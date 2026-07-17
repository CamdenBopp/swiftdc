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

        let cfg = ControlFlowStructure(blocks: blocks, objectiveCArguments: objcMethod != nil)
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
    private let objectiveCArguments: Bool

    init(blocks: [BasicBlock], objectiveCArguments: Bool = false) {
        self.blocks = blocks
        self.exit = blocks.count
        self.objectiveCArguments = objectiveCArguments
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
            let succs = block.successors.compactMap { index(of: $0) }
            // Resolve the branch condition first: a boolean-returning call whose
            // result only feeds the test is inlined into the condition, so it is
            // dropped from the straight-line statements to avoid printing it twice.
            let branch = succs.count >= 2 ? condition(of: block) : nil
            var emittedReturn = false
            for insn in block.instructions {
                if branch?.consumed.contains(insn.address) == true { continue }
                if let statement = DisassembledFunction.pseudoStatement(of: insn, hideRuntime: true) {
                    lines.append("\(pad)\(statement)")
                    emittedReturn = emittedReturn || statement.hasPrefix("return ")
                }
            }
            if isReturn(block) {
                if !emittedReturn { lines.append("\(pad)return") }
                break
            }

            if succs.count >= 2 {
                let merge = ipdom[current]
                let thenLines = edge(from: current, to: succs[0], until: merge, indent: indent + 1, visited: &visited, loop: loop)
                let elseLines = succs[1] != merge
                    ? edge(from: current, to: succs[1], until: merge, indent: indent + 1, visited: &visited, loop: loop)
                    : []
                let cond = branch?.text ?? "?"
                // Collapse empty branches: drop a no-op `if`, invert when only the
                // `then` side is empty.
                if thenLines.isEmpty, elseLines.isEmpty {
                    // both rejoin immediately — nothing to emit
                } else if thenLines.isEmpty {
                    lines.append("\(pad)if (\(Self.inverted(cond))) {")
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
    ///
    /// Returns the condition text and the addresses of any calls whose result was
    /// inlined into it — a `bool`-returning `[recv isSomething]` that only feeds
    /// the branch — so the caller can drop those from the straight-line body
    /// rather than print the send twice.
    private func condition(of block: BasicBlock) -> (text: String, consumed: Set<UInt64>) {
        var consumed: Set<UInt64> = []
        guard let terminator = block.instructions.last else { return ("?", consumed) }
        let (mnemonic, operands) = Self.decode(terminator.text)
        let last = block.instructions.count - 1
        // A value reads as a boolean when it is a message send (a `[…]` idiom),
        // an already-negated boolean, or a metadata-typed BOOL field. `tbz X, #0`
        // and `cbz X` on such a value are the compiler's `if (!X)`. `before` is
        // the index the register's definition precedes — the terminator for a
        // direct test, or the compare for a `cmp`-driven branch (walking from the
        // terminator would mistake the compare itself for the definition).
        func isBoolean(_ value: String, operand: String, before: Int) -> Bool {
            value.hasPrefix("[") || value.hasPrefix("!")
                || isBooleanSource(operand, before: before, in: block)
        }
        switch mnemonic {
        case "cbz":
            let operand = operands.first ?? "?"
            let value = resolve(operand, before: last, in: block, consumed: &consumed)
            return (isBoolean(value, operand: operand, before: last) ? "!\(value)" : "\(value) == 0", consumed)
        case "cbnz":
            let operand = operands.first ?? "?"
            let value = resolve(operand, before: last, in: block, consumed: &consumed)
            return (isBoolean(value, operand: operand, before: last) ? value : "\(value) != 0", consumed)
        case "tbz":
            let operand = operands.first ?? "?"
            let bit = Self.cleanImmediate(operands.count > 1 ? operands[1] : "?")
            let value = resolve(operand, before: last, in: block, consumed: &consumed)
            // Bit 0 is the boolean bit: `tbz X, #0` branches when X is false.
            if bit == "0", isBoolean(value, operand: operand, before: last) { return ("!\(value)", consumed) }
            return ("bit \(bit) of \(value) clear", consumed)
        case "tbnz":
            let operand = operands.first ?? "?"
            let bit = Self.cleanImmediate(operands.count > 1 ? operands[1] : "?")
            let value = resolve(operand, before: last, in: block, consumed: &consumed)
            if bit == "0", isBoolean(value, operand: operand, before: last) { return (value, consumed) }
            return ("bit \(bit) of \(value) set", consumed)
        default:
            let op = Self.conditionOperator(mnemonic)
            for index in stride(from: last - 1, through: 0, by: -1) {
                let (m, ops) = Self.decode(block.instructions[index].text)
                if ["cmp", "subs", "cmn", "adds"].contains(m), ops.count >= 2 {
                    let lhs = resolve(ops[0], before: index, in: block, consumed: &consumed)
                    let rhs = resolve(ops[1], before: index, in: block, consumed: &consumed)
                    // If back-substitution collapsed distinct operands to the same
                    // text, it lost information — show the raw registers instead.
                    if lhs == rhs, ops[0] != ops[1] {
                        return ("\(ops[0]) \(op) \(Self.cleanImmediate(ops[1]))", consumed)
                    }
                    if isBoolean(lhs, operand: ops[0], before: index),
                       let simplified = Self.booleanComparison(lhs: lhs, op: op, rhs: rhs) {
                        return (simplified, consumed)
                    }
                    return ("\(lhs) \(op) \(rhs)", consumed)
                }
                if m == "tst", ops.count >= 2 {
                    return ("(\(resolve(ops[0], before: index, in: block, consumed: &consumed)) & \(Self.cleanImmediate(ops[1]))) \(op) 0", consumed)
                }
            }
            return (op == "?" ? terminator.text : "cond \(op)", consumed)
        }
    }

    /// Whether a compared register comes from a metadata-typed BOOL field load.
    /// Stop at calls for the same clobber reason as `resolve`; follow plain moves
    /// because optimized code often copies a byte load before comparing it.
    private func isBooleanSource(_ token: String, before: Int, in block: BasicBlock) -> Bool {
        guard let register = Self.canonicalRegister(token) else { return false }
        for index in stride(from: before - 1, through: 0, by: -1) {
            let instruction = block.instructions[index]
            if instruction.controlFlow == .call,
               let number = Int(register.dropFirst()), number <= 17 { return false }
            let (mnemonic, operands) = Self.decode(instruction.text)
            guard let destination = operands.first,
                  Self.canonicalRegister(destination) == register
            else { continue }
            if instruction.sourceType == "B" { return true }
            if mnemonic == "mov", operands.count >= 2 {
                return isBooleanSource(operands[1], before: index, in: block)
            }
            return false
        }
        return false
    }

    private static func booleanComparison(lhs: String, op: String, rhs: String) -> String? {
        switch (op, rhs) {
        case ("==", "1"), ("!=", "0"): return lhs
        case ("==", "0"), ("!=", "1"): return "!\(lhs)"
        default: return nil
        }
    }

    /// Render an operand, substituting a register one level back through a
    /// data-moving definition earlier in the same block. When the operand is the
    /// result of a boolean-returning message send, the send is inlined and its
    /// address recorded in `consumed`.
    private func resolve(_ token: String, before: Int, in block: BasicBlock, consumed: inout Set<UInt64>) -> String {
        if token.hasPrefix("#") { return Self.cleanImmediate(token) }
        guard let register = Self.canonicalRegister(token) else { return token }
        for index in stride(from: before - 1, through: 0, by: -1) {
            let instruction = block.instructions[index]
            // Calls clobber x0...x17. Never substitute a pre-call definition
            // for a post-call condition (e.g. x0 is the returned object, not
            // the stack pointer that was passed to objc_msgSendSuper2).
            if instruction.controlFlow == .call,
               let number = Int(register.dropFirst()), number <= 17 {
                if register == "x0" {
                    if instruction.annotation?.components(separatedBy: "  ")
                        .contains(where: { $0.hasPrefix("self = ") }) == true {
                        return "self"
                    }
                    // The branch tests the value this call returned. Inline the
                    // send so the condition reads as source (`[x isKindOfClass:…]`),
                    // and record the call so the body drops its now-dead statement.
                    if let send = Self.callValueExpression(instruction) {
                        consumed.insert(instruction.address)
                        return send
                    }
                }
                return token
            }
            let (mnemonic, ops) = Self.decode(instruction.text)
            guard let dest = ops.first, Self.canonicalRegister(dest) == register else { continue }
            if let annotation = instruction.annotation,
               let field = annotation.components(separatedBy: "  ")
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: {
                    ($0.hasPrefix("self.") || $0.hasPrefix("self->"))
                        && ![" = ", " += ", " -= "].contains(where: $0.contains)
                        && !$0.hasPrefix("&")
                }) {
                return field
            }
            switch mnemonic {
            case "and" where ops.count >= 3: return "(\(ops[1]) & \(Self.cleanImmediate(ops[2])))"
            case "orr" where ops.count >= 3: return "(\(ops[1]) | \(Self.cleanImmediate(ops[2])))"
            case "lsr", "asr": return ops.count >= 3 ? "(\(ops[1]) >> \(Self.cleanImmediate(ops[2])))" : token
            case "lsl": return ops.count >= 3 ? "(\(ops[1]) << \(Self.cleanImmediate(ops[2])))" : token
            case "ubfx", "sbfx": return ops.count >= 2 ? sourceName(ops[1]) : sourceName(token)
            case "mov" where ops.count >= 2:
                if ops[1].hasPrefix("#") { return Self.cleanImmediate(ops[1]) }
                // Follow a copy out of the ABI return register, so a boolean moved
                // aside before a clobbering call still resolves to its source send.
                if Self.canonicalRegister(ops[1]) == "x0" {
                    return resolve(ops[1], before: index, in: block, consumed: &consumed)
                }
                return sourceName(ops[1])
            default: return sourceName(token)
            }
        }
        return sourceName(token)
    }

    /// The source-level expression a value-returning call denotes — a message
    /// send (`[recv sel:…]`) or a runtime idiom (`[x isKindOfClass:y]`) — for
    /// inlining into a branch condition. Nil for a void call, so only genuine
    /// values are substituted. Unlike `callStatement`, this ignores
    /// `resultConsumed`: a result consumed by the branch is exactly the case here.
    private static func callValueExpression(_ insn: Instruction) -> String? {
        guard let callee = DisassembledFunction.calleeName(of: insn) else { return nil }
        let arguments = insn.callArguments ?? []
        if let send = DisassembledFunction.MessageSend(callee: callee, arguments: arguments) {
            return send.rendered
        }
        return DisassembledFunction.objcRuntimeIdiom(callee: callee, arguments: arguments)
    }

    /// At an Objective-C method entry x2...x7 are the first six explicit
    /// selector arguments. Use those names only when no definition inside the
    /// block supersedes the entry value.
    private func sourceName(_ token: String) -> String {
        guard objectiveCArguments,
              let register = Self.canonicalRegister(token),
              register.hasPrefix("x"),
              let number = Int(register.dropFirst()), (2...7).contains(number)
        else { return token }
        return "arg\(number - 2)"
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

    private static func inverted(_ condition: String) -> String {
        for (op, inverse) in [
            (" != ", " == "), (" == ", " != "),
            (" <= ", " > "), (" >= ", " < "),
            (" < ", " >= "), (" > ", " <= "),
        ] where condition.contains(op) {
            return condition.replacingOccurrences(of: op, with: inverse)
        }
        if condition.hasPrefix("!("), condition.hasSuffix(")") {
            return String(condition.dropFirst(2).dropLast())
        }
        if condition.hasPrefix("!") { return String(condition.dropFirst()) }
        // A bit test inverts by flipping set/clear, not by prefixing `!` — which
        // would read as the double negative `!bit 0 of w8 clear`.
        if condition.hasSuffix(" clear") { return String(condition.dropLast(6)) + " set" }
        if condition.hasSuffix(" set") { return String(condition.dropLast(4)) + " clear" }
        return "!\(condition)"
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
