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
    /// which is class-dump's metadata-only behaviour.
    static func rewritingPropertyAccessors(
        _ header: String,
        class info: ObjCClassInfo,
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
            if isSynthesized(method.imp) == false {
                let typed = retyping(line, accessor: accessor)
                if typed != line { retype[line] = typed }
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
    /// `false` = custom (real code, keep and type it). Keyed by the raw
    /// `ObjCMethodInfo.imp` so `rewritingPropertyAccessors` can look it up.
    /// How much of an IMP's extent is decoded to classify an accessor: 1,024
    /// instructions, far past any synthesized getter or setter.
    static let accessorPrefixBytes: UInt64 = 4096

    static func classifyAccessors(
        _ snapshot: ObjCMetadataSnapshot,
        in machO: MachOFile,
        disassembler: Disassembler
    ) async -> [UInt64: Bool] {
        let rawToRuntime = accessorImplementations(snapshot, in: machO)
        guard !rawToRuntime.isEmpty else { return [:] }

        // Only a prefix of each extent: the accessor is the block its entry
        // starts, a handful of instructions. Each body is classified and
        // released before the next is decoded: only the verdicts stay.
        let byAddress = await disassembler.analyzeEachFunction(
            at: Set(rawToRuntime.values), in: machO, prefixBytes: Self.accessorPrefixBytes
        ) { function in
            isSynthesizedAccessor(function, prefixBytes: Self.accessorPrefixBytes)
        }

        var result: [UInt64: Bool] = [:]
        for (raw, runtime) in rawToRuntime {
            if let synthesized = byAddress[runtime] { result[raw] = synthesized }
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
        for insn in function.instructions[block.range] {
            let operands = insn.detail?.operands ?? []
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
            if insn.controlFlow == .call { selfRegisters = selfRegisters.filter { (19...28).contains($0) } }
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
