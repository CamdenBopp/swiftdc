import Foundation
import Ccapstone

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
        Probe.inFunction(startAddress, displayName) {
            Probe.timed(.renderTime) {
                let output = renderStructuredBody(maxStructuringDepth: maxStructuringDepth)
                Probe.rendered(output, of: self, view: "structured")
                return output
            }
        }
    }

    private func renderStructuredBody(maxStructuringDepth: Int) -> String {
        let blocks = basicBlocks()
        guard blocks.count > 1 else { return Probe.muted { renderPseudo() } }

        let depth = maxStructuringDepth > 0 ? maxStructuringDepth : ControlFlowStructure.defaultMaxDepth
        let cfg = ControlFlowStructure(
            blocks: blocks, objectiveCArguments: objcMethod != nil, maxDepth: depth,
            isThrowing: signatureThrows,
            // A specialization that binds its thrown type to `Swift.Never`
            // cannot throw, but it still threads x21 under the convention of
            // the throwing function it specializes.
            threadsSwiftError: Self.splitSignature(analysisDisplayName)?.isThrowing ?? false,
            returnsValue: Self.signatureReturnsValue(
                displayName: analysisDisplayName, objcSignature: objcMethod?.signature
            )
        )
        let header = "\(displayName) {"
        // The ObjC signature and the async-chain line share one header slot: at
        // most one applies (an ObjC IMP is never an async funclet).
        let objcLine = objcMethod.map { "    // \($0.signature)" }
            ?? asyncHeaderLine().map { "    \($0)" }

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
    /// Whether the function's result type is known at all: an ObjC method
    /// signature, a Swift function type, or an accessor's ` : Type`. A
    /// stripped `sub_…` or a C symbol has none, and "returns nothing" must
    /// not be read into that.
    static func signatureKnown(displayName: String, objcSignature: String?) -> Bool {
        objcSignature != nil || Self.splitSignature(displayName) != nil || displayName.contains(" : ")
    }

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

        // Swift function type. `splitSignature` skips a parameter's nested
        // arrow (`((A) -> B) -> C`) and stops at a closure's ` in <context>`,
        // which the last `->` did not: a `-> ()` closure inside a `-> Never`
        // function read as returning a value.
        if let result = Self.splitSignature(displayName)?.result {
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

    /// A normal machine RET delivers this source value. Async functions use
    /// their proven ResumeParent transfer instead; Never has no normal result.
    var hasProvenMachineValueReturn: Bool {
        if let signature = Self.splitSignature(analysisDisplayName) {
            if signature.isAsync || (signature.isThrowing && !specializationBindsThrownTypeToNever) || signature.result == "Swift.Never" || signature.result == "Never" { return false }
        }
        return Self.signatureReturnsValue(displayName: analysisDisplayName, objcSignature: objcMethod?.signature)
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
        /// A switch lies between this loop and the current statement. Its bare
        /// `break` exits the switch, so the loop exit needs an explicit goto.
        let exitsThroughSwitch: Bool
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
    private let isThrowing: Bool               // the signature says `throws`
    /// Per block, the argument registers (x2–x7) some path from entry may
    /// have written before the block starts. Empty unless ObjC arguments.
    private let argumentsWrittenBefore: [Set<String>]

    init(blocks: [BasicBlock], objectiveCArguments: Bool = false, maxDepth: Int = ControlFlowStructure.defaultMaxDepth, isThrowing: Bool = false, threadsSwiftError: Bool? = nil, returnsValue: Bool = false) {
        self.returnsValue = returnsValue
        self.blocks = blocks
        self.exit = blocks.count
        self.objectiveCArguments = objectiveCArguments
        self.maxDepth = maxDepth
        // The Swift error register (x21) is meaningful here only when the function
        // actually threads swifterror. A `throws` function does. A non-throwing
        // caller of a throwing callee does too: it clears x21 (`mov x21, #0`)
        // before the call AND tests it (`x21 == 0`) after, to catch a thrown
        // error. **Both** are required — a function that merely zeroes x21 and
        // never reads it back is not error-checking; x21 is just an incidental
        // callee-saved scratch there.
        //
        // Requiring the test, not just the clear, fixes two measured misfires
        // where the value was suppressed to a bare `return` (or `x21 == 0`
        // mis-named `error != nil`) purely because a BOOL/pointer computation
        // happened to zero x21:
        //   • Objective-C `isEqual:` (7 in UserNotifications): clears x21, then
        //     tests `cmp x21, x0` — against a register, not zero — so it is not a
        //     swifterror test and no longer qualifies.
        //   • Swift Publisher constructors (10 in Combine, e.g. `compactMap`,
        //     `reduce`, `min(by:)`): clear x21 as scratch, never test it.
        // The genuine cases (a `throws` function, or a Combine "Try" operator that
        // clears-and-tests x21 to catch its closure's throw — 28 in Combine) still
        // qualify. The `!objectiveCArguments` belt-and-suspenders stays: ObjC never
        // threads swifterror even if it coincidentally clears-and-tests x21.
        self.usesSwiftError = !objectiveCArguments && ((threadsSwiftError ?? isThrowing)
            || (Self.clearsSwiftErrorRegister(blocks) && Self.testsSwiftErrorRegister(blocks)))
        self.isThrowing = !objectiveCArguments && isThrowing
        var indexByAddress: [UInt64: Int] = [:]
        for (index, block) in blocks.enumerated() { indexByAddress[block.startAddress] = index }
        self.indexByAddress = indexByAddress
        self.argumentsWrittenBefore = objectiveCArguments
            ? Self.argumentsWrittenBefore(blocks, indexByAddress: indexByAddress) : blocks.map { _ in [] }

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
        // A trap is abnormal termination, not the loop's structured exit.
        // A return block can be its ordinary fall-out: excluding it left no
        // exit to translate to `break` for optimized array iteration.
        func isSinkTail(_ s: Int) -> Bool {
            guard forward[s].isEmpty, backward[s].isEmpty, let last = blocks[s].instructions.last
            else { return false }
            return Self.isTrap(last)
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
        // Task-locals do not cross a raw thread: carry the probe context over,
        // or every event the structurer records is silently lost.
        let context = Probe.context
        let thread = Thread {
            Probe.withContext(context, work)
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
        // Muted: it walks the same blocks as the emitting sweep below.
        Probe.muted { _ = emitSweep(gotoTargets: &discovered) }
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
                // A detached block keeps its address identity: code after a
                // trap is not the straight-line body of what precedes it.
                Probe.record(.structureDetachedBlock, at: blocks[index].startAddress)
                gotoTargets.insert(index)
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
        // A tail is the fall-out only when the loop has no other structured
        // exit: a `break` resumes after the `while` too. An overflow-checked
        // loop rotated on its `b.vs` printed its normal exit as `break` into
        // the `trap()` that follows, claiming every run ends in a trap.
        guard exitSucc == (info.exit ?? exit)
                || (isTrivialTail(exitSucc) && (info.exit == nil || info.exit == exitSucc))
        else { return nil }
        let bodyStart = takenInBody ? succs[0] : succs[1]
        // `succs[0]` is the branch-taken target. If taking the branch stays in the
        // loop, that condition keeps it running; otherwise invert the exit test.
        let text = takenInBody ? branch.text : Self.inverted(branch.text)
        return (text, bodyStart, exitSucc)
    }

    func emit(from start: Int, until stop: Int, indent: Int, visited: inout Set<Int>, gotoTargets: inout Set<Int>, loop: LoopContext?, depth: Int) -> [String] {
        if depth > maxDepth,
           start != stop, start != exit, !visited.contains(start), !isTrivialTail(start) {
            Probe.record(.structureDepthGoto, at: blocks[start].startAddress, ["depth": .int(depth)])
            gotoTargets.insert(start)
            return ["\(String(repeating: "    ", count: indent))goto loc_\(hex(blocks[start].startAddress))"]
        }
        var lines: [String] = []
        var current = start
        while current != stop, current != exit {
            let pad = String(repeating: "    ", count: indent)

            if let loop, current == loop.exitNode {
                lines.append(loopExitStatement(to: current, loop: loop, pad: pad, gotoTargets: &gotoTargets))
                break
            }

            if isTrivialTail(current) {
                lines.append("\(pad)\(tailStatement(blocks[current]))")
                break
            }
            if visited.contains(current) {
                if let loop, current == loop.header { lines += loopBackStatements(header: loop.header, pad: pad) }
                else {
                    // A shared continuation emitted in another branch: a comment
                    // here silently replaced the transfer with fall-through, so
                    // jump to it, and label it even when its body came first.
                    gotoTargets.insert(current)
                    lines.append("\(pad)goto loc_\(hex(blocks[current].startAddress))")
                }
                break
            }

            // Enter a foldable loop. A header that is purely a single loop-exit
            // test rotates into `while (cond) { … }`; anything else stays
            // `while (true) { … }` with the test inside.
            if let info = loops[current], loop?.header != current {
                if gotoTargets.contains(current) { lines.append("\(pad)loc_\(hex(blocks[current].startAddress)):") }
                for declaration in Self.bakedLoopInitialization(blocks[current].instructions.last) {
                    lines.append("\(pad)\(declaration)")
                }
                let context = LoopContext(
                    header: current,
                    exitNode: info.exit ?? (info.exits.count <= 1 ? exit : nil),
                    body: info.body,
                    boundsBody: info.exits.count > 1,
                    exitsThroughSwitch: false
                )
                if let rotated = whileCondition(header: current, info: info) {
                    visited.insert(current)   // header consumed as the loop condition
                    lines.append("\(pad)while (\(rotated.text)) {")
                    var body = emit(from: rotated.bodyStart, until: stop, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: context, depth: depth + 1)
                    // A trailing top-level `continue` is the loop's natural end —
                    // redundant once the test is in the `while`. Drop it.
                    if body.last == "\(pad)    continue" { body.removeLast() }
                    lines += body
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
            let isSwitch = block.switchCases != nil
            let overflowContinuation = succs.count == 2 && !isSwitch ? overflowGuardContinuation(current) : nil
            // Resolve the branch condition first: a boolean-returning call whose
            // result only feeds the test is inlined into the condition, so it is
            // dropped from the straight-line statements to avoid printing it twice.
            let branch = (succs.count >= 2 && overflowContinuation == nil && !isSwitch) ? condition(of: block) : nil
            var emittedReturn = false
            for insn in block.instructions {
                if branch?.consumed.contains(insn.address) == true { continue }
                if let statement = DisassembledFunction.pseudoStatement(of: insn, hideRuntime: true) {
                    for line in statement.components(separatedBy: "\n") { lines.append("\(pad)\(line)") }
                    // An exit's statement, or a throw after this one, ends
                    // the path: `pseudoStatement` renders either ahead of
                    // anything else on the instruction.
                    emittedReturn = emittedReturn || insn.exit != nil || insn.thenThrows
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

            if let cases = block.switchCases {
                // A recovered jump table: one arm per distinct target, labelled
                // with every case index that reaches it. The index expression is
                // not tracked yet, so it reads `?`.
                let merge = ipdom[current]
                var order: [UInt64] = []
                var labels: [UInt64: [Int]] = [:]
                for (caseIndex, target) in cases.enumerated() {
                    if labels[target] == nil { order.append(target) }
                    labels[target, default: []].append(caseIndex)
                }
                Probe.record(.structureUnknownSwitchIndex, at: blocks[current].startAddress, ["cases": .int(cases.count)])
                lines.append("\(pad)switch (?) {")
                let caseLoop = loop.map {
                    LoopContext(header: $0.header, exitNode: $0.exitNode, body: $0.body,
                                boundsBody: $0.boundsBody, exitsThroughSwitch: true)
                }
                for target in order {
                    guard let arm = index(of: target), let caseLabels = labels[target] else { continue }
                    lines.append("\(pad)case \(caseLabels.map(String.init).joined(separator: ", ")):")
                    let body = arm == merge
                        ? []
                        : edge(from: current, to: arm, until: merge, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: caseLoop, depth: depth + 1)
                    lines += body.isEmpty ? ["\(pad)    break"] : body
                }
                lines.append("\(pad)}")
                if merge == exit { break }
                if let loop, loop.boundsBody, !loop.body.contains(merge),
                   !isTrivialTail(merge) {
                    gotoTargets.insert(merge)
                    lines.append("\(pad)goto loc_\(hex(blocks[merge].startAddress))")
                    break
                }
                current = merge
            } else if succs.count >= 2 {
                let merge = ipdom[current]
                let thenLines = edge(from: current, to: succs[0], until: merge, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: loop, depth: depth + 1)
                // Even an edge to the join can leave the current loop. Let
                // `edge` spell that transfer as `break` before suppressing an
                // ordinary join edge; skipping it erased a rotated loop's exit.
                let elseLines = edge(from: current, to: succs[1], until: merge, indent: indent + 1, visited: &visited, gotoTargets: &gotoTargets, loop: loop, depth: depth + 1)
                let cond = branch?.text ?? "?"
                if cond == "?" { Probe.record(.structureUnknownCondition, at: blocks[current].startAddress) }
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
                    if let loop, only == loop.header { lines += loopBackStatements(header: loop.header, pad: pad) }
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
                    lines.append(loopExitStatement(to: only, loop: loop, pad: pad, gotoTargets: &gotoTargets))
                    break
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
            if let loop, v == loop.header { return loopBackStatements(header: loop.header, pad: pad) }
            gotoTargets.insert(v)
            return ["\(pad)goto loc_\(hex(blocks[v].startAddress))  // loop"]
        }
        if let loop, let exitNode = loop.exitNode, v == exitNode {
            return [loopExitStatement(to: v, loop: loop, pad: pad, gotoTargets: &gotoTargets)]
        }
        if let loop, loop.boundsBody, v != exit,
           !loop.body.contains(v), !isTrivialTail(v) {
            gotoTargets.insert(v)
            return ["\(pad)goto loc_\(hex(blocks[v].startAddress))"]
        }
        if v == merge || v == exit { return [] }
        return emit(from: v, until: merge, indent: indent, visited: &visited, gotoTargets: &gotoTargets, loop: loop, depth: depth + 1)
    }

    /// A break can name this loop only when no switch intervenes. Keeping the
    /// target as a goto otherwise also registers its label in the discovery pass.
    private func loopExitStatement(to target: Int, loop: LoopContext, pad: String, gotoTargets: inout Set<Int>) -> String {
        guard loop.exitsThroughSwitch else { return "\(pad)break" }
        gotoTargets.insert(target)
        return "\(pad)goto loc_\(hex(blocks[target].startAddress))"
    }

    // MARK: - Conditions

    /// If the block's terminator is a Swift error check — a branch on the error
    /// register x21 against zero (`cbnz x21`, `cbz x21`, or `cmp x21, #0; b.ne/eq`)
    /// — return `error != nil` / `error == nil`. Nil when it is not that shape.
    /// Does any instruction zero x21 (`mov x21, #0` / `mov x21, xzr`)? The
    /// swifterror setup before a throwing call.
    static func clearsSwiftErrorRegister(_ blocks: [BasicBlock]) -> Bool {
        blocks.contains { block in
            block.instructions.contains { insn in
                let (m, ops) = decode(insn.text)
                return m == "mov" && ops.count >= 2
                    && canonicalRegister(ops[0]) == "x21"
                    && (cleanImmediate(ops[1]) == "0" || ops[1] == "xzr")
            }
        }
    }

    /// Does any instruction test x21 **against zero** (`cbz`/`cbnz x21`, or a
    /// `cmp`/`subs`/`cmn` of x21 with zero)? The swifterror check after a call.
    /// A test against another register (`cmp x21, x0`) does not count — that is
    /// not reading the error register for a throw.
    static func testsSwiftErrorRegister(_ blocks: [BasicBlock]) -> Bool {
        blocks.contains { block in
            block.instructions.contains { insn in
                let (m, ops) = decode(insn.text)
                if (m == "cbz" || m == "cbnz"), ops.first.flatMap(canonicalRegister) == "x21" {
                    return true
                }
                guard ["cmp", "subs", "cmn"].contains(m) else { return false }
                let hasX21 = ops.contains { canonicalRegister($0) == "x21" }
                let hasZero = ops.contains { $0 == "xzr" || $0 == "wzr" || cleanImmediate($0) == "0" }
                return hasX21 && hasZero
            }
        }
    }

    /// Whether the nearest definition of x21 before `index` copies x0 out of
    /// the call just before it: a call result kept live in a callee-saved
    /// register, not an armed swifterror slot.
    static func holdsCallResult(x21Before index: Int, in block: BasicBlock) -> Bool {
        for earlier in stride(from: index - 1, through: 0, by: -1) {
            let (mnemonic, ops) = decode(block.instructions[earlier].text)
            guard let dest = ops.first, canonicalRegister(dest) == "x21" else { continue }
            return mnemonic == "mov" && ops.count >= 2 && canonicalRegister(ops[1]) == "x0"
                && earlier > 0 && block.instructions[earlier - 1].controlFlow == .call
        }
        return false
    }

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
    func condition(of block: BasicBlock) -> (text: String, consumed: Set<UInt64>) {
        var consumed: Set<UInt64> = []
        guard let terminator = block.instructions.last else { return ("?", consumed) }
        // Prefer the value tracer's reconstructed comparison when the enrichment
        // baked one (`cond:` note) — it names the operands (`arg0 >= arg1`) where
        // the text back-substitution below can only reach raw registers. Only
        // clean scalar comparisons are baked; message-send/boolean tests are left
        // to the text path, which inlines them more readably.
        if let baked = Self.bakedCondition(terminator) {
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
                || Self.isResultBinding(value)
                || isBooleanSource(operand, before: before, in: block)
        }
        // Comparing with 0 is a truth test whatever the value. Comparing with
        // 1, or testing bit 0, is one only for a Bool: an Int-returning call
        // tested `== 1` rendered `if (level())`, true for 2 as well, and
        // `level % 2 == 0` (`tbz x0, #0`) rendered `if (!level())`.
        func isProvenBoolean(_ value: String, operand: String, before: Int) -> Bool {
            value.hasPrefix("!") || isBooleanSource(operand, before: before, in: block)
        }
        switch mnemonic {
        case "cbz":
            let operand = operands.first ?? "?"
            let value = resolve(operand, before: last, in: block, consumed: &consumed, width: .belowSignedWord)
            return (isBoolean(value, operand: operand, before: last) ? "!\(value)" : "\(value) == 0", consumed)
        case "cbnz":
            let operand = operands.first ?? "?"
            let value = resolve(operand, before: last, in: block, consumed: &consumed, width: .belowSignedWord)
            return (isBoolean(value, operand: operand, before: last) ? value : "\(value) != 0", consumed)
        case "tbz":
            let operand = operands.first ?? "?"
            let bit = Self.cleanImmediate(operands.count > 1 ? operands[1] : "?")
            // A w operand tests a bit below 32, the same bit of a definition
            // of either width.
            let value = resolve(operand, before: last, in: block, consumed: &consumed,
                                width: operand.hasPrefix("w") ? .any : .exact)
            // Bit 0 is the boolean bit: `tbz X, #0` branches when X is false.
            if bit == "0", isProvenBoolean(value, operand: operand, before: last) { return ("!\(value)", consumed) }
            return ("bit \(bit) of \(value) clear", consumed)
        case "tbnz":
            let operand = operands.first ?? "?"
            let bit = Self.cleanImmediate(operands.count > 1 ? operands[1] : "?")
            // A w operand tests a bit below 32, the same bit of a definition
            // of either width.
            let value = resolve(operand, before: last, in: block, consumed: &consumed,
                                width: operand.hasPrefix("w") ? .any : .exact)
            if bit == "0", isProvenBoolean(value, operand: operand, before: last) { return (value, consumed) }
            return ("bit \(bit) of \(value) set", consumed)
        default:
            let op = Self.conditionOperator(mnemonic)
            for index in stride(from: last - 1, through: 0, by: -1) {
                let (m, ops) = Self.decode(block.instructions[index].text)
                // The branch reads the flags of the LAST instruction that set
                // them. Walking past one this path cannot read (`ccmp`,
                // `fcmp`, `ngcs`, …) to an earlier `cmp` bound the condition to
                // the wrong compare: `cmp; ccmp …, ge; b.lt`, taken iff
                // `lo <= x < hi`, rendered `x < lo`. Such a branch declines.
                let setsFlags = block.instructions[index].detail?.updatesFlags
                    ?? Self.flagSettingMnemonics.contains(m)
                if setsFlags, !["cmp", "subs", "cmn", "adds", "tst", "ands"].contains(m) {
                    Probe.record(.structureUnreadableFlags, at: block.instructions[index].address, ["setter": .label(m)])
                    return ("?", consumed)
                }
                if ["cmp", "subs", "cmn", "adds"].contains(m), ops.count >= 2 {
                    // `cmp`/`cmn` compare their two operands; `subs`/`adds` write a
                    // destination first, so their compared operands are 1 and 2 —
                    // reading operand 0 would test the result register, not the
                    // comparison (the source of bogus `x8 >= …` conditions).
                    let hasDestination = (m == "subs" || m == "adds") && ops.count >= 3
                    let lhsIndex = hasDestination ? 1 : 0
                    let rhsIndex = hasDestination ? 2 : 1
                    // A value below 2^31 compares the same at either width
                    // against an immediate, and under equality or an unsigned
                    // order against a register too (zero-extension keeps
                    // those). A signed order against a register does not, nor
                    // does a sum, which may cross 2^31.
                    let sums = m == "cmn" || m == "adds"
                    let orderFree = op == "==" || op == "!=" || op.hasSuffix("\u{1D41}")
                    let lhsRule: WidthRule = !sums && (ops[rhsIndex].hasPrefix("#") || orderFree) ? .belowSignedWord : .exact
                    let rhsRule: WidthRule = !sums && orderFree ? .belowSignedWord : .exact
                    let lhs = narrowResolve(ops[lhsIndex], before: index, in: block, consumed: &consumed, width: lhsRule)
                    // The second operand can carry a shift or an extend
                    // (`cmp x21, x8, lsr #1`, `cmp x0, #0x1, lsl #12`); read
                    // without it, the compare named another value.
                    guard let rhs = Self.applyingModifier(
                        narrowResolve(ops[rhsIndex], before: index, in: block, consumed: &consumed, width: rhsRule),
                        operand: ops[rhsIndex], trailing: ops[(rhsIndex + 1)...]),
                          let rawRHS = Self.applyingModifier(
                        Self.cleanImmediate(ops[rhsIndex]), operand: ops[rhsIndex], trailing: ops[(rhsIndex + 1)...])
                    else { return ("?", consumed) }
                    // `cmn`/`adds` set the flags from `lhs + rhs`: they compare lhs
                    // with -rhs. Read like `cmp`, `cmn x0, #1; b.eq` (x == -1)
                    // rendered `x0 == 1`. `b.mi`/`b.pl` test the sign of that
                    // difference or sum, not of lhs.
                    // `cmn a, b` sets the flags from `a + b`. Only equality, the
                    // sign of the sum, and an order against a nonzero immediate
                    // read as a comparison with `-b`: the carry of `a + 0` is
                    // clear while `a >=ᵁ -0` always holds, and a signed order
                    // against `-b` is wrong when b is the minimum.
                    if sums, !["==", "!=", "< 0 //", ">= 0 //"].contains(op) {
                        guard ops[rhsIndex].hasPrefix("#"), !(op.hasSuffix("\u{1D41}") && rawRHS == "0")
                        else { return ("?", consumed) }
                    }
                    func compare(_ l: String, _ r: String) -> String {
                        if op == "< 0 //" || op == ">= 0 //" {
                            return "(\(l) \(sums ? "+" : "-") \(r)) \(op == "< 0 //" ? "<" : ">=") 0"
                        }
                        return "\(l) \(op) \(sums ? Self.negatedOperand(r) : r)"
                    }
                    // If back-substitution collapsed distinct operands to the same
                    // text, it lost information — show the raw registers instead.
                    if lhs == rhs, ops[lhsIndex] != ops[rhsIndex] {
                        return (compare(ops[lhsIndex], rawRHS), consumed)
                    }
                    if !sums, rhs == "0" ? isBoolean(lhs, operand: ops[lhsIndex], before: index)
                                         : isProvenBoolean(lhs, operand: ops[lhsIndex], before: index),
                       let simplified = Self.booleanComparison(lhs: lhs, op: op, rhs: rhs) {
                        return (simplified, consumed)
                    }
                    return (compare(lhs, rhs), consumed)
                }
                // `tst` sets N and Z from the masked value and clears C and V,
                // so a signed order compares it with 0, and `b.mi`/`b.pl` test
                // its sign. A carry or overflow condition is constant, never a
                // comparison: `tst w8, #0xff; b.hs` is never taken. `ands` is
                // `tst` that also keeps the result.
                if (m == "tst" && ops.count >= 2) || (m == "ands" && ops.count >= 3) {
                    let first = m == "tst" ? 0 : 1
                    let relation = op == "< 0 //" ? "<" : op == ">= 0 //" ? ">=" : op
                    guard ["==", "!=", "<", "<=", ">", ">="].contains(relation),
                          let mask = Self.applyingModifier(Self.cleanImmediate(ops[first + 1]), operand: ops[first + 1],
                                                           trailing: ops[(first + 2)...])
                    else { return ("?", consumed) }
                    let tested = narrowResolve(ops[first], before: index, in: block, consumed: &consumed, keepsWordNumber: false,
                                               width: ops[first + 1].hasPrefix("#") ? .belowSignedWord : .exact)
                    return ("(\(tested) & \(mask)) \(relation) 0", consumed)
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
            if instruction.controlFlow == .call {
                // A call's declared `-> Swift.Bool` result is a Bool in x0.
                if register == "x0", let callee = DisassembledFunction.calleeName(of: instruction),
                   ["Swift.Bool", "Builtin.Int1"].contains(DisassembledFunction.splitSignature(callee)?.result ?? "")
                    || DisassembledFunction.isUniquenessCheck(callee) {
                    return true
                }
                if let number = Int(register.dropFirst()), number <= 17 { return false }
            }
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
    /// `resolve` for an operand of a flag-setting compare. A 32-bit operand
    /// that folds to a constant keeps its register: a number has no width
    /// to read it at, and `eor w8, wzr, #0x801f801f; cmp w8, #0; b.lt`, taken
    /// because the word is negative, rendered `0x801f801f < 0`. A single
    /// number in [-2^31, 2^31) reads the same as a word and as a doubleword,
    /// signed or not, so a compare keeps it (`w8 <ᵁ 0xd800`); a `tst`, whose
    /// mask may set bit 31, does not.
    private func narrowResolve(_ token: String, before: Int, in block: BasicBlock, consumed: inout Set<UInt64>,
                               keepsWordNumber: Bool = true, width rule: WidthRule = .exact) -> String {
        let value = resolve(token, before: before, in: block, consumed: &consumed, width: rule)
        guard token.hasPrefix("w"),
              value.replacingOccurrences(of: #"0x[0-9a-f]+|[0-9]+"#, with: "", options: .regularExpression)
                .allSatisfy({ !$0.isLetter && !$0.isNumber })
        else { return value }
        if keepsWordNumber, let number = Self.signedNumber(value), number >= -(1 << 31), number < 1 << 31 { return value }
        return token
    }

    /// Whether x0 before `index` is a call's result whose declared type
    /// fits in a word: its low word is the whole value.
    private static func producesWordResult(before index: Int, in block: BasicBlock) -> Bool {
        for earlier in stride(from: index - 1, through: 0, by: -1) {
            let instruction = block.instructions[earlier]
            if instruction.controlFlow == .call {
                guard let callee = DisassembledFunction.calleeName(of: instruction) else { return false }
                return DisassembledFunction.resultFitsInWord(callee)
            }
            guard let detail = instruction.detail else { return false }
            if detail.writtenRegisterKeys.contains("x0") { return false }
        }
        return false
    }

    /// A rendered number (`7`, `0x1c`, `-0x10`), or nil for anything else.
    private static func signedNumber(_ text: String) -> Int64? {
        let negative = text.hasPrefix("-")
        let digits = negative ? text.dropFirst() : Substring(text)
        guard let magnitude = digits.hasPrefix("0x") ? Int64(digits.dropFirst(2), radix: 16) : Int64(digits) else { return nil }
        return negative ? -magnitude : magnitude
    }

    /// Whether a definition's value is provably in [0, 2^31): such a value
    /// is the same as a word and as a doubleword, signed or not.
    private static func isBelowSignedWord(_ instruction: Instruction, mnemonic: String, operands: [String]) -> Bool {
        if mnemonic == "mov", operands.count >= 2, operands[1].hasPrefix("#") {
            guard let number = signedNumber(cleanImmediate(operands[1])) else { return false }
            return number >= 0 && number < 1 << 31
        }
        guard let detail = instruction.detail, InstructionSemantics.covers(detail.id),
              let effect = InstructionSemantics.effect(of: detail)
        else { return false }
        func constant(_ term: SemanticTerm) -> UInt64? {
            switch term {
            case .constant(let value): return value
            case .operand(let index):
                guard index < detail.operands.count, detail.operands[index].operand.register == nil else { return nil }
                return detail.operands[index].shiftedImmediate.map { UInt64(bitPattern: $0) }
            case .binary(.bitAnd, let lhs, let rhs):
                guard let left = constant(lhs), let right = constant(rhs) else { return nil }
                return left & right
            default: return nil
            }
        }
        /// How many low bits can be set.
        func bits(_ term: SemanticTerm) -> Int {
            if let value = constant(term) { return 64 - value.leadingZeroBitCount }
            switch term {
            case .register(let index):
                guard index < detail.operands.count, let register = detail.operands[index].operand.register else { return 64 }
                return register.kind == .zero ? 0 : register.widthBits
            case .operand(let index):
                guard index < detail.operands.count, let register = detail.operands[index].operand.register else { return 64 }
                let info = detail.operands[index]
                if register.kind == .zero { return 0 }
                return info.shift.type == AARCH64_SFT_INVALID && info.extender == AARCH64_EXT_INVALID ? register.widthBits : 64
            case .binary(.bitAnd, let lhs, let rhs): return min(bits(lhs), bits(rhs))
            case .binary(.bitOr, let lhs, let rhs), .binary(.bitXor, let lhs, let rhs): return max(bits(lhs), bits(rhs))
            case .binary(.shiftRight, let lhs, let rhs):
                guard let amount = constant(rhs) else { return bits(lhs) }
                return max(0, bits(lhs) - Int(min(amount, 64)))
            case .binary(.shiftLeft, let lhs, let rhs):
                guard let amount = constant(rhs) else { return 64 }
                return min(64, bits(lhs) + Int(min(amount, 64)))
            case .zeroExtend(_, let width): return width
            default: return 64
            }
        }
        return min(bits(effect.value), effect.destination.widthBits) <= 31
    }

    /// When `resolve` may substitute a definition of the other width than
    /// the tested register. A value of one width does not spell the other's
    /// in general; `belowSignedWord` admits a value proven in [0, 2^31),
    /// which reads the same at both when nothing else in the test has a
    /// width (a zero test, or a compare with an immediate); `any` is for a
    /// test that reads one low bit.
    enum WidthRule { case exact, belowSignedWord, any }

    private func resolve(_ token: String, before: Int, in block: BasicBlock, consumed: inout Set<UInt64>,
                         width rule: WidthRule = .exact) -> String {
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
                    if case .selfInitialization? = instruction.statement { return "self" }
                    // A result bound because it has several uses is tested by
                    // its name; inlining the call would show it run again.
                    if let binding = instruction.binding { return binding.name }
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
                       DisassembledFunction.returnsItsArgument(callee) {
                        continue
                    }
                }
                return token
            }
            // A callee that may throw returns its error in x21 (Swift's
            // swifterror), so no definition before the call is the value tested
            // after it. Walking past one rendered a post-call error test as a
            // test of whatever armed x21: the zero (`0 != 0`), or the register
            // the caller re-armed it from (`x19 != 0`, 180 functions in
            // SwiftData). So stop at any callee not proven non-throwing, unless
            // x21 holds a call's result: an armed x21 is the caller's current
            // error (null, or one it was handed), never a fresh x0, so a
            // result kept in x21 means the call between is not a swifterror
            // call (`bl f; mov w21, w0; bl g; tbz w21` still reads `!f()`).
            if instruction.controlFlow == .call, register == "x21",
               !ValueTracer.provablyDoesNotThrow(DisassembledFunction.calleeName(of: instruction) ?? ""),
               !Self.holdsCallResult(x21Before: index, in: block) {
                return token
            }
            let (mnemonic, ops) = Self.decode(instruction.text)
            guard let dest = ops.first, Self.canonicalRegister(dest) == register else {
                // The register's last write need not be a first operand: `ldp
                // x21, x8, [x8, #0x10]` loads x8, and a writeback moves its
                // base. Walking past it found an older definition
                // (RetainRegister.enroll read `x8 & 0x…ff8`, the pointer
                // the pair was loaded from). Without detail it may be one.
                guard let detail = instruction.detail, !detail.writtenRegisterKeys.contains(register) else { return token }
                continue
            }
            // A definition of the other width is not the value tested: `eor
            // x8, …; cmp w8, #7` compares the low word of a 64-bit result,
            // and `orr w8, w1, #…; cmp x8, #0; b.gt` a zero-extended one,
            // whose sign is not the 32-bit expression's. See `WidthRule` for
            // the exceptions (`lsr x8, x1, #62; cmp w8, #1`).
            if let tested = token.first, let defined = dest.first, "wx".contains(tested), "wx".contains(defined),
               tested != defined,
               // A word test of a saved call result whose declared type is a
               // word or narrower reads that result (`mov x26, x0; cmp w26,
               // #1` after swift_getEnumCaseMultiPayload, `unsigned`).
               !(tested == "w" && mnemonic == "mov" && ops.count == 2 && Self.canonicalRegister(ops[1]) == "x0"
                 && Self.producesWordResult(before: index, in: block)) {
                switch rule {
                case .any: break
                case .belowSignedWord:
                    if !Self.isBelowSignedWord(instruction, mnemonic: mnemonic, operands: ops) { return token }
                case .exact:
                    // A number has no width of its own: one in [0, 2^31) is
                    // the same value at both (`mov w8, #0x7fffffff; cmp x8, x9`).
                    let number = mnemonic == "mov" && ops.count >= 2 && ops[1].hasPrefix("#")
                    if !number || !Self.isBelowSignedWord(instruction, mnemonic: mnemonic, operands: ops) { return token }
                }
            }
            if let field = instruction.fieldRead { return field }
            // The substitution names the definition's source registers, which
            // read as their values at the test. One written in between holds
            // something else there: `and w8, w0, #0xff; add w0, w0, #1; cmp
            // w8, #7` rendered `(w0 & 0xff) == 7`. A copy of x0 resolves to the
            // call it saved, which no later write changes.
            let sources = ops.dropFirst().compactMap(Self.canonicalRegister)
            let savesCallResult = mnemonic == "mov" && sources == ["x0"]
            if !savesCallResult, !Self.registers(sources, surviveFrom: index, to: before, in: block) { return token }
            // Nor may the definition itself overwrite one: `lsr x8, x8, #3;
            // cmp x8, #1` rendered `(x8 >>ᵁ 3) == 1`, shifting the result
            // again. A mask, a set or a copy is idempotent, so `and x5, x5,
            // #0x80; cbnz x5` still reads `(x5 & 0x80) != 0` truly, as does
            // the mask `ubfx x4, x4, #0, #8`.
            let idempotent = ["and", "ands", "orr", "mov"].contains(mnemonic)
                || (mnemonic == "ubfx" && ops.count >= 3 && Self.immediateValue(ops[2]) == 0)
            if !savesCallResult, sources.contains(register), !idempotent { return token }
            // What the definition computes is InstructionSemantics', shared with
            // the value tracer. A copy keeps its own handling below (the saved
            // call result, an immediate as printed).
            if let detail = instruction.detail, InstructionSemantics.covers(detail.id),
               mnemonic != "mov", detail.id != AARCH64_INS_MOV, detail.id != AARCH64_INS_MOVZ {
                guard let effect = InstructionSemantics.effect(of: detail),
                      let text = Self.render(effect.value, detail, destinationBits: effect.destination.widthBits)
                else { return token }
                return text
            }
            switch mnemonic {
            case "and" where ops.count >= 3, "orr" where ops.count >= 3:
                guard let second = Self.applyingModifier(Self.cleanImmediate(ops[2]), operand: ops[2], trailing: ops[3...])
                else { return token }
                return "(\(ops[1]) \(mnemonic == "and" ? "&" : "|") \(second))"
            // A logical and an arithmetic shift differ on a negative value, so
            // each names its kind, as the tracer's expressions do (`>>ᵁ`, `>>ˢ`).
            case "lsr": return ops.count >= 3 ? "(\(ops[1]) >>\u{1D41} \(Self.cleanImmediate(ops[2])))" : token
            case "asr": return ops.count >= 3 ? "(\(ops[1]) >>\u{02E2} \(Self.cleanImmediate(ops[2])))" : token
            case "lsl": return ops.count >= 3 ? "(\(ops[1]) << \(Self.cleanImmediate(ops[2])))" : token
            // `ubfx d, s, #lsb, #width` is `(s >> lsb) & (2^width - 1)`, not a
            // copy of s: read as one, the Go float test `ubfx x13, x12, #23,
            // #8; cmp x13, #0xff` (exponent all ones) rendered `x12 != 0xff`.
            // `sbfx` sign-extends its field, which no operator here spells.
            case "ubfx" where ops.count >= 4:
                guard let lsb = Self.immediateValue(ops[2]), let width = Self.immediateValue(ops[3]),
                      width >= 1, lsb + width <= 64
                else { return token }
                let mask = width == 64 ? UInt64.max : (UInt64(1) << width) - 1
                let field = lsb == 0 ? sourceName(ops[1], before: index, in: block) : "(\(sourceName(ops[1], before: index, in: block)) >>\u{1D41} \(lsb))"
                return "(\(field) & 0x\(String(mask, radix: 16)))"
            case "ubfx", "sbfx": return token
            case "mov" where ops.count >= 2:
                if ops[1].hasPrefix("#") { return Self.cleanImmediate(ops[1]) }
                // Follow a copy out of the ABI return register, so a boolean moved
                // aside before a clobbering call still resolves to its source send.
                if Self.canonicalRegister(ops[1]) == "x0" {
                    // When the producing call can't be expressed, keep the tested
                    // register: a bare `w0` would read as x0 *now* (a later
                    // call's result), not the earlier one this copy saved.
                    let source = resolve(ops[1], before: index, in: block, consumed: &consumed)
                    return source == ops[1] ? token : source
                }
                return sourceName(ops[1], before: index, in: block)
            default: return sourceName(token, before: before, in: block)
            }
        }
        return sourceName(token, before: before, in: block)
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
        if DisassembledFunction.isUniquenessCheck(callee) {
            return "isKnownUniquelyReferenced(\(rawArguments.first ?? "?"))"
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

    /// Whether a rendered value is a bound call result's name (`r0`): a call
    /// result tested by name, which a bit-0 test treats as the call itself.
    static func isResultBinding(_ value: String) -> Bool {
        value.range(of: #"^r[0-9]+$"#, options: .regularExpression) != nil
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
    /// Whether no instruction strictly between `definition` and `use` writes
    /// one of `registers` (keys, `x0`…`x30`): a call clobbers the
    /// caller-saved x0–x18 and x30, and an instruction without Capstone
    /// detail may write anything.
    private static func registers(
        _ registers: [String], surviveFrom definition: Int, to use: Int, in block: BasicBlock
    ) -> Bool {
        guard !registers.isEmpty, definition + 1 < use else { return true }
        let wanted = Set(registers)
        for index in definition + 1 ..< use {
            let instruction = block.instructions[index]
            if instruction.controlFlow == .call {
                if wanted.contains(where: { key in Int(key.dropFirst()).map { $0 <= 18 || $0 == 30 } ?? true }) { return false }
                continue
            }
            guard let detail = instruction.detail else { return false }
            if !detail.writtenRegisterKeys.isDisjoint(with: wanted) { return false }
        }
        return true
    }

    /// x2–x7 of an ObjC method named as the arguments they arrive as, where
    /// no path from entry can have written them before `index` in `block`.
    /// Named without that check, `add x2, x9, #1; cmp x2, #0` rendered
    /// `arg0 == 0`, and so did a test of x2 after any call.
    private func sourceName(_ token: String, before index: Int, in block: BasicBlock) -> String {
        guard objectiveCArguments,
              let register = Self.canonicalRegister(token),
              register.hasPrefix("x"),
              let number = Int(register.dropFirst()), (2...7).contains(number),
              let blockIndex = indexByAddress[block.startAddress],
              !argumentsWrittenBefore[blockIndex].contains(register),
              !block.instructions.prefix(index).contains(where: { Self.mayWriteArgument(register, $0) })
        else { return token }
        return "arg\(number - 2)"
    }

    private static let argumentRegisters = ["x2", "x3", "x4", "x5", "x6", "x7"]

    /// Whether an instruction may write `register`: a call clobbers every
    /// argument register, and one without detail may write anything.
    private static func mayWriteArgument(_ register: String, _ instruction: Instruction) -> Bool {
        if instruction.controlFlow == .call { return true }
        guard let detail = instruction.detail else { return true }
        return detail.writtenRegisterKeys.contains(register)
    }

    /// A forward may-analysis: the argument registers written on some path
    /// from the entry block to each block's start, to a fixpoint.
    private static func argumentsWrittenBefore(_ blocks: [BasicBlock], indexByAddress: [UInt64: Int]) -> [Set<String>] {
        let written = blocks.map { block in
            Set(argumentRegisters.filter { register in block.instructions.contains { mayWriteArgument(register, $0) } })
        }
        var before = blocks.map { _ in Set<String>() }
        var changed = true
        while changed {
            changed = false
            for (index, block) in blocks.enumerated() {
                let out = before[index].union(written[index])
                for successor in block.successors.compactMap({ indexByAddress[$0] }) where !out.isSubset(of: before[successor]) {
                    before[successor].formUnion(out)
                    changed = true
                }
            }
        }
        return before
    }

    /// `#0x1` → `1`, `#0xff` → `0xff` (keep masks hex), `#5` → `5`.
    /// `-operand`: a numeric literal flips its sign, anything else is wrapped.
    private static func negatedOperand(_ operand: String) -> String {
        let t = operand.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("-") { return String(t.dropFirst()) }
        if let first = t.first, first.isNumber { return "-" + t }
        if t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) { return "-" + t }
        return "-(\(t))"
    }

    /// An InstructionSemantics term over register names, as the tracer's
    /// expressions print (`(x0 & 0xff)`, `(x1 >>ᵁ 3)`, `~x2`). Nil where no
    /// operator here spells it: a sign extension that is not the register's
    /// own width, a division or a high multiply (whose signedness the
    /// operator does not show), an extend or a rotate on an operand, or a
    /// register this path does not name.
    static func render(_ term: SemanticTerm, _ detail: StructuredInsn, destinationBits: Int) -> String? {
        func constant(_ value: UInt64) -> String { value < 10 ? String(value) : "0x" + String(value, radix: 16) }
        func name(_ register: PhysReg) -> String? {
            switch register.kind {
            case .gpr: return (register.widthBits == 32 ? "w" : "x") + String(register.number)
            case .zero: return "0"
            default: return nil
            }
        }
        /// An operand's own width: its register's, or nil for an immediate.
        func width(_ term: SemanticTerm) -> Int? {
            switch term {
            case .operand(let index), .register(let index):
                return index < detail.operands.count ? detail.operands[index].operand.register?.widthBits : nil
            default: return nil
            }
        }
        /// A term's value when it is a constant: an immediate, the zero
        /// register, or constants combined.
        func immediate(_ term: SemanticTerm) -> UInt64? {
            switch term {
            case .constant(let value): return value
            case .operand(let index), .register(let index):
                guard index < detail.operands.count else { return nil }
                let info = detail.operands[index]
                if case .register(let register) = info.operand, register.kind == .zero { return 0 }
                if case .register = info.operand { return nil }
                return info.shiftedImmediate.map { UInt64(bitPattern: $0) }
            case .binary(let op, let lhs, let rhs):
                guard let left = immediate(lhs), let right = immediate(rhs) else { return nil }
                switch op {
                case .bitAnd: return left & right
                case .bitOr: return left | right
                case .bitXor: return left ^ right
                default: return nil
                }
            case .complement(let inner):
                return immediate(inner).map { ~$0 & (destinationBits == 64 ? .max : (UInt64(1) << UInt64(destinationBits)) - 1) }
            default: return nil
            }
        }
        switch term {
        case .constant(let value):
            return constant(value)
        case .register(let index):
            guard index < detail.operands.count, let register = detail.operands[index].operand.register else { return nil }
            return name(register)
        case .operand(let index):
            guard index < detail.operands.count else { return nil }
            let info = detail.operands[index]
            if let value = immediate(term) { return constant(value) }
            guard let register = info.operand.register, let base = name(register),
                  info.extender == AARCH64_EXT_INVALID else { return nil }
            switch info.shift.type {
            case AARCH64_SFT_INVALID: return base
            case AARCH64_SFT_LSL: return "(\(base) << \(info.shift.amount))"
            case AARCH64_SFT_LSR: return "(\(base) >>\u{1D41} \(info.shift.amount))"
            case AARCH64_SFT_ASR: return "(\(base) >>\u{02E2} \(info.shift.amount))"
            default: return nil
            }
        case .binary(let op, let lhs, let rhs):
            if let value = immediate(term) { return constant(value) }
            switch op {
            case .divide, .unsignedDivide, .multiplyHigh, .unsignedMultiplyHigh: return nil
            default: break
            }
            guard let left = render(lhs, detail, destinationBits: destinationBits) else { return nil }
            // A shift amount reads in decimal, as Capstone prints it.
            let shifts = op == .shiftLeft || op == .shiftRight || op == .arithmeticShiftRight
            let right: String
            if shifts, let amount = immediate(rhs) { right = String(amount) }
            else if let other = render(rhs, detail, destinationBits: destinationBits) { right = other }
            else { return nil }
            return "(\(left) \(op.symbol) \(right))"
        case .complement(let inner):
            return render(inner, detail, destinationBits: destinationBits).map { "~\($0)" }
        case .signExtend(let inner, let bits):
            // A W register read in a W result is already its signed word.
            guard bits == destinationBits, width(inner) == bits else { return nil }
            return render(inner, detail, destinationBits: destinationBits)
        case .zeroExtend(let inner, let bits):
            guard let text = render(inner, detail, destinationBits: destinationBits) else { return nil }
            if width(inner) == bits { return text }
            return "(\(text) & \(constant(bits >= 64 ? .max : (UInt64(1) << UInt64(bits)) - 1)))"
        }
    }

    /// An operand with the shift or extend Capstone prints after it: `x1,
    /// lsr #1` is `(x1 >>ᵁ 1)` and `#0x1, lsl #12` is `0x1000`. `trailing`
    /// is what follows the operand. Nil when it carries a modifier this
    /// spells no operator for (an extend, `ror`), so the caller declines.
    private static func applyingModifier(_ value: String, operand: String, trailing: ArraySlice<String>) -> String? {
        guard let modifier = trailing.first else { return value }
        let parts = modifier.split(separator: " ")
        guard trailing.count == 1, parts.count == 2, let amount = immediateValue(String(parts[1])), amount < 64
        else { return nil }
        if operand.hasPrefix("#") {
            guard parts[0] == "lsl", let base = immediateValue(operand), base <= UInt64.max >> amount else { return nil }
            let shifted = base << amount
            return shifted < 10 ? String(shifted) : "0x" + String(shifted, radix: 16)
        }
        switch parts[0] {
        case "lsl": return "(\(value) << \(amount))"
        case "lsr": return "(\(value) >>\u{1D41} \(amount))"
        case "asr": return "(\(value) >>\u{02E2} \(amount))"
        default: return nil
        }
    }

    /// `#5` or `#0x1f` as a number; nil for anything else.
    private static func immediateValue(_ token: String) -> UInt64? {
        guard token.hasPrefix("#") else { return nil }
        let digits = token.dropFirst()
        return digits.hasPrefix("0x") ? UInt64(digits.dropFirst(2), radix: 16) : UInt64(digits)
    }

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

    /// Mnemonics that write NZCV, for an instruction without Capstone detail.
    private static let flagSettingMnemonics: Set<String> = [
        "cmp", "cmn", "tst", "subs", "adds", "ands", "bics", "adcs", "sbcs", "ngcs", "negs",
        "ccmp", "ccmn", "fcmp", "fcmpe", "fccmp", "fccmpe", "setf8", "setf16", "rmif",
    ]

    private static func conditionOperator(_ mnemonic: String) -> String {
        switch mnemonic {
        case "b.eq": return "=="
        case "b.ne": return "!="
        // The carry conditions compare unsigned. `b.hs` after `sub; cmp`
        // is a range check, and read as a signed `>=` it is false for every
        // input below the range.
        case "b.lt": return "<"
        case "b.le": return "<="
        case "b.gt": return ">"
        case "b.ge": return ">="
        case "b.cc", "b.lo": return "<\u{1D41}"
        case "b.ls": return "<=\u{1D41}"
        case "b.hi": return ">\u{1D41}"
        case "b.cs", "b.hs": return ">=\u{1D41}"
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
    private static func bakedCondition(_ branch: Instruction?) -> String? {
        branch?.condition.map(unwrapOuterParentheses)
    }

    /// Updates belong to the proven back-edge, including explicit continues.
    /// Emitting only at a rotated body's end skipped them in nonrotated loops.
    private func loopBackStatements(header: Int, pad: String) -> [String] {
        let branch = blocks[header].instructions.last
        let named = Self.bakedCondition(branch) != nil || !Self.bakedLoopInitialization(branch).isEmpty
        let updates = named ? Self.bakedLoopUpdate(branch).map { "\(pad)\($0)" } : []
        return updates + ["\(pad)continue"]
    }

    /// The loop induction body updates (`total += i`, `i += 1`), in order, the
    /// enrichment baked on a loop header's branch — or an empty array.
    private static func bakedLoopUpdate(_ branch: Instruction?) -> [String] {
        branch?.loopUpdates ?? []
    }

    /// The induction variables' declarations (`var i = 0`) the enrichment
    /// baked on a loop header's branch, or an empty array.
    private static func bakedLoopInitialization(_ branch: Instruction?) -> [String] {
        branch?.loopInitializations ?? []
    }

    /// Strip a single balanced outer parenthesis pair, but only when the leading
    /// `(` matches the trailing `)` — so `(a >= b)` unwraps while `(a) + (b)` does
    /// not.
    private static func unwrapOuterParentheses(_ text: String) -> String {
        guard text.hasPrefix("("), text.hasSuffix(")") else { return text }
        var depth = 0
        var literal = LiteralScan()
        for (offset, character) in text.enumerated() {
            if literal.step(character) { continue }
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

    /// The negation of a rendered condition.
    ///
    /// An operator is rewritten in place only when the condition is a single
    /// comparison at parenthesis depth zero. Anything with a top-level `&&` or
    /// `||` is wrapped as `!(…)`: rewriting one operator text everywhere used
    /// to negate a single conjunct, so the range test `(0 <= x) && (x < 101)`
    /// inverted to `(0 > x) && (x < 101)` (measured on a typed-throws guard at
    /// -O), a condition that is never true where the real branch is.
    static func inverted(_ condition: String) -> String {
        // A declined condition stays declined: `!?` claims nothing more.
        if condition == "?" { return condition }
        // Unsigned forms first so ` <=ᵁ ` is never read as ` <= `.
        let comparisons: [(String, String)] = [
            (" <=\u{1D41} ", " >\u{1D41} "), (" >=\u{1D41} ", " <\u{1D41} "),
            (" <\u{1D41} ", " >=\u{1D41} "), (" >\u{1D41} ", " <=\u{1D41} "),
            (" != ", " == "), (" == ", " != "),
            (" <= ", " > "), (" >= ", " < "),
            (" < ", " >= "), (" > ", " <= "),
        ]
        var topLevel: [(range: Range<String.Index>, inverse: String)] = []
        var hasLogical = false
        var hasTopLevelSpace = false
        var depth = 0
        var genericDepth = 0
        var literal = LiteralScan()
        var previous: Character = " "
        var index = condition.startIndex
        while index < condition.endIndex {
            let character = condition[index]
            defer { previous = character }
            if !literal.step(character) {
                // A generic clause's `<` hugs a name (`Collection<A>`,
                // `Collection< where A.Element == B>`), where a comparison or a
                // shift is spaced; its `>` closes only an open clause, so a
                // top-level `>>` or an arrow's `>` never does.
                if character == "(" || character == "[" {
                    depth += 1
                } else if character == ")" || character == "]" {
                    depth -= 1
                } else if character == "<", previous.isLetter || previous.isNumber || previous == "_" {
                    genericDepth += 1
                } else if character == ">", genericDepth > 0, previous != " ", previous != "-" {
                    genericDepth -= 1
                } else if depth == 0, genericDepth == 0 {
                    if character == " " { hasTopLevelSpace = true }
                    let rest = condition[index...]
                    if rest.hasPrefix(" && ") || rest.hasPrefix(" || ") { hasLogical = true }
                    if let (op, inverse) = comparisons.first(where: { rest.hasPrefix($0.0) }) {
                        topLevel.append((index..<condition.index(index, offsetBy: op.count), inverse))
                    }
                }
            }
            index = condition.index(after: index)
        }
        if hasLogical || topLevel.count > 1 { return "!(\(condition))" }
        if let only = topLevel.first {
            return condition.replacingCharacters(in: only.range, with: only.inverse)
        }
        if condition.hasPrefix("!("), unwrapOuterParentheses(String(condition.dropFirst())) != String(condition.dropFirst()) {
            return String(condition.dropFirst(2).dropLast())
        }
        if condition.hasPrefix("!"), !condition.hasPrefix("!(") { return String(condition.dropFirst()) }
        // A bit test inverts by flipping set/clear, not by prefixing `!` — which
        // would read as the double negative `!bit 0 of w8 clear`.
        if condition.hasSuffix(" clear") { return String(condition.dropLast(6)) + " set" }
        if condition.hasSuffix(" set") { return String(condition.dropLast(4)) + " clear" }
        // `!` binds tighter than any infix operator, so an unparenthesized one
        // (`x & 1`) needs wrapping; a call, send, or bare name does not.
        return hasTopLevelSpace ? "!(\(condition))" : "!\(condition)"
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
            !$0.isTrap && DisassembledFunction.pseudoStatement(of: $0, hideRuntime: true) != nil
        }
        guard !hasStatements else { return false }
        return last.controlFlow == .return || Self.isTrap(last)
    }

    private static func isTrap(_ insn: Instruction) -> Bool {
        insn.isTrap
    }

    /// A pure trap sink: a block that only traps, with no recovered statements —
    /// the target of a Swift safety-check guard. A trap never continues, so this
    /// deliberately ignores successor edges (which are spurious on a trap block).
    private func isTrivialTrapTail(_ node: Int) -> Bool {
        guard let last = blocks[node].instructions.last, Self.isTrap(last) else { return false }
        return !blocks[node].instructions.contains {
            !$0.isTrap && DisassembledFunction.pseudoStatement(of: $0, hideRuntime: true) != nil
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
    /// - A throwing function's exit not classified by enrichment is neither a
    ///   return nor a throw here: `machine_return()`. Its error exit yields no
    ///   value (the error travels in x21), so `return ?` would assert a value on
    ///   a throw path, and a bare `return` would assert success.
    /// - A function that catches a callee's error (clears and tests x21) but
    ///   does not throw keeps the bare form. Its exits are returns; whether
    ///   one carries a value is not proven here.
    private var valuelessReturn: String {
        if isThrowing { return DisassembledFunction.unresolvedSwiftExitStatement }
        return returnsValue && !usesSwiftError ? "return ?" : "return"
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
        // The closest post-dominator has the largest set. On a DAG those sets
        // are nested, so it is unique. A cycle the entry's DFS never visits
        // (a loop inside a landing pad, which only the unwinder enters) stays
        // in the forward graph, and the nodes on it can tie. The tie went to
        // whichever the per-process hash seed iterated first, so the same
        // binary rendered differently run to run. Ties now go to the lowest
        // block index: address order.
        return (0..<count).map { node in
            pd[node].subtracting([node]).max(by: {
                (pd[$0].count, -$0) < (pd[$1].count, -$1)
            }) ?? exit
        }
    }
}

private func hex(_ value: UInt64) -> String { String(value, radix: 16) }
