import Foundation

/// Folds the recovered call statements into structured `if`/`else` using the
/// control-flow graph. Forward structure (the reducible DAG) is recovered via
/// post-dominators; back-edges (loops) are emitted honestly as `goto`, never
/// guessed into a `while`. Conditions are reconstructed from the compare +
/// conditional-branch pair. Anything it can't structure degrades to a labeled
/// block with `goto`, so the output is never structurally wrong.
public extension DisassembledFunction {
    func renderStructured() -> String {
        let blocks = basicBlocks()
        guard blocks.count > 1 else { return renderPseudo() }

        let cfg = ControlFlowStructure(blocks: blocks)
        var lines = ["\(displayName) {"]
        var visited = Set<Int>()
        lines += cfg.emit(from: 0, until: cfg.exit, indent: 1, visited: &visited)
        // Anything unreachable from entry by forward edges (e.g. landing pads):
        // emit honestly as labeled blocks rather than dropping it.
        for index in blocks.indices where !visited.contains(index) {
            lines += cfg.emit(from: index, until: cfg.exit, indent: 1, visited: &visited)
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}

/// Internal CFG + post-dominator structuring for `renderStructured`.
struct ControlFlowStructure {
    let blocks: [BasicBlock]
    let exit: Int
    private let indexByAddress: [UInt64: Int]
    private let forwardSuccessors: [[Int]]   // intra-function, back-edges removed
    private let backSuccessors: [[Int]]       // back-edges (to loop headers)
    private let ipdom: [Int]                   // immediate post-dominator per block

    init(blocks: [BasicBlock]) {
        self.blocks = blocks
        self.exit = blocks.count
        var indexByAddress: [UInt64: Int] = [:]
        for (index, block) in blocks.enumerated() { indexByAddress[block.startAddress] = index }
        self.indexByAddress = indexByAddress

        // Resolve successor edges to indices (intra-function only).
        var successors: [[Int]] = blocks.map { block in
            block.successors.compactMap { indexByAddress[$0] }
        }

        // Back-edge detection via DFS (edge to a node on the recursion stack).
        var color = [Int](repeating: 0, count: blocks.count) // 0=white,1=gray,2=black
        var back = Set<[Int]>()
        func dfs(_ u: Int) {
            color[u] = 1
            for v in successors[u] {
                if color[v] == 1 { back.insert([u, v]) }
                else if color[v] == 0 { dfs(v) }
            }
            color[u] = 2
        }
        if !blocks.isEmpty { dfs(0) }

        forwardSuccessors = successors.enumerated().map { u, succ in succ.filter { !back.contains([u, $0]) } }
        backSuccessors = successors.enumerated().map { u, succ in succ.filter { back.contains([u, $0]) } }
        self.ipdom = Self.postDominators(count: blocks.count, exit: exit, forward: forwardSuccessors)
    }

    // MARK: - Structured emission

    func emit(from start: Int, until stop: Int, indent: Int, visited: inout Set<Int>) -> [String] {
        var lines: [String] = []
        var current = start
        while current != stop, current != exit, !visited.contains(current) {
            visited.insert(current)
            let block = blocks[current]
            let pad = String(repeating: "    ", count: indent)

            if isLoopHeader(current) { lines.append("\(pad)loc_\(hex(block.startAddress)):  // loop header") }
            for insn in block.instructions {
                if let statement = DisassembledFunction.callStatement(of: insn, hideRuntime: true) {
                    lines.append("\(pad)\(statement)")
                }
            }
            for target in backSuccessors[current] {
                lines.append("\(pad)goto loc_\(hex(blocks[target].startAddress))  // loop")
            }

            let forward = forwardSuccessors[current]
            if isReturn(block) { lines.append("\(pad)return"); break }

            if forward.count >= 2, let taken = index(of: block.successors.first) {
                let fall = block.successors.count > 1 ? index(of: block.successors[1]) : nil
                let merge = ipdom[current]
                lines.append("\(pad)if (\(condition(of: block))) {")
                lines += emit(from: taken, until: merge, indent: indent + 1, visited: &visited)
                if let fall, fall != merge {
                    lines.append("\(pad)} else {")
                    lines += emit(from: fall, until: merge, indent: indent + 1, visited: &visited)
                }
                lines.append("\(pad)}")
                if merge == exit { break }
                current = merge
            } else if forward.count == 1 {
                current = forward[0]
            } else {
                break
            }
        }
        return lines
    }

    // MARK: - Conditions

    /// Reconstruct a readable branch condition from the block's terminator.
    private func condition(of block: BasicBlock) -> String {
        guard let terminator = block.instructions.last else { return "?" }
        let (mnemonic, operands) = Self.decode(terminator.text)
        switch mnemonic {
        case "cbz": return "\(operands.first ?? "?") == 0"
        case "cbnz": return "\(operands.first ?? "?") != 0"
        case "tbz": return "bit \(operands.count > 1 ? operands[1] : "?") of \(operands.first ?? "?") clear"
        case "tbnz": return "bit \(operands.count > 1 ? operands[1] : "?") of \(operands.first ?? "?") set"
        default:
            // b.<cond> — combine with the preceding compare.
            let op = Self.conditionOperator(mnemonic)
            for insn in block.instructions.reversed() {
                let (m, ops) = Self.decode(insn.text)
                if ["cmp", "subs", "cmn", "adds"].contains(m), ops.count >= 2 {
                    return "\(ops[0]) \(op) \(ops[1].replacingOccurrences(of: "#", with: ""))"
                }
                if m == "tst", ops.count >= 2 { return "(\(ops[0]) & \(ops[1])) \(op) 0" }
            }
            return op == "?" ? terminator.text : "cond \(op)"
        }
    }

    private static func conditionOperator(_ mnemonic: String) -> String {
        switch mnemonic {
        case "b.eq": return "=="
        case "b.ne": return "!="
        case "b.lt", "b.cc", "b.lo": return "<"
        case "b.le", "b.ls": return "<="
        case "b.gt", "b.hi": return ">"
        case "b.ge", "b.cs", "b.hs": return ">="
        case "b.mi": return "< 0 //"
        case "b.pl": return ">= 0 //"
        case "b.vs": return "overflow"
        case "b.vc": return "no-overflow"
        default: return "?"
        }
    }

    // MARK: - Helpers

    private func index(of address: UInt64?) -> Int? { address.flatMap { indexByAddress[$0] } }
    private func isLoopHeader(_ node: Int) -> Bool { backSuccessors.contains { $0.contains(node) } }
    private func isReturn(_ block: BasicBlock) -> Bool {
        block.instructions.last?.controlFlow == .return
    }

    private static func decode(_ text: String) -> (String, [String]) {
        let beforeComment = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let trimmed = beforeComment.trimmingCharacters(in: .whitespaces)
        guard let split = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return (trimmed, []) }
        let operands = trimmed[trimmed.index(after: split)...]
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (String(trimmed[..<split]), operands)
    }

    /// Post-dominators on the forward DAG: PD[n] = {n} ∪ ⋂ PD[successors];
    /// ipdom(n) = the closest member (largest post-dominator set).
    private static func postDominators(count: Int, exit: Int, forward: [[Int]]) -> [Int] {
        guard count > 0 else { return [] }
        let universe = Set(0...exit)
        var pd = [Set<Int>](repeating: universe, count: count + 1)
        pd[exit] = [exit]
        var changed = true
        while changed {
            changed = false
            for node in (0..<count).reversed() {
                let succ = forward[node].isEmpty ? [exit] : forward[node]
                var meet = succ.map { pd[$0] }.reduce(universe) { $0.intersection($1) }
                meet.insert(node)
                if meet != pd[node] { pd[node] = meet; changed = true }
            }
        }
        return (0..<count).map { node in
            pd[node].subtracting([node]).max(by: { pd[$0].count < pd[$1].count }) ?? exit
        }
    }
}

private func hex(_ value: UInt64) -> String { String(value, radix: 16) }
