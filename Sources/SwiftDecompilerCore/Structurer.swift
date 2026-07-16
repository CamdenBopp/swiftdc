import Foundation

/// Folds the recovered call statements into structured `if`/`else`/`while` using
/// the control-flow graph. Forward structure (the reducible DAG) is recovered via
/// post-dominators; reducible loops (single forward exit) are folded into
/// `while (true) { … }` with `break`/`continue`; anything it can't structure
/// degrades to a labeled block with `goto`, so the output is never structurally
/// wrong. Conditions are reconstructed from the compare + conditional-branch pair.
public extension DisassembledFunction {
    func renderStructured() -> String {
        let blocks = basicBlocks()
        guard blocks.count > 1 else { return renderPseudo() }

        let cfg = ControlFlowStructure(blocks: blocks)
        var lines = ["\(displayName) {"]
        if let objcMethod { lines.append("    // \(objcMethod.signature)") }
        var visited = Set<Int>()
        lines += cfg.emit(from: 0, until: cfg.exit, indent: 1, visited: &visited, loop: nil)
        // Anything unreachable from entry by forward edges (e.g. landing pads):
        // emit honestly as labeled blocks. Trivial tails are duplicated into
        // branches, not emitted standalone.
        for index in blocks.indices where !visited.contains(index) && !cfg.isTrivialTail(index) {
            lines += cfg.emit(from: index, until: cfg.exit, indent: 1, visited: &visited, loop: nil)
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}

/// Internal CFG + post-dominator structuring for `renderStructured`.
struct ControlFlowStructure {
    struct LoopInfo { let body: Set<Int>; let exit: Int? }
    struct LoopContext { let header: Int; let exitNode: Int }

    let blocks: [BasicBlock]
    let exit: Int
    private let indexByAddress: [UInt64: Int]
    private let forwardSuccessors: [[Int]]   // intra-function, back-edges removed
    private let backSuccessors: [[Int]]       // back-edges (to loop headers)
    private let ipdom: [Int]                   // immediate post-dominator per block
    private let loops: [Int: LoopInfo]         // foldable natural loops, by header

    init(blocks: [BasicBlock]) {
        self.blocks = blocks
        self.exit = blocks.count
        var indexByAddress: [UInt64: Int] = [:]
        for (index, block) in blocks.enumerated() { indexByAddress[block.startAddress] = index }
        self.indexByAddress = indexByAddress

        let successors: [[Int]] = blocks.map { $0.successors.compactMap { indexByAddress[$0] } }

        // Back-edge detection via DFS (edge to a node on the recursion stack).
        var color = [Int](repeating: 0, count: blocks.count) // 0=white,1=gray,2=black
        var back = Set<[Int]>()
        func dfs(_ root: Int) {
            var stack = [(node: root, next: 0)]
            color[root] = 1
            while let top = stack.last {
                let u = top.node
                if top.next < successors[u].count {
                    stack[stack.count - 1].next += 1
                    let v = successors[u][top.next]
                    if color[v] == 1 { back.insert([u, v]) }
                    else if color[v] == 0 { color[v] = 1; stack.append((v, 0)) }
                } else {
                    color[u] = 2
                    stack.removeLast()
                }
            }
        }
        if !blocks.isEmpty { dfs(0) }

        let forward = successors.enumerated().map { u, succ in succ.filter { !back.contains([u, $0]) } }
        let backward = successors.enumerated().map { u, succ in succ.filter { back.contains([u, $0]) } }
        self.forwardSuccessors = forward
        self.backSuccessors = backward
        self.ipdom = Self.postDominators(count: blocks.count, exit: exit, forward: forward)

        // Natural loops: for each back-edge u→h, body = {h} ∪ predecessors of u
        // up to h. Fold only single-forward-exit loops (provably correct).
        var fullPredecessors = [[Int]](repeating: [], count: blocks.count)
        for (u, succ) in successors.enumerated() { for v in succ { fullPredecessors[v].append(u) } }
        var bodies: [Int: Set<Int>] = [:]
        for edge in back {
            let (u, h) = (edge[0], edge[1])
            var body: Set<Int> = [h]
            var work: [Int] = []
            if u != h { body.insert(u); work.append(u) }
            while let n = work.popLast() {
                for p in fullPredecessors[n] where !body.contains(p) { body.insert(p); work.append(p) }
            }
            bodies[h, default: [h]].formUnion(body)
        }
        // A sink that ends in return/trap is abnormal/structured termination, not
        // a loop's structured exit — exclude it so a loop whose body can trap
        // still folds (the trap renders inline as `trap()`).
        func isSinkTail(_ s: Int) -> Bool {
            guard forward[s].isEmpty, backward[s].isEmpty, let last = blocks[s].instructions.last
            else { return false }
            return last.controlFlow == .return || Self.isTrap(last)
        }
        var loops: [Int: LoopInfo] = [:]
        for (header, body) in bodies {
            var exits = Set<Int>()
            for n in body {
                for s in forward[n] where !body.contains(s) && !isSinkTail(s) { exits.insert(s) }
            }
            if exits.count <= 1 { loops[header] = LoopInfo(body: body, exit: exits.first) }
        }
        self.loops = loops
    }

    // MARK: - Structured emission

    func emit(from start: Int, until stop: Int, indent: Int, visited: inout Set<Int>, loop: LoopContext?) -> [String] {
        var lines: [String] = []
        var current = start
        while current != stop, current != exit {
            let pad = String(repeating: "    ", count: indent)

            if let loop, current == loop.exitNode { lines.append("\(pad)break"); break }

            if isTrivialTail(current) {
                lines.append("\(pad)\(tailStatement(blocks[current]))")
                break
            }
            if visited.contains(current) {
                if let loop, current == loop.header { lines.append("\(pad)continue") }
                else { lines.append("\(pad)// continues at loc_\(hex(blocks[current].startAddress))") }
                break
            }

            // Enter a foldable loop: wrap its region in `while (true)`.
            if let info = loops[current], loop?.header != current {
                let context = LoopContext(header: current, exitNode: info.exit ?? exit)
                lines.append("\(pad)while (true) {")
                lines += emit(from: current, until: stop, indent: indent + 1, visited: &visited, loop: context)
                lines.append("\(pad)}")
                current = info.exit ?? exit
                continue
            }

            visited.insert(current)
            let block = blocks[current]
            if loops[current] == nil, isLoopHeader(current) {
                lines.append("\(pad)loc_\(hex(block.startAddress)):  // loop header")
            }
            for insn in block.instructions {
                if let statement = DisassembledFunction.pseudoStatement(of: insn, hideRuntime: true) {
                    lines.append("\(pad)\(statement)")
                }
            }
            if isReturn(block) { lines.append("\(pad)return"); break }

            let succs = block.successors.compactMap { index(of: $0) }
            if succs.count >= 2 {
                let merge = ipdom[current]
                let thenLines = edge(from: current, to: succs[0], until: merge, indent: indent + 1, visited: &visited, loop: loop)
                let elseLines = succs[1] != merge
                    ? edge(from: current, to: succs[1], until: merge, indent: indent + 1, visited: &visited, loop: loop)
                    : []
                let cond = condition(of: block)
                // Collapse empty branches: drop a no-op `if`, invert when only the
                // `then` side is empty.
                if thenLines.isEmpty, elseLines.isEmpty {
                    // both rejoin immediately — nothing to emit
                } else if thenLines.isEmpty {
                    lines.append("\(pad)if (!(\(cond))) {")
                    lines += elseLines
                    lines.append("\(pad)}")
                } else {
                    lines.append("\(pad)if (\(cond)) {")
                    lines += thenLines
                    if !elseLines.isEmpty {
                        lines.append("\(pad)} else {")
                        lines += elseLines
                    }
                    lines.append("\(pad)}")
                }
                if merge == exit { break }
                current = merge
            } else if succs.count == 1 {
                let only = succs[0]
                if backSuccessors[current].contains(only) {
                    if let loop, only == loop.header { lines.append("\(pad)continue") }
                    else { lines.append("\(pad)goto loc_\(hex(blocks[only].startAddress))  // loop") }
                    break
                }
                if let loop, only == loop.exitNode { lines.append("\(pad)break"); break }
                current = only
            } else {
                break
            }
        }
        return lines
    }

    /// Emit one branch edge `u → v`: a back-edge becomes `continue`/`goto`, the
    /// loop exit becomes `break`, the merge point is empty, else recurse.
    private func edge(from u: Int, to v: Int, until merge: Int, indent: Int, visited: inout Set<Int>, loop: LoopContext?) -> [String] {
        let pad = String(repeating: "    ", count: indent)
        if backSuccessors[u].contains(v) {
            if let loop, v == loop.header { return ["\(pad)continue"] }
            return ["\(pad)goto loc_\(hex(blocks[v].startAddress))  // loop"]
        }
        if let loop, v == loop.exitNode { return ["\(pad)break"] }
        if v == merge || v == exit { return [] }
        return emit(from: v, until: merge, indent: indent, visited: &visited, loop: loop)
    }

    // MARK: - Conditions

    /// Reconstruct a readable branch condition from the block's terminator,
    /// back-substituting compared registers through the block (`w8` →
    /// `(w1 & 0xff)`) so the condition reflects what's actually tested.
    private func condition(of block: BasicBlock) -> String {
        guard let terminator = block.instructions.last else { return "?" }
        let (mnemonic, operands) = Self.decode(terminator.text)
        let last = block.instructions.count - 1
        switch mnemonic {
        case "cbz": return "\(resolve(operands.first ?? "?", before: last, in: block)) == 0"
        case "cbnz": return "\(resolve(operands.first ?? "?", before: last, in: block)) != 0"
        case "tbz": return "bit \(Self.cleanImmediate(operands.count > 1 ? operands[1] : "?")) of \(resolve(operands.first ?? "?", before: last, in: block)) clear"
        case "tbnz": return "bit \(Self.cleanImmediate(operands.count > 1 ? operands[1] : "?")) of \(resolve(operands.first ?? "?", before: last, in: block)) set"
        default:
            let op = Self.conditionOperator(mnemonic)
            for index in stride(from: last - 1, through: 0, by: -1) {
                let (m, ops) = Self.decode(block.instructions[index].text)
                if ["cmp", "subs", "cmn", "adds"].contains(m), ops.count >= 2 {
                    let lhs = resolve(ops[0], before: index, in: block)
                    let rhs = resolve(ops[1], before: index, in: block)
                    // If back-substitution collapsed distinct operands to the same
                    // text, it lost information — show the raw registers instead.
                    if lhs == rhs, ops[0] != ops[1] {
                        return "\(ops[0]) \(op) \(Self.cleanImmediate(ops[1]))"
                    }
                    return "\(lhs) \(op) \(rhs)"
                }
                if m == "tst", ops.count >= 2 {
                    return "(\(resolve(ops[0], before: index, in: block)) & \(Self.cleanImmediate(ops[1]))) \(op) 0"
                }
            }
            return op == "?" ? terminator.text : "cond \(op)"
        }
    }

    /// Render an operand, substituting a register one level back through a
    /// data-moving definition earlier in the same block.
    private func resolve(_ token: String, before: Int, in block: BasicBlock) -> String {
        if token.hasPrefix("#") { return Self.cleanImmediate(token) }
        guard let register = Self.canonicalRegister(token) else { return token }
        for index in stride(from: before - 1, through: 0, by: -1) {
            let (mnemonic, ops) = Self.decode(block.instructions[index].text)
            guard let dest = ops.first, Self.canonicalRegister(dest) == register else { continue }
            switch mnemonic {
            case "and" where ops.count >= 3: return "(\(ops[1]) & \(Self.cleanImmediate(ops[2])))"
            case "orr" where ops.count >= 3: return "(\(ops[1]) | \(Self.cleanImmediate(ops[2])))"
            case "lsr", "asr": return ops.count >= 3 ? "(\(ops[1]) >> \(Self.cleanImmediate(ops[2])))" : token
            case "lsl": return ops.count >= 3 ? "(\(ops[1]) << \(Self.cleanImmediate(ops[2])))" : token
            case "ubfx", "sbfx": return ops.count >= 2 ? ops[1] : token
            case "mov" where ops.count >= 2: return ops[1].hasPrefix("#") ? Self.cleanImmediate(ops[1]) : ops[1]
            default: return token
            }
        }
        return token
    }

    /// `#0x1` → `1`, `#0xff` → `0xff` (keep masks hex), `#5` → `5`.
    private static func cleanImmediate(_ token: String) -> String {
        var s = token.hasPrefix("#") ? String(token.dropFirst()) : token
        if s.hasPrefix("0x"), let value = UInt64(s.dropFirst(2), radix: 16), value < 10 {
            s = String(value)
        }
        return s
    }

    private static func canonicalRegister(_ token: String) -> String? {
        let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "[]!"))
        guard let first = t.first, first == "x" || first == "w",
              t.dropFirst().allSatisfy(\.isNumber), t.count > 1 else { return nil }
        return "x" + t.dropFirst()
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
    private func isReturn(_ block: BasicBlock) -> Bool { block.instructions.last?.controlFlow == .return }

    /// A sink block with no recovered statements that ends in `return` or a trap — safe to
    /// duplicate into multiple branches (no side effects, no recursion).
    func isTrivialTail(_ node: Int) -> Bool {
        guard forwardSuccessors[node].isEmpty, backSuccessors[node].isEmpty,
              let last = blocks[node].instructions.last
        else { return false }
        let hasStatements = blocks[node].instructions.contains {
            DisassembledFunction.pseudoStatement(of: $0, hideRuntime: true) != nil
        }
        guard !hasStatements else { return false }
        return last.controlFlow == .return || Self.isTrap(last)
    }

    private static func isTrap(_ insn: Instruction) -> Bool {
        ["brk", "udf", "trap"].contains(decode(insn.text).0)
    }

    private func tailStatement(_ block: BasicBlock) -> String {
        if let last = block.instructions.last, Self.isTrap(last) { return "trap()" }
        return "return"
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
