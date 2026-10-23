import Foundation

/// A basic block: a maximal straight-line run of instructions with a single
/// entry and a single exit, plus the addresses it can flow to.
public struct BasicBlock: Sendable {
    public let startAddress: UInt64
    public let instructions: [Instruction]
    /// Start addresses this block can transfer control to (branch target and/or
    /// fall-through). External (out-of-function) targets are included as-is.
    public let successors: [UInt64]
    /// For a block ending in a recovered jump table: the target of each case,
    /// in case order (`successors` holds them deduplicated). Nil otherwise.
    public var switchCases: [UInt64]? = nil
}

/// A CFG edge: from the last instruction of a block to a block start.
struct CFGEdge: Hashable, Sendable {
    let from: UInt64
    let to: UInt64
}

public extension DisassembledFunction {
    /// Recover the function's basic blocks from Capstone control-flow info.
    /// Requires instructions to carry `controlFlow` (the Capstone-enriched path);
    /// otherwise returns a single block. A view of `FunctionCFG`, which owns
    /// the algorithm.
    func basicBlocks() -> [BasicBlock] {
        FunctionCFG(self).basicBlocks(of: self)
    }

    /// Render the function as a control-flow graph: basic blocks with `loc_<addr>`
    /// labels and successor edges.
    func renderCFG() -> String {
        var lines = ["\(displayName):  // \(symbol) @ 0x\(String(startAddress, radix: 16))"]
        if let objcMethod { lines.append("  // \(objcMethod.signature)") }
        for block in FunctionCFG(self).blocks {
            lines.append("  loc_\(String(block.startAddress, radix: 16)):")
            for insn in instructions[block.range] {
                var line = "    \(String(insn.address, radix: 16)):  \(insn.text)"
                if let annotation = insn.annotation, !insn.text.contains(annotation) {
                    line += "  ; \(annotation)"
                }
                lines.append(line)
            }
            if !block.successorAddresses.isEmpty {
                let edges = block.successorAddresses.map { "loc_\(String($0, radix: 16))" }.joined(separator: ", ")
                lines.append("    → \(edges)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension Instruction {
    /// Trap termination, shared by the CFG and both pseudocode renderers.
    var isTrap: Bool {
        let mnemonic = text.prefix { $0 != " " && $0 != "\t" }
        return mnemonic == "brk" || mnemonic == "udf" || mnemonic == "trap"
    }
}
