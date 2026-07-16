import Foundation

/// A small abstract-value lattice for intra-block data-flow. Deliberately tiny:
/// enough to recover constants and `adrp`/`add` addresses flowing into calls.
public enum AbstractValue: Equatable, Sendable {
    case unknown
    case immediate(UInt64)
    case address(UInt64)
    /// The return value (x0) of the call at this instruction address — lets a
    /// result flow into a later call's argument as a nested expression.
    case callResult(UInt64)
    /// The *contents* of the given address, loaded by an `ldr` from a known
    /// base. Only meaningful once something resolves what lives there (an
    /// `__objc_selrefs` slot, say); callers that can't resolve it should treat
    /// it as `.unknown`.
    case loaded(UInt64)
    /// A frame-relative address: the stack pointer on function entry, plus this
    /// (usually negative) offset.
    ///
    /// Keying stack slots off a symbolic frame base rather than a literal `sp`
    /// value is what lets them survive the prologue's `sub sp, sp, #k` and
    /// `stp …, [sp, #-k]!` — after those, the same local is at a different `sp`
    /// offset, but the same frame offset.
    case frame(Int64)
}

/// The values reaching one call, snapshotted just before it executes.
public struct CallSite: Equatable, Sendable {
    /// x0–x7, trailing unknowns trimmed.
    public var arguments: [AbstractValue] = []
    /// x20 — `self` under the Swift calling convention. Meaningless for a
    /// non-Swift callee, where x20 is just another callee-saved register, so
    /// only render it once the callee is known to be Swift.
    public var selfValue: AbstractValue = .unknown
    /// x21 — the Swift error result register.
    public var errorValue: AbstractValue = .unknown
    /// x8 — AAPCS64's indirect result buffer, used for returns too large for x0.
    public var indirectResult: AbstractValue = .unknown

    /// Whether nothing at all was inferred (so there's nothing worth showing).
    public var isEmpty: Bool {
        arguments.isEmpty && selfValue == .unknown
            && errorValue == .unknown && indirectResult == .unknown
    }
}

/// An abstract interpreter over a function's basic blocks. Propagates constants,
/// addresses, and frame-relative stack slots through registers, and snapshots
/// the argument registers at each call.
public struct ValueTracer: Sendable {
    public init() {}

    /// Register and stack-slot values. Register keys are canonical names
    /// (`x3`, `sp`); stack slots are keyed by frame offset (see `stackKey`), so
    /// both live in one map and flow through the same meet.
    private typealias State = [String: AbstractValue]

    /// Entry state: `sp` anchors the frame at offset 0.
    private static var initialState: State { ["sp": .frame(0)] }

    /// Map of call-instruction address → the values reaching that call.
    /// Calls where nothing could be inferred are omitted.
    ///
    /// A forward data-flow fixpoint over the CFG carries values across basic
    /// blocks (e.g. callee-saved x19–x28 holding `self`/locals), so an argument
    /// set before a branch is still recovered at a call after it.
    public func callSites(in function: DisassembledFunction) -> [UInt64: CallSite] {
        let blocks = function.basicBlocks()
        guard !blocks.isEmpty else { return [:] }
        let blockByStart = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })

        var predecessors: [UInt64: [UInt64]] = [:]
        for block in blocks {
            for successor in block.successors where blockByStart[successor] != nil {
                predecessors[successor, default: []].append(block.startAddress)
            }
        }

        // Forward fixpoint: block entry state = meet of predecessors' exit states.
        var inState: [UInt64: State] = [:]
        var outState: [UInt64: State] = [:]
        var worklist = blocks.map(\.startAddress)
        var queued = Set(worklist)
        var iterations = 0
        let cap = blocks.count * 64 + 16 // safety bound; the analysis is monotone
        while let addr = worklist.first {
            worklist.removeFirst()
            queued.remove(addr)
            iterations += 1
            if iterations > cap { break }
            guard let block = blockByStart[addr] else { continue }
            let preds = predecessors[addr] ?? []
            // No predecessors: the entry block (or unreachable code) — start from
            // the frame anchor rather than an empty state.
            let entry = preds.isEmpty ? Self.initialState : Self.meet(preds.compactMap { outState[$0] })
            inState[addr] = entry
            var registers = entry
            for insn in block.instructions { transfer(insn, into: &registers, record: nil) }
            if outState[addr] != registers {
                outState[addr] = registers
                for successor in block.successors
                where blockByStart[successor] != nil && !queued.contains(successor) {
                    worklist.append(successor)
                    queued.insert(successor)
                }
            }
        }

        // Snapshot pass: replay from each block's fixed entry state, recording args.
        var result: [UInt64: CallSite] = [:]
        for block in blocks {
            var registers = inState[block.startAddress] ?? [:]
            for insn in block.instructions {
                transfer(insn, into: &registers) { result[$0] = $1 }
            }
        }
        return result
    }

    /// Run the transfer function over a short, straight-line instruction
    /// sequence from an empty state and return the resulting registers. Used to
    /// decode stub bodies, which are branch-free by construction.
    public func finalState(of instructions: [Instruction]) -> [String: AbstractValue] {
        var registers: State = [:]
        for insn in instructions { transfer(insn, into: &registers, record: nil) }
        return registers
    }

    /// The instruction's mnemonic and destination register, for callers that
    /// need to recognise a specific instruction shape.
    public static func destination(of insn: Instruction) -> (mnemonic: String, register: String)? {
        let (mnemonic, operands) = decode(insn.text)
        guard let first = operands.first, let dest = register(first) else { return nil }
        return (mnemonic, dest)
    }

    /// One instruction's effect on the register state. At a call, snapshot the
    /// argument registers (via `record`) then apply AAPCS64 clobbering.
    private func transfer(
        _ insn: Instruction,
        into registers: inout State,
        record: ((UInt64, CallSite) -> Void)?
    ) {
        if insn.controlFlow == .call {
            if let record {
                let args = (0...7).map { registers["x\($0)"] ?? .unknown }
                let site = CallSite(
                    arguments: Self.trimTrailingUnknown(args) ?? [],
                    // Only when freshly set for *this* call — see selfFreshKey.
                    selfValue: registers[Self.selfFreshKey] != nil
                        ? (registers["x20"] ?? .unknown) : .unknown,
                    errorValue: registers["x21"] ?? .unknown,
                    indirectResult: registers["x8"] ?? .unknown
                )
                if !site.isEmpty { record(insn.address, site) }
            }
            // AAPCS64: x0–x17 are caller-saved, so a call clobbers them. x18 is
            // reserved, x19–x28 are callee-saved — and preserving those is what
            // carries `self` and locals across a call.
            for index in 1...17 { registers["x\(index)"] = .unknown }
            registers["x30"] = .unknown
            registers["x0"] = .callResult(insn.address) // return value
            registers[Self.selfFreshKey] = nil
            return
        }
        let hadSelf = registers[Self.selfFreshKey]
        apply(insn, into: &registers)
        if Self.writesSwiftSelf(insn) {
            registers[Self.selfFreshKey] = .immediate(1)
        } else {
            registers[Self.selfFreshKey] = hadSelf
        }
    }

    /// Marks that x20 was written since the last call, i.e. that the caller set
    /// it up *for the upcoming call*.
    ///
    /// x20 is callee-saved, so a value placed there for one call survives into
    /// later ones. Without this, a Swift callee whose `self` isn't in x20 at all
    /// — `Double.write(to:)`, whose self is a Double in d0 — would inherit the
    /// previous call's x20 and report it as its own `self`. Requiring a fresh
    /// write trades a missed `self` (when the compiler doesn't re-materialise an
    /// unchanged x20) for never inventing one.
    private static let selfFreshKey = "swiftself.fresh"

    private static func writesSwiftSelf(_ insn: Instruction) -> Bool {
        guard let (mnemonic, register) = destination(of: insn), register == "x20" else { return false }
        // `str x20, [sp, #n]` names x20 first but reads it.
        return !mnemonic.hasPrefix("st") && !nonWritingMnemonics.contains(mnemonic)
    }

    /// Meet (∧) of predecessor states: a register keeps its value only when all
    /// predecessors agree; otherwise it becomes unknown (absent).
    private static func meet(_ states: [State]) -> State {
        guard var accumulator = states.first else { return [:] }
        for state in states.dropFirst() {
            accumulator = accumulator.filter { state[$0.key] == $0.value }
        }
        return accumulator
    }

    /// Decode a Swift `_SmallString` passed in two registers (x0 = low 8 bytes,
    /// x1 = high 8 bytes, with the count in the top byte's low nibble and the
    /// `0xE` small-string discriminator in its high nibble). Returns the text
    /// when it decodes to printable UTF-8, else nil.
    public static func decodeSmallString(lo: UInt64, hi: UInt64) -> String? {
        let discriminator = UInt8(truncatingIfNeeded: hi >> 56)
        guard (discriminator & 0xF0) == 0xE0 else { return nil }
        let count = Int(discriminator & 0x0F)
        guard (1...15).contains(count) else { return nil }

        var bytes: [UInt8] = []
        for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: lo >> shift)) }
        for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: hi >> shift)) }
        let content = Array(bytes.prefix(count))
        guard content.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return nil }
        return String(decoding: content, as: UTF8.self)
    }

    // MARK: - Transfer function

    private func apply(_ insn: Instruction, into registers: inout [String: AbstractValue]) {
        let (mnemonic, operands) = Self.decode(insn.text)

        func clobberDestination() {
            if let first = operands.first, let dest = Self.register(first), dest != "xzr" {
                registers[dest] = .unknown
            }
        }

        switch mnemonic {
        case "adrp":
            guard let first = operands.first, let dest = Self.register(first) else {
                clobberDestination(); return
            }
            // objdump keeps the resolved page in a trailing `; 0x…` comment;
            // Capstone puts it straight in the operand.
            let page = Self.trailingHexComment(insn.text)
                ?? (operands.count >= 2 ? Self.hexOperand(operands[1]) : nil)
            guard let page else { clobberDestination(); return }
            registers[dest] = .address(page)

        case "add", "sub":
            guard operands.count >= 3, let dest = Self.register(operands[0]) else { clobberDestination(); return }
            guard let imm = Self.immediate(operands[2]) else { registers[dest] = .unknown; return }
            let delta = Int64(bitPattern: imm)
            switch value(of: operands[1], in: registers) {
            case .address(let a): registers[dest] = .address(mnemonic == "add" ? a &+ imm : a &- imm)
            case .immediate(let v): registers[dest] = .immediate(mnemonic == "add" ? v &+ imm : v &- imm)
            case .frame(let f): registers[dest] = .frame(mnemonic == "add" ? f &+ delta : f &- delta)
            case .unknown, .callResult, .loaded: registers[dest] = .unknown
            }

        // Only the full 64-bit forms: a sub-word load (`ldrb`/`ldrh`/`ldrsw`)
        // can't produce a pointer, so it falls through to the default clobber.
        case "ldr", "ldur":
            guard let first = operands.first, let dest = Self.register(first) else {
                clobberDestination(); return
            }
            let slot = frameSlot(operands, in: registers)
            let address = memoryAddress(operands, in: registers)
            applyWriteback(operands, into: &registers)
            if let slot {
                registers[dest] = registers[slot] ?? .unknown
            } else {
                registers[dest] = address.map { AbstractValue.loaded($0) } ?? .unknown
            }

        // A store writes memory, not a register — but it does populate a stack
        // slot, which is how a value materialized before a branch reaches a call
        // after it (`str x0, [sp, #n]` … `ldr x20, [sp, #n]`).
        case "str", "stur":
            if let slot = frameSlot(operands, in: registers), let first = operands.first {
                registers[slot] = value(of: first, in: registers)
            }
            applyWriteback(operands, into: &registers)

        case "mov", "movz":
            guard let first = operands.first, let dest = Self.register(first), operands.count >= 2 else {
                clobberDestination(); return
            }
            if let imm = Self.immediate(operands[1]) {
                registers[dest] = .immediate(imm)
            } else {
                registers[dest] = value(of: operands[1], in: registers) // register copy
            }

        case "movk":
            guard let first = operands.first, let dest = Self.register(first),
                  operands.count >= 2, let imm = Self.immediate(operands[1])
            else { clobberDestination(); return }
            let shift = operands.count >= 3 ? Self.lslShift(operands[2]) : 0
            let base: UInt64 = { if case .immediate(let v) = registers[dest] { return v } else { return 0 } }()
            let mask = ~(UInt64(0xffff) << shift)
            registers[dest] = .immediate((base & mask) | (imm << shift))

        default:
            // Stores, compares, and branches don't write their register
            // operands — leaving their values intact matters for cross-block flow.
            // Stores still need writeback applied: `stp x29, x30, [sp, #-0x70]!`
            // is the standard prologue, and missing it desynchronises the frame
            // for every stack slot that follows.
            if mnemonic.hasPrefix("st") {
                applyWriteback(operands, into: &registers)
                return
            }
            if mnemonic.hasPrefix("b.") || Self.nonWritingMnemonics.contains(mnemonic) {
                return
            }
            // Pair loads write two destination registers.
            if mnemonic.hasPrefix("ldp") || mnemonic.hasPrefix("ldnp") {
                for operand in operands.prefix(2) {
                    if let reg = Self.register(operand), reg != "xzr" { registers[reg] = .unknown }
                }
                applyWriteback(operands, into: &registers)
                return
            }
            // Most remaining instructions write (only) their first operand.
            clobberDestination()
        }
    }

    private static let nonWritingMnemonics: Set<String> = [
        "cmp", "cmn", "tst", "ccmp", "ccmn",
        "b", "bl", "br", "blr", "ret", "cbz", "cbnz", "tbz", "tbnz",
        "brk", "nop", "svc", "hlt", "dmb", "dsb", "isb", "prfm", "prfum",
        // Pointer-auth branches. These *read* their register operand — arm64e
        // stubs end in `braa x16, x17`, and without these the default clobber
        // would wipe x16, the very value the stub resolved.
        "braa", "braaz", "brab", "brabz",
        "blraa", "blraaz", "blrab", "blrabz",
        "retaa", "retab",
    ]

    private func value(of token: String, in registers: [String: AbstractValue]) -> AbstractValue {
        guard let reg = Self.register(token) else { return .unknown }
        if reg == "xzr" { return .immediate(0) }
        return registers[reg] ?? .unknown
    }

    /// Index of the operand that opens the memory reference. `str` puts it
    /// second, `stp`/`ldp` third — so find it rather than assuming.
    private static func memoryOperandIndex(_ operands: [String]) -> Int? {
        operands.firstIndex { $0.hasPrefix("[") }
    }

    /// Decompose a memory operand into its base token and immediate offset.
    ///
    /// The bracket distinguishes the addressing modes: an offset/pre-index
    /// operand splits across the comma as `[xB` + `#imm]`, so the base token has
    /// no `]`; a bare `[xB]` or a post-index `[xB], #imm` closes on the base
    /// token and accesses the base itself. Register-offset forms (`[xB, xC]`)
    /// have no immediate and stay unresolved.
    private static func memoryOperand(_ operands: [String]) -> (base: String, offset: Int64)? {
        guard let index = memoryOperandIndex(operands) else { return nil }
        let baseToken = operands[index]
        if baseToken.hasSuffix("]") { return (baseToken, 0) }
        guard index + 1 < operands.count,
              let offset = immediate(stripBracket(operands[index + 1]))
        else { return nil }
        return (baseToken, Int64(bitPattern: offset))
    }

    /// The concrete address a memory operand reads, when its base holds a known
    /// absolute address.
    private func memoryAddress(_ operands: [String], in registers: State) -> UInt64? {
        guard let (baseToken, offset) = Self.memoryOperand(operands),
              case .address(let base) = value(of: baseToken, in: registers)
        else { return nil }
        return base &+ UInt64(bitPattern: offset)
    }

    /// The state key for a frame-relative memory operand (`[sp, #0x70]`), when
    /// the base register holds a frame offset.
    private func frameSlot(_ operands: [String], in registers: State) -> String? {
        guard let (baseToken, offset) = Self.memoryOperand(operands),
              case .frame(let base) = value(of: baseToken, in: registers)
        else { return nil }
        return Self.stackKey(base &+ offset)
    }

    /// Stack slots share the register map, under a key no register can collide
    /// with.
    private static func stackKey(_ frameOffset: Int64) -> String { "stack@\(frameOffset)" }

    /// Apply a writeback/post-index memory operand's effect on its base register.
    private func applyWriteback(_ operands: [String], into registers: inout State) {
        guard let index = Self.memoryOperandIndex(operands),
              let base = Self.register(operands[index]),
              index + 1 < operands.count
        else { return }
        let isPostIndex = operands[index].hasSuffix("]")
        let isPreIndex = operands[index + 1].contains("!")
        guard isPostIndex || isPreIndex else { return }
        guard let immediate = Self.immediate(Self.stripBracket(operands[index + 1])) else {
            registers[base] = .unknown
            return
        }
        let delta = Int64(bitPattern: immediate)
        switch registers[base] {
        case .frame(let offset): registers[base] = .frame(offset &+ delta)
        case .address(let address): registers[base] = .address(address &+ UInt64(bitPattern: delta))
        default: registers[base] = .unknown
        }
    }

    private static func stripBracket(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "]!"))
    }

    // MARK: - Parsing

    static func decode(_ text: String) -> (mnemonic: String, operands: [String]) {
        let beforeComment = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let trimmed = beforeComment.trimmingCharacters(in: .whitespaces)
        guard let split = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return (trimmed, [])
        }
        let mnemonic = String(trimmed[..<split])
        let operands = trimmed[trimmed.index(after: split)...]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return (mnemonic, operands)
    }

    /// Canonical 64-bit register name (`w3`→`x3`), the `xzr` zero sentinel, or
    /// `sp` (tracked because it anchors the frame); nil for anything else.
    static func register(_ token: String) -> String? {
        let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "[]!"))
        if t == "xzr" || t == "wzr" { return "xzr" }
        if t == "sp" || t == "wsp" { return "sp" }
        guard let first = t.first, first == "x" || first == "w",
              t.dropFirst().allSatisfy(\.isNumber), t.count > 1
        else { return nil }
        return "x" + t.dropFirst()
    }

    static func immediate(_ token: String) -> UInt64? {
        guard token.hasPrefix("#") else { return nil }
        var s = Substring(token.dropFirst())
        let negative = s.hasPrefix("-")
        if negative { s = s.dropFirst() }
        let value = s.hasPrefix("0x") ? UInt64(s.dropFirst(2), radix: 16) : UInt64(s)
        guard let v = value else { return nil }
        return negative ? (~v &+ 1) : v
    }

    private static func lslShift(_ token: String) -> UInt64 {
        guard let range = token.range(of: "#") else { return 0 }
        return UInt64(token[range.upperBound...].prefix { $0.isNumber }) ?? 0
    }

    /// The `0x…` value in objdump's trailing `; 0x…` comment (adrp page).
    private static func trailingHexComment(_ text: String) -> UInt64? {
        guard let range = text.range(of: "; 0x")?.upperBound else { return nil }
        return UInt64(text[range...].prefix { $0.isHexDigit }, radix: 16)
    }

    /// A bare `0x…` operand (Capstone renders a resolved adrp page this way).
    private static func hexOperand(_ token: String) -> UInt64? {
        let s = token.trimmingCharacters(in: CharacterSet(charactersIn: "#[], "))
        guard s.hasPrefix("0x") else { return nil }
        return UInt64(s.dropFirst(2), radix: 16)
    }

    static func trimTrailingUnknown(_ values: [AbstractValue]) -> [AbstractValue]? {
        guard let last = values.lastIndex(where: { $0 != .unknown }) else { return nil }
        return Array(values[0...last])
    }
}
