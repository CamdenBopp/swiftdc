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

    /// Map of call-instruction address → recovered argument values (x0…),
    /// trailing-unknowns trimmed. Calls with no inferable argument are omitted.
    public func callArguments(in function: DisassembledFunction) -> [UInt64: [AbstractValue]] {
        var result: [UInt64: [AbstractValue]] = [:]
        for block in function.basicBlocks() {
            var registers: [String: AbstractValue] = [:]
            for insn in block.instructions {
                if insn.controlFlow == .call {
                    let args = (0...7).map { registers["x\($0)"] ?? .unknown }
                    if let trimmed = Self.trimTrailingUnknown(args) {
                        result[insn.address] = trimmed
                    }
                    // AAPCS64: x0–x17 (+ LR) are caller-saved. x1–x17 become
                    // unknown; x0 now holds this call's return value, so a later
                    // use as an argument renders as a nested call.
                    for index in 1...17 { registers["x\(index)"] = .unknown }
                    registers["x30"] = .unknown
                    registers["x0"] = .callResult(insn.address)
                    continue
                }
                apply(insn, into: &registers)
            }
        }
        return result
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
            // Anything else writing a register invalidates it (conservative).
            clobberDestination()
        }
    }

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
