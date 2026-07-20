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
        let cfg = ControlFlowStructure(
            blocks: blocks, objectiveCArguments: objcMethod != nil, maxDepth: depth,
            isThrowing: displayName.contains(" throws"),
            returnsValue: Self.signatureReturnsValue(
                displayName: displayName, objcSignature: objcMethod?.signature
            )
        )
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

    /// Whether a signature **proves** the function yields a value.
    ///
    /// Used only to choose between `return` and `return ?`, so it is deliberately
    /// one-sided: it must never claim a value for a function that has none, and
    /// when the signature is unrecognisable (`sub_<addr>`, a thunk, a witness
    /// accessor) it returns false. Under-claiming prints a bare `return`, which
    /// is merely uninformative; over-claiming would assert a value exists that
    /// does not — the fabrication this project refuses to make.
    static func signatureReturnsValue(displayName: String, objcSignature: String?) -> Bool {
        // Objective-C is authoritative when present: the metadata carries a real
        // return type, e.g. `- (long long)incrementBy:(long long)arg0;`.
        if let objcSignature,
           let open = objcSignature.firstIndex(of: "("),
           let close = objcSignature[open...].firstIndex(of: ")") {
            let type = objcSignature[objcSignature.index(after: open)..<close]
                .trimmingCharacters(in: .whitespaces)
            return type != "void" && type != "IBAction"
        }

        // Swift function type: take the LAST `->`, since a parameter can itself be
        // a function type (`(A) -> B) -> C`).
        if let arrow = displayName.range(of: "->", options: .backwards) {
            let result = displayName[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            return !result.isEmpty && result != "()" && result != "Void" && result != "Swift.Void"
        }

        // Accessor form, which uses a colon rather than an arrow:
        // `Reconstruction.Priority.rawValue.getter : Swift.Int`. Only `.getter`
        // qualifies — a `.setter` yields nothing, and an ObjC selector's colons
        // must not be mistaken for this form.
        if let range = displayName.range(of: ".getter : ") {
            return !displayName[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
        }

        return false
    }
}

/// Carries the rendered lines back from the large-stack worker thread. Safe
/// because the caller reads `lines` only after the semaphore join (a
/// happens-before), so there is no concurrent access.
final class ResultBox: @unchecked Sendable { var lines: [String] = [] }

/// Internal CFG + post-dominator structuring for `renderStructured`.
struct ControlFlowStructure {
    struct LoopInfo { let body: Set<Int>; let exit: Int?; let exits: Set<Int> }
    /// `exitNode` is the single structured exit, or nil for a MULTI-exit loop —
    /// which has no one way out to render as `break`, so every exit leaves through
    /// an explicit `goto` and `body` bounds what may be emitted inside the loop.
    /// `exitNode` is the exit that renders as `break`; `boundsBody` marks a
    /// MULTI-exit loop, whose emission must stay inside `body` (every other exit
    /// leaves by an explicit `goto`). The two are independent: granting a
    /// multi-exit loop a `break` must NOT switch its body-bounding off.
    struct LoopContext {
        let header: Int
        let exitNode: Int?
        let body: Set<Int>
        let boundsBody: Bool
    }

    /// Whether the function's signature PROVES it returns a value. Drives the
    /// difference between `return` (void, or unknown) and `return ?` (a value we
    /// could not recover). Default false: unknown declines.
    let returnsValue: Bool

    let blocks: [BasicBlock]
    let exit: Int
    private let indexByAddress: [UInt64: Int]
    private let forwardSuccessors: [[Int]]   // intra-function, back-edges removed
    private let backSuccessors: [[Int]]       // back-edges (to loop headers)
    private let ipdom: [Int]                   // immediate post-dominator per block
    private let loops: [Int: LoopInfo]         // foldable natural loops, by header
    private let objectiveCArguments: Bool
    let maxDepth: Int                          // recursion-depth guard (see emit)
    private let usesSwiftError: Bool           // x21 is the error register here

    init(blocks: [BasicBlock], objectiveCArguments: Bool = false, maxDepth: Int = ControlFlowStructure.defaultMaxDepth, isThrowing: Bool = false, returnsValue: Bool = false) {
        self.returnsValue = returnsValue
        self.blocks = blocks
        self.exit = blocks.count
        self.objectiveCArguments = objectiveCArguments
        self.maxDepth = maxDepth
        // The Swift error register (x21) is meaningful here when the function
        // threads swifterror: it is declared `throws`, or it clears x21 (`mov x21,
        // #0`) before a call to catch a thrown error. Only then is `x21 == 0` an
        // error check rather than an incidental use of a callee-saved register.
        self.usesSwiftError = isThrowing || blocks.contains { block in
            block.instructions.contains { insn in
                let (m, ops) = Self.decode(insn.text)
                return m == "mov" && ops.count >= 2
                    && Self.canonicalRegister(ops[0]) == "x21"
                    && (Self.cleanImmediate(ops[1]) == "0" || ops[1] == "xzr")
            }
        }
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
        let postDominators = Self.postDominators(count: blocks.count, exit: exit, forward: forward)
        self.ipdom = postDominators

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
            // Every natural loop folds. One structured exit keeps the existing
            // rotation/`break` path unchanged; a MULTI-exit loop still becomes an
            // explicit `while (true)` whose body is bounded to exactly `body`, each
            // exit leaving by an explicit `goto`. Choosing no primary exit is what
            // makes that safe: nothing is classified, so nothing can be
            // misrepresented.
            // One exit is the loop's `break`. For a single-exit loop that is the
            // exit. For a MULTI-exit loop, take it only when the choice is
            // unambiguous: the header's immediate post-dominator is where control
            // provably reconverges after the loop, so if that block is itself one
            // of the exits it IS the fall-out. When it is not (control reconverges
            // somewhere past the exits), no exit is privileged — keep every one of
            // them an explicit goto rather than guess which is the way out.
            let fallOut: Int?
            if exits.count <= 1 {
                fallOut = exits.first
            } else {
                let reconvergence = postDominators[header]
                fallOut = exits.contains(reconvergence) ? reconvergence : nil
            }
            loops[header] = LoopInfo(body: body, exit: fallOut, exits: exits)
        }
        self.loops = loops
    }

    /// Pull body blocks the linear walk never reached INSIDE their loop, so the
    /// loop owns its body instead of leaving them stranded as top-level labelled
    /// blocks. Only chunks that transfer control explicitly are moved: a chunk
    /// carrying a `// continues at` marker falls through to whatever follows it,
    /// and inside a loop that fall-through would read as looping back — a
    /// misrepresentation. Those stay at top level, unchanged.
    private func drainBodyInsideLoop(
        info: LoopInfo, context: LoopContext, stop: Int, indent: Int,
        visited: inout Set<Int>, gotoTargets: inout Set<Int>, depth: Int
    ) -> [String] {
        var lines: [String] = []
        for block in info.body.sorted() where !visited.contains(block) {
            var trialVisited = visited
            var trialGotos = gotoTargets
            let chunk = emit(
                from: block, until: stop, indent: indent + 1,
                visited: &trialVisited, gotoTargets: &trialGotos,
                loop: context, depth: depth + 1
            )
            guard !chunk.contains(where: { $0.contains("// continues at") }) else { continue }
            visited = trialVisited
            gotoTargets = trialGotos
            lines += chunk
        }
        return lines
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
        // Emission decides whether to print a block's `loc_<addr>:` label from
        // `gotoTargets` — which it also POPULATES as it goes. A goto emitted after
        // its target block was already written would therefore dangle. Run a
        // discovery sweep first and emit with the complete set; labels do not
        // affect control flow, so both sweeps produce the same structure.
        var discovered = Set<Int>()
        _ = emitSweep(gotoTargets: &discovered)
        var gotoTargets = discovered
        var lines = [header]
        if let objcLine { lines.append(objcLine) }
        lines += emitSweep(gotoTargets: &gotoTargets)
        lines.append("}")
        return lines
    }

    /// One full emission sweep: the walk from entry, then a drain of every block
    /// it did not reach (landing pads, depth-deferred blocks, multi-exit targets).
    private func emitSweep(gotoTargets: inout Set<Int>) -> [String] {
        var lines: [String] = []
        var visited = Set<Int>()
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
        return lines
    }

    /// If a loop header is purely a single loop-exit test — no side-effecting
    /// statement that would be dropped by hoisting the test, exactly one successor
    /// in the loop body and the other the loop's single structured exit — return
    /// the `while (…)` condition (oriented so `true` keeps the loop running) and
    /// the body's entry block. This rotates `while (true) { if (i >= n) break… }`
    /// into `while (i < n) { … }`. Returns nil (keep `while (true)`) for anything
    /// not provably this shape: a header that does real work, a multi-exit or
    /// mid-body exit, a `do/while` (exit at the back-edge), etc.
    private func whileCondition(header: Int, info: LoopInfo) -> (text: String, bodyStart: Int, exit: Int)? {
        let block = blocks[header]
        let succs = block.successors.compactMap { index(of: $0) }
        guard succs.count == 2 else { return nil }
        // Rotation lifts the header test into the `while`, which presumes a single
        // way out; a multi-exit loop stays `while (true)`.
        guard info.exits.count <= 1 else { return nil }
        let branch = condition(of: block)
        guard branch.text != "?" else { return nil }
        // The header must carry the loop test only: a statement that must run each
        // iteration would be lost by moving the test into the `while`.
        let hasStatement = block.instructions.contains { insn in
            !branch.consumed.contains(insn.address)
                && DisassembledFunction.pseudoStatement(of: insn, hideRuntime: true) != nil
        }
        guard !hasStatement else { return nil }
        // Exactly one successor continues the loop (in the body); the other leaves.
        let takenInBody = info.body.contains(succs[0])
        let fallInBody = info.body.contains(succs[1])
        guard takenInBody != fallInBody else { return nil }
        let exitSucc = takenInBody ? succs[1] : succs[0]
        // The exit must be the loop's structured exit or a `return`/`trap` tail the
        // loop falls out to — so control resumes cleanly there after the `while`.
        guard exitSucc == (info.exit ?? exit) || isTrivialTail(exitSucc) else { return nil }
        let bodyStart = takenInBody ? succs[0] : succs[1]
        // `succs[0]` is the branch-taken target. If taking the branch stays in the
        // loop, that condition keeps it running; otherwise invert the exit test.
        let text = takenInBody ? branch.text : Self.inverted(branch.text)
        return (text, bodyStart, exitSucc)
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

            // Enter a foldable loop. A header that is purely a single loop-exit
            // test rotates into `while (cond) { … }`; anything else stays
            // `while (true) { … }` with the test inside.
            if let info = loops[current], loop?.header != current {
                if gotoTargets.contains(current) { lines.append("\(pad)loc_\(hex(blocks[current].startAddress)):") }
                let context = LoopContext(
                    header: current,
                    exitNode: info.exit ?? (info.exits.count <= 1 ? exit : nil),
                    body: info.body,
                    boundsBody: info.exits.count > 1
                )
                if let rotated = whileCondition(header: current, info: info) {
                    visited.insert(current)   // header consumed as the loop condition
                    lines.append("\(pad)while (\(rotated.text)) {")
                    var body = emit(from: rotated.bodyStart, until: stop, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: context, depth: depth + 1)
                    // A trailing top-level `continue` is the loop's natural end —
                    // redundant once the test is in the `while`. Drop it.
                    if body.last == "\(pad)    continue" { body.removeLast() }
                    lines += body
                    // Append the proven induction body updates (`total += i`,
                    // `i += 1`) at the body end — the Swift for/while update
                    // position. Only when the loop condition is the tracer-baked
                    // one (which names `i`); if the condition fell back to raw
                    // registers, the names would be undefined.
                    let annotation = blocks[current].instructions.last?.annotation
                    if Self.bakedCondition(annotation) != nil {
                        for update in Self.bakedLoopUpdate(annotation) {
                            lines.append("\(pad)    \(update)")
                        }
                    }
                    lines += drainBodyInsideLoop(info: info, context: context, stop: stop, indent: indent, visited: &visited, gotoTargets: &gotoTargets, depth: depth)
                    lines.append("\(pad)}")
                    current = rotated.exit   // resume at the loop's exit successor
                } else {
                    lines.append("\(pad)while (true) {")
                    lines += emit(from: current, until: stop, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: context, depth: depth + 1)
                    lines += drainBodyInsideLoop(info: info, context: context, stop: stop, indent: indent, visited: &visited, gotoTargets: &gotoTargets, depth: depth)
                    lines.append("\(pad)}")
                    current = info.exit ?? exit
                }
                continue
            }

            visited.insert(current)
            let block = blocks[current]
            // Label a block that is a loop header, or a `goto` target the depth
            // guard deferred — so every emitted `goto loc_<addr>` resolves.
            if loops[current] == nil, isLoopHeader(current) {
                lines.append("\(pad)loc_\(hex(block.startAddress)):  // loop header")
            } else if gotoTargets.contains(current), loop?.header != current {
                // Not when this IS the header of the loop currently being emitted:
                // the `while` line already carries that label, and repeating it
                // inside the body would define the same label twice.
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
                // Same rule as the tail site. MEASURED: on every fixture this
                // site currently emits nothing but throwing-function error exits,
                // so routing it through `valuelessReturn` changes no output today.
                // It is here so the two emission sites cannot drift apart, not
                // because it fixes an observed case.
                if !emittedReturn { lines.append("\(pad)\(valuelessReturn)") }
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
                if let loop, loop.boundsBody, !loop.body.contains(merge),
                   !isTrivialTail(merge) {
                    gotoTargets.insert(merge)
                    lines.append("\(pad)goto loc_\(hex(blocks[merge].startAddress))")
                    break
                }
                current = merge
            } else if succs.count == 1 {
                let only = succs[0]
                if backSuccessors[current].contains(only) {
                    if let loop, only == loop.header { lines.append("\(pad)continue") }
                    else {
                        // The target header needs a label: once a loop folds it no
                        // longer prints `// loop header`, so an unregistered
                        // back-edge goto would dangle.
                        gotoTargets.insert(only)
                        lines.append("\(pad)goto loc_\(hex(blocks[only].startAddress))  // loop")
                    }
                    break
                }
                if let loop, let exitNode = loop.exitNode, only == exitNode {
                    lines.append("\(pad)break"); break
                }
                if let loop, loop.boundsBody, only != exit,
                   !loop.body.contains(only), !isTrivialTail(only) {
                    // Leaving a multi-exit loop: an explicit goto keeps the emitted
                    // body exactly the loop's blocks.
                    gotoTargets.insert(only)
                    lines.append("\(pad)goto loc_\(hex(blocks[only].startAddress))")
                    break
                }
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
            gotoTargets.insert(v)
            return ["\(pad)goto loc_\(hex(blocks[v].startAddress))  // loop"]
        }
        if let loop, let exitNode = loop.exitNode, v == exitNode { return ["\(pad)break"] }
        if let loop, loop.boundsBody, v != exit,
           !loop.body.contains(v), !isTrivialTail(v) {
            gotoTargets.insert(v)
            return ["\(pad)goto loc_\(hex(blocks[v].startAddress))"]
        }
        if v == merge || v == exit { return [] }
        return emit(from: v, until: merge, indent: indent, visited: &visited, gotoTargets: &gotoTargets, loop: loop, depth: depth + 1)
    }

    // MARK: - Conditions

    /// If the block's terminator is a Swift error check — a branch on the error
    /// register x21 against zero (`cbnz x21`, `cbz x21`, or `cmp x21, #0; b.ne/eq`)
    /// — return `error != nil` / `error == nil`. Nil when it is not that shape.
    private func swiftErrorCondition(of block: BasicBlock) -> String? {
        guard let terminator = block.instructions.last else { return nil }
        let (mnemonic, operands) = Self.decode(terminator.text)
        let firstReg = operands.first.flatMap(Self.canonicalRegister)
        if mnemonic == "cbnz", firstReg == "x21" { return "error != nil" }
        if mnemonic == "cbz", firstReg == "x21" { return "error == nil" }
        guard mnemonic == "b.ne" || mnemonic == "b.eq" else { return nil }
        let notEqual = mnemonic == "b.ne"
        // The nearest preceding flag-setting compare must test x21 against zero.
        for index in stride(from: block.instructions.count - 2, through: 0, by: -1) {
            let (m, ops) = Self.decode(block.instructions[index].text)
            guard ["cmp", "subs", "cmn"].contains(m), !ops.isEmpty else { continue }
            let testsX21 = ops.contains { Self.canonicalRegister($0) == "x21" }
            let versusZero = ops.contains { $0 == "xzr" || $0 == "wzr" || Self.cleanImmediate($0) == "0" }
            return (testsX21 && versusZero) ? (notEqual ? "error != nil" : "error == nil") : nil
        }
        return nil
    }

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
        // A test of the Swift error register (x21) against zero is an error check:
        // `x21 != 0` means a call threw. Name it (`error != nil`) instead of a raw
        // register — the compiler back-substitution below would otherwise mistake
        // the pre-call `mov x21, #0` for the tested value.
        if usesSwiftError, let errorCondition = swiftErrorCondition(of: block) {
            return (errorCondition, consumed)
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

    /// The loop induction body updates (`total += i`, `i += 1`), in order, the
    /// enrichment baked on a loop header's branch — or an empty array.
    private static func bakedLoopUpdate(_ annotation: String?) -> [String] {
        guard let annotation else { return [] }
        for note in annotation.components(separatedBy: "  ") {
            let trimmed = note.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("loop-update: ") else { continue }
            return String(trimmed.dropFirst("loop-update: ".count))
                .components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return []
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
        return valuelessReturn
    }

    /// How to render a `ret` whose value was not recovered.
    ///
    /// A bare `return` in a function that DOES return a value is misleading: it
    /// reads as "returns nothing" when it means "we did not recover what it
    /// returns". The tool's contract elsewhere is that an unprovable value
    /// renders `?`, so it should say so here too.
    ///
    /// Two deliberate refusals, both in the declining direction:
    ///
    /// - An unrecognisable signature (`sub_<addr>`, a thunk, a witness accessor)
    ///   keeps the bare form. Claiming a value exists would be a fabrication of
    ///   exactly the kind the `?` convention is meant to avoid.
    /// - A function that threads swifterror keeps it too. Its error exit really
    ///   does yield no value — the result travels in x21 — and this is a
    ///   per-function fact, so the two exits cannot be told apart here. Printing
    ///   `return ?` on a throw path would assert a missing value that was never
    ///   there. Where such a function's normal exit IS recovered it already
    ///   prints `return <expr>`, so the cost of declining is small.
    private var valuelessReturn: String {
        returnsValue && !usesSwiftError ? "return ?" : "return"
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
