import Foundation

/// A function's control-flow graph, built once from its instructions.
///
/// Blocks are index ranges into `DisassembledFunction.instructions`, not
/// copies, and carry dense ids: block `i` is the `i`th block in instruction
/// order, and block 0 (the first instruction's) is the entry. The graph reads
/// only each instruction's address, control-flow class, branch target and
/// trap mnemonic, plus the function's `switchTargets`, so it stays valid for
/// any rebuild that keeps those (one that only adds notes). A change to the
/// jump tables or to a resolved branch target needs a new graph.
///
/// `basicBlocks()` is a view of this graph, so every block list in the
/// analysis is the same one.
struct FunctionCFG: Sendable, Equatable {
    typealias BlockID = Int

    struct Block: Sendable, Equatable {
        let startAddress: UInt64
        /// The block's instructions, as indices into the function's.
        let range: Range<Int>
        /// Where control can go: the branch target and the fall-through, or a
        /// jump table's case targets without repeats, in `BasicBlock.successors`
        /// order and multiplicity (a conditional branch to the next instruction
        /// lists it twice). Out-of-function targets are included as-is.
        let successorAddresses: [UInt64]
        /// The successors that start a block of this function, in the same
        /// order and multiplicity.
        fileprivate(set) var successorIDs: [BlockID]
        /// The blocks that list this one as a successor, in block order, once
        /// per edge.
        fileprivate(set) var predecessorIDs: [BlockID]
        /// For a block ending in a recovered jump table: the target of each
        /// case, in case order, repeats kept. Nil otherwise.
        let switchCases: [UInt64]?

        /// Index of the block's last instruction, the one that ends it.
        var terminator: Int { range.upperBound - 1 }
    }

    let blocks: [Block]
    /// The number of instructions the graph partitions.
    let instructionCount: Int
    /// The block holding each instruction, indexed like the instructions.
    let blockOfInstruction: [BlockID]
    /// Block start address to block. Two blocks can share an address only
    /// when two instructions do; the first wins, as every address-keyed
    /// consumer of `basicBlocks()` resolved it.
    private let blockAtAddress: [UInt64: BlockID]

    /// The entry block: the first instruction's. Nil for an empty function.
    var entry: BlockID? { blocks.isEmpty ? nil : 0 }

    /// The block that starts at `address`, if one does.
    func block(startingAt address: UInt64) -> BlockID? { blockAtAddress[address] }

    /// Recover the blocks from Capstone control-flow info: leaders are the
    /// entry, every internal branch and jump-table target, and the instruction
    /// after any branch, return or trap. Without `controlFlow` on the
    /// instructions (a text-only listing) the function is one block.
    init(_ function: DisassembledFunction) {
        let instructions = function.instructions
        let switchTargets = function.switchTargets
        instructionCount = instructions.count
        guard !instructions.isEmpty else {
            blocks = []
            blockOfInstruction = []
            blockAtAddress = [:]
            return
        }
        let internalAddresses = Set(instructions.map(\.address))

        // 1. Leaders: entry, branch targets (internal), and the instruction
        //    following any block-terminating control flow.
        var leaders: Set<UInt64> = [instructions[0].address]
        for (index, insn) in instructions.enumerated() {
            // A trap ends its block like a return, though Capstone classes
            // BRK/UDF as sequential; function-start extents can hold
            // unreachable instructions after it, which are not its body.
            if insn.isTrap, index + 1 < instructions.count {
                leaders.insert(instructions[index + 1].address)
            }
            switch insn.controlFlow {
            case .branch, .conditionalBranch, .return:
                if index + 1 < instructions.count {
                    leaders.insert(instructions[index + 1].address)
                }
                if let target = insn.branchTarget, internalAddresses.contains(target) {
                    leaders.insert(target)
                }
                for target in switchTargets[insn.address] ?? [] where internalAddresses.contains(target) {
                    leaders.insert(target)
                }
            case .call, .sequential, .none:
                break
            }
        }

        // 2. Cut the instruction stream at the leaders.
        var blocks: [Block] = []
        var start = 0
        func flush(end: Int, fallthrough next: UInt64?) {
            guard start < end else { return }
            let last = instructions[end - 1]
            let cases = switchTargets[last.address]
            var unique: [UInt64] = []
            for target in cases ?? [] where !unique.contains(target) { unique.append(target) }
            blocks.append(Block(
                startAddress: instructions[start].address, range: start..<end,
                successorAddresses: cases == nil ? Self.successors(of: last, fallthrough: next) : unique,
                successorIDs: [], predecessorIDs: [], switchCases: cases
            ))
            start = end
        }
        for (index, insn) in instructions.enumerated() {
            if index > start, leaders.contains(insn.address) {
                flush(end: index, fallthrough: insn.address)
            }
        }
        flush(end: instructions.count, fallthrough: nil)

        // 3. Edges between blocks, from the successor addresses.
        var blockAtAddress: [UInt64: BlockID] = [:]
        var blockOfInstruction = [BlockID](repeating: 0, count: instructions.count)
        for (id, block) in blocks.enumerated() {
            if blockAtAddress[block.startAddress] == nil { blockAtAddress[block.startAddress] = id }
            for index in block.range { blockOfInstruction[index] = id }
        }
        var predecessors = [[BlockID]](repeating: [], count: blocks.count)
        for id in blocks.indices {
            blocks[id].successorIDs = blocks[id].successorAddresses.compactMap { blockAtAddress[$0] }
            for successor in blocks[id].successorIDs { predecessors[successor].append(id) }
        }
        for id in blocks.indices { blocks[id].predecessorIDs = predecessors[id] }

        self.blocks = blocks
        self.blockOfInstruction = blockOfInstruction
        self.blockAtAddress = blockAtAddress
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
            if last.isTrap { return [] }
            return next.map { [$0] } ?? []
        }
    }

    /// The blocks as `BasicBlock` values holding copies of `function`'s
    /// instructions. `function` must be the one the graph was built from, or a
    /// rebuild of it with the same instructions in the same order.
    func basicBlocks(of function: DisassembledFunction) -> [BasicBlock] {
        precondition(function.instructions.count == instructionCount,
                     "FunctionCFG used with a function it was not built from")
        return blocks.map { block in
            BasicBlock(
                startAddress: block.startAddress,
                instructions: Array(function.instructions[block.range]),
                successors: block.successorAddresses,
                switchCases: block.switchCases
            )
        }
    }
}
