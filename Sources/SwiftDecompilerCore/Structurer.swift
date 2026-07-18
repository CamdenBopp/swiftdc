import Foundation

/// Folds the recovered call statements into structured `if`/`else`/`while` using
/// the control-flow graph. Forward structure (the reducible DAG) is recovered via
/// post-dominators; reducible loops (single forward exit) are folded into
/// `while (true) { … }` with `break`/`continue`; anything it can't structure
/// degrades to a labeled block with `goto`, so the output is never structurally
/// wrong. Conditions are reconstructed from the compare + conditional-branch pair.
public extension DisassembledFunction {
    /// `maxStructuringDepth` bounds the structurer's recursion (see
    /// `ControlFlowStructure.emit`); pass `0` (the default) to use the built-in
    /// limit. Exposed so tests can inject a small value.
    func renderStructured(maxStructuringDepth: Int = 0) -> String {
        let blocks = basicBlocks()
        guard blocks.count > 1 else { return renderPseudo() }

        let depth = maxStructuringDepth > 0 ? maxStructuringDepth : ControlFlowStructure.defaultMaxDepth
        let cfg = ControlFlowStructure(blocks: blocks, objectiveCArguments: objcMethod != nil, maxDepth: depth)
        let header = "\(displayName) {"
        let objcLine = objcMethod.map { "    // \($0.signature)" }

        // The structurer recurses with the CFG's nesting depth, and each frame is
        // large; a deeply nested CFG (a giant switch → a long if-else-if cascade)
        // can exceed the ambient thread's stack. Run on a thread with a large,
        // known stack so the depth guard (a backstop) is what bounds recursion,
        // not the caller's stack size.
        let result = ResultBox()
        ControlFlowStructure.onLargeStack {
            result.lines = cfg.renderLines(header: header, objcLine: objcLine)
        }
        return result.lines.joined(separator: "\n")
    }
}

/// Carries the rendered lines back from the large-stack worker thread. Safe
/// because the caller reads `lines` only after the semaphore join (a
/// happens-before), so there is no concurrent access.
final class ResultBox: @unchecked Sendable { var lines: [String] = [] }

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
    let maxDepth: Int                          // recursion-depth guard (see emit)

    init(blocks: [BasicBlock], objectiveCArguments: Bool = false, maxDepth: Int = ControlFlowStructure.defaultMaxDepth) {
        self.blocks = blocks
        self.exit = blocks.count
        self.objectiveCArguments = objectiveCArguments
        self.maxDepth = maxDepth
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

    /// Past `maxDepth` `emit`/`edge` recursion frames, `emit` degrades to a `goto`
    /// rather than run the recursion arbitrarily deep on a pathologically deep CFG
    /// (e.g. a giant switch lowered to a long if-else-if cascade). The deferred
    /// block is emitted later as a standalone labeled block — the Structurer's
    /// "never crash, degrade to goto" contract. `renderStructured` runs the whole
    /// recursion on a large dedicated stack, so this bounds *readability* (very
    /// deep nesting degrades to gotos), and is a safety backstop only for the
    /// truly absurd. Injectable so tests exercise it on a small-stack test thread.
    static let defaultMaxDepth = 400

    /// The stack given to the structuring worker thread. `emit`/`edge` frames are
    /// large, and a deeply nested CFG recurses far deeper than a default worker
    /// stack allows; 256 MB is virtual (lazily committed) and ample.
    private static let workerStackSize = 256 * 1024 * 1024

    /// Run `work` synchronously on a thread with a large stack (see above), so the
    /// structurer's recursion depth is bounded by `maxDepth`, not the ambient
    /// thread's stack. Blocks the caller until it finishes — fine for this batch
    /// (non-server) rendering.
    static func onLargeStack(_ work: @escaping @Sendable () -> Void) {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            work()
            done.signal()
        }
        thread.stackSize = workerStackSize
        thread.start()
        done.wait()
    }

    /// Build the structured body (the shared work run on the large-stack thread).
    func renderLines(header: String, objcLine: String?) -> [String] {
        var lines = [header]
        if let objcLine { lines.append(objcLine) }
        var visited = Set<Int>()
        // Blocks a depth-guarded `goto` points to: they must be emitted with a
        // `loc_<addr>:` label wherever they land (see `emit`).
        var gotoTargets = Set<Int>()
        lines += emit(from: 0, until: exit, indent: 1, visited: &visited, gotoTargets: &gotoTargets, loop: nil, depth: 0)
        // Anything unreachable from entry by forward edges (e.g. landing pads),
        // and any block deferred by the recursion-depth guard: emit honestly as
        // labeled blocks. Trivial tails are duplicated into branches, not emitted
        // standalone. Loop so a block the guard defers *while* draining the
        // worklist still gets emitted (its index may already be behind us).
        var progressed = true
        while progressed {
            progressed = false
            for index in blocks.indices where !visited.contains(index) && !isTrivialTail(index) {
                lines += emit(from: index, until: exit, indent: 1, visited: &visited, gotoTargets: &gotoTargets, loop: nil, depth: 0)
                progressed = true
            }
        }
        lines.append("}")
        return lines
    }

    func emit(from start: Int, until stop: Int, indent: Int, visited: inout Set<Int>, gotoTargets: inout Set<Int>, loop: LoopContext?, depth: Int) -> [String] {
        if depth > maxDepth,
           start != stop, start != exit, !visited.contains(start), !isTrivialTail(start) {
            gotoTargets.insert(start)
            return ["\(String(repeating: "    ", count: indent))goto loc_\(hex(blocks[start].startAddress))"]
        }
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
                if gotoTargets.contains(current) { lines.append("\(pad)loc_\(hex(blocks[current].startAddress)):") }
                let context = LoopContext(header: current, exitNode: info.exit ?? exit)
                lines.append("\(pad)while (true) {")
                lines += emit(from: current, until: stop, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: context, depth: depth + 1)
                lines.append("\(pad)}")
                current = info.exit ?? exit
                continue
            }

            visited.insert(current)
            let block = blocks[current]
            // Label a block that is a loop header, or a `goto` target the depth
            // guard deferred — so every emitted `goto loc_<addr>` resolves.
            if loops[current] == nil, isLoopHeader(current) {
                lines.append("\(pad)loc_\(hex(block.startAddress)):  // loop header")
            } else if gotoTargets.contains(current) {
                lines.append("\(pad)loc_\(hex(block.startAddress)):")
            }
            let succs = block.successors.compactMap { index(of: $0) }
            // Swift's checked-arithmetic overflow guard (`adds; b.vs trap`) is an
            // implicit language safety check, not program logic. Fold it away and
            // fall through to the non-trap path, so `+=`/loop bodies aren't sprayed
            // with `if (overflow) trap()`.
            let overflowContinuation = succs.count == 2 ? overflowGuardContinuation(current) : nil
            // Resolve the branch condition first: a boolean-returning call whose
            // result only feeds the test is inlined into the condition, so it is
            // dropped from the straight-line statements to avoid printing it twice.
            let branch = (succs.count >= 2 && overflowContinuation == nil) ? condition(of: block) : nil
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

            // Folded overflow guard: continue straight to the non-trap successor.
            if let overflowContinuation {
                current = overflowContinuation
                continue
            }

            if succs.count >= 2 {
                let merge = ipdom[current]
                let thenLines = edge(from: current, to: succs[0], until: merge, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: loop, depth: depth + 1)
                let elseLines = succs[1] != merge
                    ? edge(from: current, to: succs[1], until: merge, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: loop, depth: depth + 1)
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
    private func edge(from u: Int, to v: Int, until merge: Int, indent: Int, visited: inout Set<Int>, gotoTargets: inout Set<Int>, loop: LoopContext?, depth: Int) -> [String] {
        let pad = String(repeating: "    ", count: indent)
        if backSuccessors[u].contains(v) {
            if let loop, v == loop.header { return ["\(pad)continue"] }
            return ["\(pad)goto loc_\(hex(blocks[v].startAddress))  // loop"]
        }
        if let loop, v == loop.exitNode { return ["\(pad)break"] }
        if v == merge || v == exit { return [] }
        return emit(from: v, until: merge, indent: indent, visited: &visited, gotoTargets: &gotoTargets, loop: loop, depth: depth + 1)
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
        // Prefer the value tracer's reconstructed comparison when the enrichment
        // baked one (`cond:` note) — it names the operands (`arg0 >= arg1`) where
        // the text back-substitution below can only reach raw registers. Only
        // clean scalar comparisons are baked; message-send/boolean tests are left
        // to the text path, which inlines them more readably.
        if let baked = Self.bakedCondition(terminator.annotation) {
            return (baked, consumed)
        }
        let (mnemonic, operands) = Self.decode(terminator.text)
        let last = block.instructions.count - 1
        // A value reads as a boolean when it is a message send (a `[…]` idiom),
        // a value-returning call (`foo(…)` — a single-bit or 0/1 test on a call
        // result is the compiler testing a Bool/nil return), an already-negated
        // boolean, or a metadata-typed BOOL field. `tbz X, #0` and `cbz X` on such
        // a value are the compiler's `if (!X)`. `before` is the index the
        // register's definition precedes — the terminator for a direct test, or
        // the compare for a `cmp`-driven branch (walking from the terminator would
        // mistake the compare itself for the definition).
        func isBoolean(_ value: String, operand: String, before: Int) -> Bool {
            value.hasPrefix("[") || value.hasPrefix("!") || Self.looksLikeCall(value)
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
                    // `cmp`/`cmn` compare their two operands; `subs`/`adds` write a
                    // destination first, so their compared operands are 1 and 2 —
                    // reading operand 0 would test the result register, not the
                    // comparison (the source of bogus `x8 >= …` conditions).
                    let hasDestination = (m == "subs" || m == "adds") && ops.count >= 3
                    let lhsIndex = hasDestination ? 1 : 0
                    let rhsIndex = hasDestination ? 2 : 1
                    let lhs = resolve(ops[lhsIndex], before: index, in: block, consumed: &consumed)
                    let rhs = resolve(ops[rhsIndex], before: index, in: block, consumed: &consumed)
                    // If back-substitution collapsed distinct operands to the same
                    // text, it lost information — show the raw registers instead.
                    if lhs == rhs, ops[lhsIndex] != ops[rhsIndex] {
                        return ("\(ops[lhsIndex]) \(op) \(Self.cleanImmediate(ops[rhsIndex]))", consumed)
                    }
                    if isBoolean(lhs, operand: ops[lhsIndex], before: index),
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
                    // ARC identity wrappers (objc_retain / …AutoreleasedReturnValue)
                    // return x0 unchanged, so the real producer is one call back —
                    // keep walking rather than giving up on the retained result.
                    if let callee = DisassembledFunction.calleeName(of: instruction),
                       DisassembledFunction.isRuntimeNoise(callee) {
                        continue
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

    /// The source-level expression a value-returning call denotes, for inlining
    /// into a branch condition: a message send (`[recv sel:…]`), a runtime idiom
    /// (`[x isKindOfClass:y]`), or any other named call (a Swift function, a
    /// runtime predicate like `swift_task_isCurrentExecutor`, a C function)
    /// rendered as `callee(args)`. Unlike `callStatement`, this ignores
    /// `resultConsumed` — a result consumed by the branch is exactly the case
    /// here. ARC/exclusivity bookkeeping returns nil so `resolve` sees through it
    /// to the real producer rather than inlining `objc_retain(x)`.
    private static func callValueExpression(_ insn: Instruction) -> String? {
        guard let callee = DisassembledFunction.calleeName(of: insn) else { return nil }
        let rawArguments = insn.callArguments ?? []
        if let cast = DisassembledFunction.swiftCastIdiom(callee: callee, arguments: rawArguments) {
            return cast
        }
        if DisassembledFunction.isRuntimeNoise(callee)
            || DisassembledFunction.isGenericPlumbingCallee(callee) { return nil }
        let arguments = DisassembledFunction.strippingGenericPlumbing(rawArguments)
        if let send = DisassembledFunction.MessageSend(callee: callee, arguments: arguments) {
            return send.rendered
        }
        if let idiom = DisassembledFunction.objcRuntimeIdiom(callee: callee, arguments: arguments) {
            return idiom
        }
        // A Swift receiver arrives in x20, not the argument registers, so show it
        // explicitly the way the statement form does rather than dropping it.
        let parts = insn.callSelf.map { ["self: \($0)"] + arguments } ?? arguments
        return "\(DisassembledFunction.strippedCallee(callee))(\(parts.joined(separator: ", ")))"
    }

    /// Whether a rendered value is an identifier-led call expression `name(args)`
    /// (as opposed to an arithmetic group like `(a + b)`, which starts with `(`).
    /// A single-bit or 0/1 test on a call result is the compiler testing a Bool
    /// or nil return, so such a value renders as `!call` / `call`. Message sends
    /// (`[recv sel]`) are recognised separately by their `[` prefix.
    private static func looksLikeCall(_ value: String) -> Bool {
        guard value.hasSuffix(")"), value.contains("("),
              let first = value.first, first.isLetter || first == "_" || first == "$"
        else { return false }
        return true
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

    /// The comparison the enrichment baked for this branch (`cond: (a >= b)`),
    /// with its outer parentheses removed so it matches the text path's spacing
    /// (which `inverted` and the `if (…)` wrapper both assume). Nil when absent.
    private static func bakedCondition(_ annotation: String?) -> String? {
        guard let annotation else { return nil }
        for note in annotation.components(separatedBy: "  ") {
            let trimmed = note.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("cond: ") else { continue }
            return unwrapOuterParentheses(String(trimmed.dropFirst("cond: ".count)))
        }
        return nil
    }

    /// Strip a single balanced outer parenthesis pair, but only when the leading
    /// `(` matches the trailing `)` — so `(a >= b)` unwraps while `(a) + (b)` does
    /// not.
    private static func unwrapOuterParentheses(_ text: String) -> String {
        guard text.hasPrefix("("), text.hasSuffix(")") else { return text }
        var depth = 0
        for (offset, character) in text.enumerated() {
            if character == "(" { depth += 1 }
            else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return offset == text.count - 1 ? String(text.dropFirst().dropLast()) : text
                }
            }
        }
        return text
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

    /// A pure trap sink: a block that only traps, with no recovered statements —
    /// the target of a Swift safety-check guard. A trap never continues, so this
    /// deliberately ignores successor edges (which are spurious on a trap block).
    private func isTrivialTrapTail(_ node: Int) -> Bool {
        guard let last = blocks[node].instructions.last, Self.isTrap(last) else { return false }
        return !blocks[node].instructions.contains {
            DisassembledFunction.pseudoStatement(of: $0, hideRuntime: true) != nil
        }
    }

    /// Recognize Swift's checked-arithmetic **overflow guard**: a conditional
    /// branch to a pure trap sink, taken on an arithmetic overflow/carry flag
    /// (what `a &+ b`-style checked `+`/`-`/`+=` lower to — `adds; cset vs; tbnz
    /// trap`). Returns the non-trap continuation to fall through to (folding the
    /// guard away), or nil when the block is not such a guard.
    ///
    /// Distinguished from a genuine bounds/precondition check: those test a `cmp`
    /// (not a live-destination `adds`/`subs`) and never test the V flag alone, so
    /// this never eats a real `precondition`/bounds trap.
    private func overflowGuardContinuation(_ blockIndex: Int) -> Int? {
        let block = blocks[blockIndex]
        let succs = block.successors.compactMap { index(of: $0) }
        guard succs.count == 2, let trapPos = succs.firstIndex(where: { isTrivialTrapTail($0) })
        else { return nil }
        guard let cc = testedFlagCondition(of: block) else { return nil }
        // V flag (`vs`/`vc`) is unambiguously arithmetic overflow. A carry code
        // (`cs`/`hs`/`cc`/`lo`) is also how an unsigned bounds check branches, so
        // for those require an arithmetic flag-setter (a live-destination
        // `adds`/`subs`, never a `cmp`).
        if cc == "vs" || cc == "vc" {
            // arithmetic overflow — fold
        } else if ["cs", "hs", "cc", "lo"].contains(cc), hasArithmeticFlagSetter(block) {
            // unsigned add/sub carry-overflow — fold
        } else {
            return nil
        }
        return succs[1 - trapPos]
    }

    /// The condition code a block's conditional terminator tests, following a
    /// `cset`-materialized flag for a `tbnz`/`cbnz` bit-0 test. Returns the raw
    /// code (`vs`, `hs`, …), or nil when the terminator is not a flag-conditional
    /// branch.
    private func testedFlagCondition(of block: BasicBlock) -> String? {
        guard let terminator = block.instructions.last else { return nil }
        let (mnemonic, operands) = Self.decode(terminator.text)
        if mnemonic.hasPrefix("b."), mnemonic.count > 2 { return String(mnemonic.dropFirst(2)) }
        guard mnemonic == "tbnz" || mnemonic == "cbnz",
              let register = operands.first.flatMap(Self.canonicalRegister)
        else { return nil }
        // `tbnz` carries a bit index; only bit 0 is the boolean/flag bit a `cset`
        // writes.
        if mnemonic == "tbnz", operands.count >= 2, Self.cleanImmediate(operands[1]) != "0" { return nil }
        for index in stride(from: block.instructions.count - 2, through: 0, by: -1) {
            let (m, ops) = Self.decode(block.instructions[index].text)
            guard let destination = ops.first, Self.canonicalRegister(destination) == register
            else { continue }
            return m == "cset" && ops.count >= 2 ? ops[1] : nil
        }
        return nil
    }

    /// Whether the block sets flags via arithmetic with a live destination
    /// (`adds`/`subs`/`adcs`/`sbcs`, destination not the zero register) — the
    /// checked `+`/`-`, as opposed to a `cmp`/`subs xzr` comparison.
    private func hasArithmeticFlagSetter(_ block: BasicBlock) -> Bool {
        block.instructions.contains { insn in
            let (m, ops) = Self.decode(insn.text)
            guard ["adds", "subs", "adcs", "sbcs"].contains(m), let destination = ops.first
            else { return false }
            return Self.canonicalRegister(destination) != nil && destination != "xzr" && destination != "wzr"
        }
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
