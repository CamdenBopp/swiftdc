import Foundation

/// A basic block: a maximal straight-line run of instructions with a single
/// entry and a single exit, plus the addresses it can flow to.
public struct BasicBlock: Sendable {
    public let startAddress: UInt64
    public let instructions: [Instruction]
    /// Start addresses this block can transfer control to (branch target and/or
    /// fall-through). External (out-of-function) targets are included as-is.
    public let successors: [UInt64]
}

public extension DisassembledFunction {
    /// Recover the function's basic blocks from Capstone control-flow info.
    /// Requires instructions to carry `controlFlow` (the Capstone-enriched path);
    /// otherwise returns a single block.
    func basicBlocks() -> [BasicBlock] {
        guard !instructions.isEmpty else { return [] }
        let internalAddresses = Set(instructions.map(\.address))

        // 1. Leaders: entry, branch targets (internal), and the instruction
        //    following any block-terminating control flow.
        var leaders: Set<UInt64> = [instructions[0].address]
        for (index, insn) in instructions.enumerated() {
            switch insn.controlFlow {
            case .branch, .conditionalBranch, .return:
                if index + 1 < instructions.count {
                    leaders.insert(instructions[index + 1].address)
                }
                if let target = insn.branchTarget, internalAddresses.contains(target) {
                    leaders.insert(target)
                }
            case .call, .sequential, .none:
                break
            }
        }

        // 2. Cut the instruction stream at the leaders.
        var blocks: [BasicBlock] = []
        var current: [Instruction] = []

        func flush(fallthrough next: UInt64?) {
            guard let first = current.first, let last = current.last else { return }
            blocks.append(
                BasicBlock(
                    startAddress: first.address,
                    instructions: current,
                    successors: Self.successors(of: last, fallthrough: next)
                )
            )
            current = []
        }

        for insn in instructions {
            if !current.isEmpty, leaders.contains(insn.address) {
                flush(fallthrough: insn.address)
            }
            current.append(insn)
        }
        flush(fallthrough: nil)
        return blocks
    }

    private static func successors(of last: Instruction, fallthrough next: UInt64?) -> [UInt64] {
        switch last.controlFlow {
        case .return:
            return []
        case .branch:
            return last.branchTarget.map { [$0] } ?? []
        case .conditionalBranch:
            return [last.branchTarget, next].compactMap { $0 }
        case .call, .sequential, .none:
            // A trap (`brk`/`udf`) never returns or falls through; Capstone
            // classifies it as sequential, so drop the spurious fall-through edge
            // that would otherwise make the trap sink look like ordinary code.
            if isTrapInstruction(last) { return [] }
            return next.map { [$0] } ?? []
        }
    }

    private static func isTrapInstruction(_ insn: Instruction) -> Bool {
        let mnemonic = insn.text.prefix { $0 != " " && $0 != "\t" }
        return mnemonic == "brk" || mnemonic == "udf" || mnemonic == "trap"
    }

    /// Render the function as a control-flow graph: basic blocks with `loc_<addr>`
    /// labels and successor edges.
    func renderCFG() -> String {
        var lines = ["\(displayName):  // \(symbol) @ 0x\(String(startAddress, radix: 16))"]
        if let objcMethod { lines.append("  // \(objcMethod.signature)") }
        for block in basicBlocks() {
            lines.append("  loc_\(String(block.startAddress, radix: 16)):")
            for insn in block.instructions {
                var line = "    \(String(insn.address, radix: 16)):  \(insn.text)"
                if let annotation = insn.annotation, !insn.text.contains(annotation) {
                    line += "  ; \(annotation)"
                }
                lines.append(line)
            }
            if !block.successors.isEmpty {
                let edges = block.successors.map { "loc_\(String($0, radix: 16))" }.joined(separator: ", ")
                lines.append("    → \(edges)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
