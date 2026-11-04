import Foundation
import MachOKit
import ObjCDump

extension ObjCDumper {
    /// A property's accessor: the object type the method encoding drops (an
    /// accessor's return/argument is encoded only as `@`/`id`), and whether this
    /// selector is the setter.
    struct PropertyAccessor {
        let type: String
        let isSetter: Bool
    }

    /// Rewrite a class header so property-backed accessors read like a real
    /// header. A declared `@property` already implies its getter and setter, so a
    /// *synthesized* accessor (a trivial ivar load/store) is redundant and
    /// dropped; a *custom* accessor is genuine code, so it is kept and given the
    /// object type recovered from the property.
    ///
    /// `isSynthesized(imp)` is the disassembly-backed oracle: `true` = trivial
    /// (suppress), `false` = custom (keep + type), `nil` = unknown — no disasm on
    /// this architecture, so treat every property-backed accessor as synthesized,
    /// which is class-dump's metadata-only behaviour. `unknown: .marked` keeps
    /// such an accessor instead, typed from its property (the metadata proves
    /// that much) and ending with the note for its IMP: dropping it says the
    /// `@property` covers all there is, which only its body can show.
    static func rewritingPropertyAccessors(
        _ header: String,
        class info: ObjCClassInfo,
        unknown: UnknownAccessor = .dropped,
        isSynthesized: (UInt64) -> Bool?
    ) -> String {
        guard !info.properties.isEmpty, !info.methods.isEmpty else { return header }
        let accessors = propertyAccessors(info.properties)
        guard !accessors.isEmpty else { return header }

        var suppress: Set<String> = []      // exact header lines to drop
        var retype: [String: String] = [:]  // old line → typed line

        for method in info.methods where !method.isClassMethod {
            guard let accessor = accessors[method.name] else { continue }
            let line = method.headerString
            let verdict = isSynthesized(method.imp)
            if verdict == false {
                let typed = retyping(line, accessor: accessor)
                if typed != line { retype[line] = typed }
            } else if verdict == nil, case .marked(let note) = unknown {
                retype[line] = retyping(line, accessor: accessor) + " " + note(method.imp)
            } else {
                suppress.insert(line)
            }
        }
        guard !suppress.isEmpty || !retype.isEmpty else { return header }

        // Each method renders as its own `headerString` line, so whole-line
        // matching rewrites exactly the accessor lines and nothing else.
        let lines = header.components(separatedBy: "\n").compactMap { line -> String? in
            if suppress.contains(line) { return nil }
            return retype[line] ?? line
        }
        return lines.joined(separator: "\n")
    }

    /// What the header does with an accessor no body has classified.
    enum UnknownAccessor {
        /// Left to its `@property`, as class-dump does.
        case dropped
        /// Kept, ending with the note for its raw IMP.
        case marked((UInt64) -> String)
    }

    /// Ends the line of an accessor `objc --metadata-only` did not classify:
    /// it may be synthesized or custom.
    static let unclassifiedAccessorNote = "// unclassified accessor: body not analyzed"

    /// The same, for the two ways the default header gets no verdict: the
    /// entry block ran off the decoded prefix, or no code was found at the
    /// IMP. One note for both would read as one cause.
    static let declinedAccessorNote = "// unclassified accessor: body runs past the 4 KB decode limit"
    static let undecodedAccessorNote = "// unclassified accessor: no body decoded"

    /// Selector → accessor descriptor for every getter and setter a property
    /// declares, honouring `getter=`/`setter=` and `readonly`.
    private static func propertyAccessors(_ properties: [ObjCPropertyInfo]) -> [String: PropertyAccessor] {
        var result: [String: PropertyAccessor] = [:]
        for property in properties {
            let attributes = property.attributes
            let type = attributes.compactMap { attribute -> String? in
                if case let .type(type) = attribute, let type { return type.decodedStringForArgument }
                return nil
            }.first
            guard let type else { continue }

            let customGetter = attributes.compactMap { attribute -> String? in
                if case let .getter(name) = attribute { return name } else { return nil }
            }.first
            result[customGetter ?? property.name] = PropertyAccessor(type: type, isSetter: false)

            guard !attributes.contains(.readonly) else { continue }
            let customSetter = attributes.compactMap { attribute -> String? in
                if case let .setter(name) = attribute { return name } else { return nil }
            }.first
            let setter = customSetter ?? "set\(capitalizingFirst(property.name)):"
            result[setter] = PropertyAccessor(type: type, isSetter: true)
        }
        return result
    }

    private static func capitalizingFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.uppercased() + string.dropFirst()
    }

    /// Give a kept custom accessor the object type its encoding dropped:
    /// `- (id)name;` → `- (NSString *)name;`,
    /// `- (void)setName:(id)arg0;` → `- (void)setName:(NSString *)arg0;`.
    /// Only the untyped `id` is substituted; an accessor whose type the encoding
    /// already carries (a scalar like `int`) is left as-is.
    private static func retyping(_ line: String, accessor: PropertyAccessor) -> String {
        guard accessor.type != "id" else { return line }
        if accessor.isSetter {
            return line.replacingOccurrences(of: "(id)arg0", with: "(\(accessor.type))arg0")
        }
        return line.replacingOccurrences(of: "- (id)", with: "- (\(accessor.type))")
    }

    /// Disassemble every property-backed accessor and classify it: `true` =
    /// synthesized (a trivial ivar load/store its @property already covers),
    /// `false` = custom (real code, keep and type it), nil = the classifier
    /// declined. Keyed by the raw `ObjCMethodInfo.imp` so
    /// `rewritingPropertyAccessors` can look it up; an IMP with no key decoded
    /// nothing.
    /// How much of an IMP's extent is decoded to classify an accessor: 1,024
    /// instructions, far past any synthesized getter or setter.
    static let accessorPrefixBytes: UInt64 = 4096

    static func classifyAccessors(
        _ snapshot: ObjCMetadataSnapshot,
        in machO: MachOFile,
        disassembler: Disassembler
    ) async -> [UInt64: Bool?] {
        let rawToRuntime = accessorImplementations(snapshot, in: machO)
        guard !rawToRuntime.isEmpty else { return [:] }

        // Only a prefix of each extent: the accessor is the block its entry
        // starts, a handful of instructions. Each body is classified and
        // released before the next is decoded: only the verdicts stay.
        let byAddress = await disassembler.analyzeEachFunction(
            at: Set(rawToRuntime.values), in: machO, prefixBytes: Self.accessorPrefixBytes
        ) { function -> Bool?? in
            .some(isSynthesizedAccessor(function, prefixBytes: Self.accessorPrefixBytes))
        }

        var result: [UInt64: Bool?] = [:]
        for (raw, runtime) in rawToRuntime {
            if let verdict = byAddress[runtime] { result[raw] = verdict }
        }
        return result
    }

    /// Every property-backed instance accessor's IMP: the raw
    /// `ObjCMethodInfo.imp` the rewriter looks up, to the address its body
    /// starts at.
    static func accessorImplementations(_ snapshot: ObjCMetadataSnapshot, in machO: MachOFile) -> [UInt64: UInt64] {
        var rawToRuntime: [UInt64: UInt64] = [:]
        for cls in snapshot.classes {
            let accessors = propertyAccessors(cls.properties)
            guard !accessors.isEmpty else { continue }
            for method in cls.methods
            where !method.isClassMethod && accessors[method.name] != nil {
                if let runtime = ObjCMetadataIndex.implementationAddress(of: method.imp, in: machO) {
                    rawToRuntime[method.imp] = runtime
                }
            }
        }
        return rawToRuntime
    }

    /// Whether a disassembled accessor body is synthesized: the block its
    /// entry starts ends it (a return, or a tail call), with no branch to
    /// other code, and its only calls are ARC / property-storage runtime
    /// helpers. Anything that sends a message, calls another function, or has
    /// control flow is custom and worth keeping. Only that block is the
    /// accessor: what follows it in the decoded extent is another function
    /// or padding, and judging by the whole extent called a synthesized
    /// setter followed by a 6 KB function custom (`accessorextent.m`). Nil
    /// when the block runs past a decode `prefixBytes` cut short; a block
    /// that runs into the next function (after a call that does not return)
    /// is no accessor's shape, so it is custom.
    ///
    /// And it touches the ivar: a load or store addressed from `self` (or a
    /// copy of it), or a property-storage helper. A getter
    /// that returns a constant, `mov w0, #-1; ret`, is one block with no
    /// call, and read as synthesized: its line was dropped.
    ///
    /// And it moves the value unchanged (`AccessorValueFlow`): a clamp, `csel
    /// w8, w2, w8, lt; str w8, [x0, #8]; ret`, is one block that stores
    /// through self, and read as synthesized too.
    static func isSynthesizedAccessor(_ function: DisassembledFunction, prefixBytes: UInt64? = nil) -> Bool? {
        let cfg = FunctionCFG(function)
        guard let entry = cfg.entry else { return nil }
        let block = cfg.blocks[entry]
        let last = function.instructions[block.terminator]
        if last.controlFlow == .conditionalBranch || !block.successorIDs.isEmpty { return false }
        let fallsThrough = !last.isTrap && [.call, .sequential, .none].contains(last.controlFlow)
        if fallsThrough {
            let cut = prefixBytes.map { last.address + 4 - function.startAddress >= $0 } ?? false
            return block.terminator == function.instructions.count - 1 && cut ? nil : false
        }
        // The registers holding `self` or an address in it: x0 at entry, a
        // `mov` copy (a Swift `@objc` thunk keeps self in x19 across
        // `swift_beginAccess`), and an `add` to it (a non-fragile ivar,
        // `add x8, x0, x8; ldr x0, [x8]`), and a reload of a stack slot self
        // was spilled to. Any other write ends one, and a call ends every one
        // but the callee-saved x19 to x28.
        var touchesIvar = false, selfRegisters: Set<Int> = [0], selfSlots: Set<Int64> = []
        var flow = AccessorValueFlow(
            movesAggregate: function.objcMethod.map { $0.typeEncoding.contains("{") || $0.typeEncoding.contains("(") } ?? false)
        for insn in function.instructions[block.range] {
            let operands = insn.detail?.operands ?? []
            if let detail = insn.detail, !flow.admits(insn.text, detail, selfRegisters: selfRegisters) { return false }
            // -O0 spills self to the stack and reloads it: `str x0, [sp, #8]`
            // … `ldr x8, [sp, #8]`.
            var reloaded: Int?
            if operands.count == 2, case .register(let register) = operands[0].operand, register.kind == .gpr,
               register.widthBits == 64, case .memory(let base?, nil, let offset) = operands[1].operand,
               base.kind == .stackPointer, insn.detail?.writeback == false {
                if insn.text.hasPrefix("str"), selfRegisters.contains(register.number) { selfSlots.insert(offset) }
                if insn.text.hasPrefix("ldr"), selfSlots.contains(offset) { reloaded = register.number }
            }
            if operands.contains(where: { operand in
                guard case .memory(let base?, _, _) = operand.operand else { return false }
                return base.kind == .gpr && base.widthBits == 64 && selfRegisters.contains(base.number)
            }) {
                touchesIvar = true
            }
            if insn.controlFlow == .call {
                selfRegisters = selfRegisters.filter { (19...28).contains($0) }
                flow.endCall()
            }
            if let detail = insn.detail {
                let copied: Int? = {
                    guard insn.text.hasPrefix("mov") && operands.count == 2 || insn.text.hasPrefix("add") && operands.count == 3,
                          case .register(let destination) = operands[0].operand, destination.kind == .gpr,
                          destination.widthBits == 64,
                          case .register(let source) = operands[1].operand, source.kind == .gpr,
                          selfRegisters.contains(source.number) else { return nil }
                    return destination.number
                }()
                for key in detail.writtenRegisterKeys {
                    if let number = Int(key.dropFirst()) { selfRegisters.remove(number) }
                }
                if let copied = copied ?? reloaded { selfRegisters.insert(copied) }
            } else {
                selfRegisters = []
            }
            guard insn.controlFlow == .call || insn.controlFlow == .branch else { continue }
            guard let callee = DisassembledFunction.calleeName(of: insn) else {
                // An unresolved call is not provably a helper — treat as custom.
                if insn.controlFlow == .call { return false }
                continue
            }
            guard isAccessorRuntimeHelper(callee) else { return false }
            if propertyStorageHelpers.contains(where: { callee.hasPrefix($0) }) { touchesIvar = true }
        }
        return touchesIvar
    }

    /// What a synthesized accessor does to its value: nothing. A setter
    /// stores its argument, once, and a getter loads the ivar; both may copy
    /// the value between registers and stack slots on the way, as -O0 does.
    /// The rest of the block is address arithmetic, which never reads the
    /// value. So an accessor is custom when it computes with the value
    /// (`cmp`, `csel`, `add`), reads memory through it (`return _node->x`),
    /// stores anything but an argument through self (a constant, an ivar) or
    /// the same argument twice (`_a = x; _b = x`), or stores anywhere but
    /// through self and the stack. A BOOL's `and w8, w8, #1` and a narrow
    /// type's extension change no value the type can hold, so they pass.
    /// A struct over 16 bytes is copied through memory: its setter reads it
    /// through the x2 it was passed by, its getter writes it through the x8
    /// the caller gave, which is what `movesAggregate` allows.
    ///
    /// Not modelled: whether the value reaches x0 at the `ret`, so a getter
    /// that loads an ivar and then returns a constant still passes.
    private struct AccessorValueFlow {
        /// Registers holding an incoming argument unchanged, to the argument
        /// register it came in. x0 is self and x1 `_cmd`; a getter that uses
        /// x2 as scratch writes it first, which ends it.
        private var arguments: [String: String] = Dictionary(
            uniqueKeysWithValues: ((2...7).map { "x\($0)" } + (0...7).map { "v\($0)" }).map { ($0, $0) })
        /// Registers holding a value loaded through self.
        private var ivarValues: Set<String> = []
        /// The same, for what a stack slot holds.
        private var argumentSlots: [String: String] = [:]
        private var ivarSlots: Set<String> = []
        /// Arguments already stored through self.
        private var storedArguments: Set<String> = []
        private let movesAggregate: Bool
        /// x8 still holds the caller's result buffer.
        private var resultBufferLive = true

        init(movesAggregate: Bool) { self.movesAggregate = movesAggregate }

        private static let loads = ["ldr", "ldur", "ldp", "ldar", "ldapr", "ldapur"]
        private static let stores = ["str", "stur", "stp", "stlr", "stlur"]
        private static let extensions: Set<String> = ["sxtb", "sxth", "sxtw", "uxtb", "uxth"]

        private func holdsValue(_ register: PhysReg?) -> Bool {
            guard let register else { return false }
            return arguments[register.key] != nil || ivarValues.contains(register.key)
        }

        private mutating func clear(_ key: String) {
            arguments[key] = nil
            ivarValues.remove(key)
            if key == "x8" { resultBufferLive = false }
        }

        /// A call leaves only the callee-saved x19 to x28.
        mutating func endCall() {
            arguments = arguments.filter { Self.survivesCall($0.key) }
            ivarValues = ivarValues.filter(Self.survivesCall)
        }

        private static func survivesCall(_ key: String) -> Bool {
            key.first == "x" && Int(key.dropFirst()).map((19...28).contains) == true
        }

        /// Steps over one instruction of the entry block; false when it does
        /// something to the value a synthesized accessor never does.
        mutating func admits(_ text: String, _ detail: StructuredInsn, selfRegisters: Set<Int>) -> Bool {
            let mnemonic = String(text.prefix { !$0.isWhitespace })
            let registers = detail.operands.compactMap { info -> (register: PhysReg, info: StructuredOperandInfo)? in
                info.operand.register.map { ($0, info) }
            }
            if let (base, index, displacement) = detail.operands.lazy.compactMap({ info -> (PhysReg?, PhysReg?, Int64)? in
                if case .memory(let base, let index, let displacement) = info.operand { return (base, index, displacement) }
                return nil
            }).first {
                return admitsMemory(
                    mnemonic, registers: registers.map(\.register), base: base, index: index,
                    displacement: displacement, writeback: detail.writeback, selfRegisters: selfRegisters)
            }
            let written = registers.filter { $0.info.isWritten }.map(\.register)
            let sources = registers.filter { $0.info.isRead && holdsValue($0.register) }.map(\.register)
            guard let source = sources.first else {
                written.forEach { clear($0.key) }
                return true
            }
            let isCopy = (mnemonic == "mov" || mnemonic == "fmov" || Self.extensions.contains(mnemonic))
                && detail.operands.count == 2
            let isBoolMask = mnemonic == "and" && detail.operands.count == 3
                && detail.operands[2].operand.immediateValue == 1
            guard isCopy || isBoolMask, sources.count == 1, written.count == 1, let destination = written.first
            else { return false }
            let origin = arguments[source.key], fromIvar = ivarValues.contains(source.key)
            clear(destination.key)
            arguments[destination.key] = origin
            if fromIvar { ivarValues.insert(destination.key) }
            return true
        }

        private mutating func admitsMemory(
            _ mnemonic: String, registers: [PhysReg], base: PhysReg?, index: PhysReg?, displacement: Int64,
            writeback: Bool, selfRegisters: Set<Int>
        ) -> Bool {
            let isLoad = Self.loads.contains(where: mnemonic.hasPrefix)
            // A word of the struct x2 points at, an argument in its own right.
            if movesAggregate, isLoad, base?.key == "x2", arguments["x2"] == "x2", index == nil, !writeback {
                for (word, register) in registers.enumerated() {
                    clear(register.key)
                    arguments[register.key] = "[x2+\(displacement)].\(word)"
                }
                return true
            }
            if movesAggregate, !isLoad, base?.key == "x8", resultBufferLive, index == nil, !writeback {
                return registers.allSatisfy { ivarValues.contains($0.key) }
            }
            if holdsValue(base) || holdsValue(index) { return false }
            let throughSelf = base.map { $0.kind == .gpr && selfRegisters.contains($0.number) } ?? false
            let onStack = base.map { $0.kind == .stackPointer || ($0.kind == .gpr && $0.number == 29) } ?? false
            let slot = base.map { "\($0.key)\(displacement)" } ?? ""
            if Self.stores.contains(where: mnemonic.hasPrefix) {
                if throughSelf {
                    return registers.allSatisfy { register in
                        guard let origin = arguments[register.key] else { return false }
                        return storedArguments.insert(origin).inserted
                    }
                }
                guard onStack else { return false }
                if registers.count == 1, !writeback, let source = registers.first {
                    argumentSlots[slot] = arguments[source.key]
                    if ivarValues.contains(source.key) { ivarSlots.insert(slot) } else { ivarSlots.remove(slot) }
                }
                return true
            }
            guard isLoad else { return !throughSelf }
            registers.forEach { clear($0.key) }
            // `[x0]` is the isa: a thunk reads a field offset through it.
            let isIsa = base?.number == 0 && index == nil && displacement == 0
            for register in registers {
                if throughSelf, !isIsa { ivarValues.insert(register.key) }
                if onStack, registers.count == 1 {
                    arguments[register.key] = argumentSlots[slot]
                    if ivarSlots.contains(slot) { ivarValues.insert(register.key) }
                }
            }
            return true
        }
    }

    /// ARC and property-storage helpers a synthesized accessor may call: the
    /// retain/release/autorelease bookkeeping `isRuntimeNoise` already knows,
    /// plus the atomic/copy accessor primitives.
    private static func isAccessorRuntimeHelper(_ callee: String) -> Bool {
        if DisassembledFunction.isRuntimeNoise(callee) { return true }
        return propertyStorageHelpers.contains { callee.hasPrefix($0) }
    }

    /// The helpers that read or write a property's storage for it.
    private static let propertyStorageHelpers = [
        "objc_storeStrong", "objc_storeWeak", "objc_loadWeakRetained",
        "objc_getProperty", "objc_setProperty", "objc_copyStruct",
        "objc_copyCppObjectAtomic", "objc_initWeak", "objc_destroyWeak",
    ]
}
