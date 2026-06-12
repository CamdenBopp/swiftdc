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
}

/// An abstract interpreter over a function's basic blocks. Propagates constants
/// and addresses through registers and snapshots the argument registers (x0–x7)
/// at each call. Block-local (state resets per block) — a sound local
/// approximation, since arguments are almost always materialized in the same
/// block as the call.
public struct ValueTracer: Sendable {
    public init() {}

    private typealias State = [String: AbstractValue]

    /// Map of call-instruction address → recovered argument values (x0…),
    /// trailing-unknowns trimmed. Calls with no inferable argument are omitted.
    ///
    /// A forward data-flow fixpoint over the CFG carries values across basic
    /// blocks (e.g. callee-saved x19–x28 holding `self`/locals), so an argument
    /// set before a branch is still recovered at a call after it.
    public func callArguments(in function: DisassembledFunction) -> [UInt64: [AbstractValue]] {
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
            let entry = Self.meet((predecessors[addr] ?? []).compactMap { outState[$0] })
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
        var result: [UInt64: [AbstractValue]] = [:]
        for block in blocks {
            var registers = inState[block.startAddress] ?? [:]
            for insn in block.instructions {
                transfer(insn, into: &registers) { result[$0] = $1 }
            }
        }
        return result
    }

    /// One instruction's effect on the register state. At a call, snapshot the
    /// argument registers (via `record`) then apply AAPCS64 clobbering.
    private func transfer(
        _ insn: Instruction,
        into registers: inout State,
        record: ((UInt64, [AbstractValue]) -> Void)?
    ) {
        if insn.controlFlow == .call {
            if let record {
                let args = (0...7).map { registers["x\($0)"] ?? .unknown }
                if let trimmed = Self.trimTrailingUnknown(args) { record(insn.address, trimmed) }
            }
            for index in 1...17 { registers["x\(index)"] = .unknown }
            registers["x30"] = .unknown
            registers["x0"] = .callResult(insn.address) // return value
            return
        }
        apply(insn, into: &registers)
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
            guard let first = operands.first, let dest = Self.register(first),
                  let page = Self.trailingHexComment(insn.text)
            else { clobberDestination(); return }
            registers[dest] = .address(page)

        case "add", "sub":
            guard operands.count >= 3, let dest = Self.register(operands[0]) else { clobberDestination(); return }
            guard let imm = Self.immediate(operands[2]) else { registers[dest] = .unknown; return }
            switch value(of: operands[1], in: registers) {
            case .address(let a): registers[dest] = .address(mnemonic == "add" ? a &+ imm : a &- imm)
            case .immediate(let v): registers[dest] = .immediate(mnemonic == "add" ? v &+ imm : v &- imm)
            case .unknown, .callResult: registers[dest] = .unknown
            }

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
            if mnemonic.hasPrefix("st") || mnemonic.hasPrefix("b.")
                || Self.nonWritingMnemonics.contains(mnemonic) {
                return
            }
            // Pair loads write two destination registers.
            if mnemonic.hasPrefix("ldp") || mnemonic.hasPrefix("ldnp") {
                for operand in operands.prefix(2) {
                    if let reg = Self.register(operand), reg != "xzr" { registers[reg] = .unknown }
                }
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
    ]

    private func value(of token: String, in registers: [String: AbstractValue]) -> AbstractValue {
        guard let reg = Self.register(token) else { return .unknown }
        if reg == "xzr" { return .immediate(0) }
        return registers[reg] ?? .unknown
    }

    // MARK: - Parsing

    private static func decode(_ text: String) -> (mnemonic: String, operands: [String]) {
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

    /// Canonical 64-bit register name (`w3`→`x3`), or "xzr"/"wzr" sentinel; nil
    /// for sp/non-registers.
    private static func register(_ token: String) -> String? {
        let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "[]!"))
        if t == "xzr" || t == "wzr" { return "xzr" }
        guard let first = t.first, first == "x" || first == "w",
              t.dropFirst().allSatisfy(\.isNumber), t.count > 1
        else { return nil }
        return "x" + t.dropFirst()
    }

    private static func immediate(_ token: String) -> UInt64? {
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

    private static func trimTrailingUnknown(_ values: [AbstractValue]) -> [AbstractValue]? {
        guard let last = values.lastIndex(where: { $0 != .unknown }) else { return nil }
        return Array(values[0...last])
    }
}
