import Foundation

public extension Probe {
    /// Bounded branch-path evidence for exits in an acyclic CFG. Cycles,
    /// unsupported forks and their dependent paths remain unknown. This does
    /// not execute calls, prove side effects or change the value analysis.
    static func returnPathConditions(_ analysis: FunctionAnalysis,
                                     of function: DisassembledFunction) -> [UInt64: AbstractValue] {
        let cfg = FunctionCFG(function)
        let blocks = cfg.blocks, instructions = function.instructions
        guard !blocks.isEmpty, blocks.count <= 256,
              blocks.first?.startAddress == function.startAddress,
              Set(blocks.map(\.startAddress)).count == blocks.count else { return [:] }
        let byAddress = Dictionary(uniqueKeysWithValues: blocks.map { ($0.startAddress, $0) })
        var remaining = Dictionary(uniqueKeysWithValues: blocks.map { ($0.startAddress, 0) })
        for block in blocks {
            for successor in Set(block.successorAddresses) where byAddress[successor] != nil {
                remaining[successor, default: 0] += 1
            }
        }
        var queue = remaining.keys.filter { remaining[$0] == 0 }.sorted(), cursor = 0
        var paths: [UInt64: ReturnPathTerm] = [function.startAddress: .one]
        var exits: [UInt64: AbstractValue] = [:]
        // Initialize every exit to unknown so a cyclic/dependent block cannot
        // accidentally appear absent or inherit an unfinished path calculation.
        for block in blocks {
            for insn in instructions[block.range] where insn.controlFlow == .return
                || analysis.indirectControlFlowTargets[insn.address] == .asyncResumeParent {
                exits[insn.address] = .unknown
            }
        }
        // An unresolved indirect branch can enter an otherwise disconnected
        // block. Without all potential edges, even "unreachable" is unproven.
        if blocks.contains(where: { block in
            let last = instructions[block.terminator]
            return last.controlFlow == .branch && last.branchTarget == nil
                && function.switchTargets[last.address] == nil
                && analysis.indirectControlFlowTargets[last.address] != .asyncResumeParent
        }) { return exits }
        while cursor < queue.count {
            let address = queue[cursor]; cursor += 1
            guard let block = byAddress[address] else { continue }
            let last = instructions[block.terminator]
            let prefix = paths[address] ?? .zero // disconnected DAG roots are unreachable
            for insn in instructions[block.range] where exits[insn.address] != nil { exits[insn.address] = prefix.value }
            let successors = Set(block.successorAddresses).sorted()
            for successor in successors where byAddress[successor] != nil {
                let edge: ReturnPathTerm
                if prefix.value == .immediate(0) {
                    edge = .zero
                } else if last.controlFlow == .conditionalBranch {
                    // Require both internal edges and the exact fall-through.
                    // An external target or missing edge cannot be treated as
                    // an unconditional route to the remaining block.
                    let next = last.address.addingReportingOverflow(4)
                    if !next.overflow, successors == [last.branchTarget, next.partialValue].compactMap({ $0 }).sorted(),
                       successors.count == 2, let target = last.branchTarget,
                       byAddress[target] != nil, byAddress[next.partialValue] != nil,
                       let condition = analysis.branchConditions[last.address] {
                        edge = prefix.combining(.bitAnd, ReturnPathTerm(condition).truth(taken: successor == target))
                    } else { edge = .unknown }
                } else if successors.count == 1 {
                    edge = prefix
                } else {
                    edge = .unknown // jump tables and other unsupported forks
                }
                paths[successor] = (paths[successor] ?? .zero).combining(.bitOr, edge)
                remaining[successor, default: 0] -= 1
                if remaining[successor] == 0 { queue.append(successor) }
            }
        }
        return exits
    }
}

/// Keep construction bounded before exporting an AST. DAG joins can otherwise
/// double the tree repeatedly even when the final serialization is bounded.
private struct ReturnPathTerm {
    let value: AbstractValue
    let nodes: Int
    let depth: Int
    static let zero = Self(value: .immediate(0), nodes: 1, depth: 1)
    static let one = Self(value: .immediate(1), nodes: 1, depth: 1)
    static let unknown = Self(value: .unknown, nodes: 1, depth: 1)

    private init(value: AbstractValue, nodes: Int, depth: Int) {
        self.value = value; self.nodes = nodes; self.depth = depth
    }
    init(_ value: AbstractValue) {
        var remaining = 512
        func measure(_ value: AbstractValue, depth: Int) -> Int? {
            guard remaining > 0, depth <= 24 else { return nil }
            remaining -= 1
            let children: [AbstractValue]
            switch value {
            case .binary(_, let left, let right): children = [left, right]
            case .unary(_, let operand): children = [operand]
            case .select(let condition, let yes, let no): children = [condition, yes, no]
            case .aggregate(let values): children = values
            default: children = []
            }
            var deepest = depth
            for child in children {
                guard let childDepth = measure(child, depth: depth + 1) else { return nil }
                deepest = max(deepest, childDepth)
            }
            return deepest
        }
        if let depth = measure(value, depth: 1) { self.init(value: value, nodes: 512 - remaining, depth: depth) }
        else { self = .unknown }
    }
    func truth(taken: Bool) -> Self {
        if case .immediate(let bits) = value { return (bits != 0) == taken ? .one : .zero }
        if value == .unknown { return .unknown }
        guard nodes + 2 <= 512, depth + 1 <= 24 else { return .unknown }
        return Self(value: .binary(taken ? .notEqual : .equal, value, .immediate(0)), nodes: nodes + 2, depth: depth + 1)
    }
    func combining(_ op: AbstractBinaryOperator, _ other: Self) -> Self {
        if op == .bitAnd {
            if value == .immediate(0) || other.value == .immediate(0) { return .zero }
            if value == .immediate(1) { return other }
            if other.value == .immediate(1) { return self }
        } else {
            if value == .immediate(1) || other.value == .immediate(1) { return .one }
            if value == .immediate(0) { return other }
            if other.value == .immediate(0) { return self }
        }
        if value == .unknown || other.value == .unknown { return .unknown }
        if value == other.value { return self }
        let nodes = nodes + other.nodes + 1, depth = max(depth, other.depth) + 1
        guard nodes <= 512, depth <= 24 else { return .unknown }
        return Self(value: .binary(op, value, other.value), nodes: nodes, depth: depth)
    }
}
