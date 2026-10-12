import Foundation
import MachOKit
import Ccapstone

/// How a resume funclet is entered, which fixes what its registers mean.
public enum AsyncResumeKind: String, Sendable, Equatable {
    /// Entered when an awaited async callee returns. x22 holds the *callee's*
    /// context, whose first word is this function's own context; the callee's
    /// direct results arrive in x0… / v0… exactly as a synchronous call's would.
    case awaitReturn = "await-return"
    /// Entered by `swift_task_switch` after an executor hop, or by a runtime
    /// wait that takes the resume function as an argument
    /// (`swift_taskGroup_wait_next_throwing`, `swift_asyncLet_get`, …). x22 is
    /// this function's own context again; no result register carries anything.
    case continuation
    /// The predecessor's suspension could not be classified (the binary has no
    /// `__swift_as_*` hint sections and the tail is not a recognised shape), or
    /// the hint section and the tail disagree. Grouped and named, but no
    /// register is seeded, so nothing about its state is claimed.
    case unknown
}

/// A function's place in an async function's funclet chain.
///
/// The compiler splits an async function at every suspension point into an
/// entry funclet plus one resume funclet per `await` or executor hop. The resume
/// funclets are local symbols, so a stripped binary keeps only their
/// `LC_FUNCTION_STARTS` entry. This records the recovered grouping: which entry a
/// funclet belongs to, its position in the chain, and how it is entered.
public struct AsyncFuncletInfo: Sendable, Equatable {
    /// Address of the entry funclet (the async function itself). Nil for a resume
    /// funclet the hint sections declare but no predecessor was found for.
    public let parent: UInt64?
    /// The entry funclet's display name, so a nameless resume funclet can be
    /// titled after the function it belongs to.
    public let parentName: String?
    /// 0 for the entry; resume funclets are numbered 1… in chain order.
    public let ordinal: Int
    /// Nil for the entry funclet.
    public let kind: AsyncResumeKind?
    /// The funclet that stores this one's address as a resume pointer, i.e. the
    /// one whose suspension this funclet continues. Nil for the entry, and for
    /// a resume funclet several suspensions of its chain continue into (a loop).
    public let predecessor: UInt64?
    /// Every funclet of the chain, entry first, in ordinal order.
    public let chain: [UInt64]
    /// The runtime wait that resumes this continuation, when it is not an
    /// executor hop.
    public let resumedBy: String?
    /// For a funclet with no parent: the entries of the several chains that
    /// resume into it (identical code folding shares one funclet between
    /// functions). Empty when no chain was found to reach it at all.
    public let sharedBy: [UInt64]

    public var isEntry: Bool { ordinal == 0 && kind == nil }

    public init(
        parent: UInt64?, parentName: String?, ordinal: Int, kind: AsyncResumeKind?,
        predecessor: UInt64?, chain: [UInt64], resumedBy: String? = nil, sharedBy: [UInt64] = []
    ) {
        self.parent = parent
        self.parentName = parentName
        self.ordinal = ordinal
        self.kind = kind
        self.predecessor = predecessor
        self.chain = chain
        self.resumedBy = resumedBy
        self.sharedBy = sharedBy
    }
}

/// Recovers every async funclet of an image and groups them into chains.
///
/// Two sources of evidence, cross-checked:
///
/// 1. The `__TEXT,__swift_as_entry`, `__swift_as_ret` and `__swift_as_cont`
///    sections: int32 relative pointers to, respectively, every async entry
///    funclet, every await-return resume funclet, and every executor-hop
///    continuation funclet. The compiler emits them for the runtime's backtracer,
///    and they survive stripping. They are the **oracle** for which functions are
///    funclets at all.
/// 2. The code itself: before suspending, a funclet materialises the address of
///    the funclet that will resume it (`adrp`+`add` or `adr`) and stores it into
///    the async context it is about to hand over (or passes it to
///    `swift_task_switch`). The funclet that materialises an address is that
///    funclet's predecessor; following those edges from an entry orders its chain.
///
/// Without the hint sections (older toolchains) the index falls back to the code
/// evidence alone, with a stricter test: the materialised address must be a
/// declared function start, it must be stored or handed to `swift_task_switch`,
/// and the function must also allocate an async context (`swift_task_alloc`) or
/// hop executors. A synchronous function that stores a plain function pointer
/// does neither, so it is not grouped.
///
/// Anything that fails these tests is declined: a declared resume funclet with no
/// predecessor is reported as an orphan, never attached to a guessed parent.
struct AsyncFuncletIndex: Sendable {
    /// A suspension point: the tail call or hop at `address` resumes in `resume`.
    struct Suspension: Sendable, Equatable {
        /// The resume funclet's address.
        let resume: UInt64
        /// Direct tail-call target when the suspension is a call to a known
        /// function (the awaited callee). Nil for an indirect call.
        let callee: UInt64?
        /// Display name of `callee`, when known.
        let calleeName: String?
        /// True when the suspension is a `swift_task_switch` executor hop rather
        /// than a call.
        let isExecutorHop: Bool
    }

    struct Funclet: Sendable, Equatable {
        let parent: UInt64?
        let ordinal: Int
        let kind: AsyncResumeKind?
        let predecessor: UInt64?
        var resumedBy: String? = nil
        var sharedBy: [UInt64] = []
    }

    /// Every funclet (entries included), keyed by address.
    private(set) var funclets: [UInt64: Funclet] = [:]
    /// Entry address → the chain in ordinal order (entry first).
    private(set) var chains: [UInt64: [UInt64]] = [:]
    /// Suspension instruction address → what it suspends into.
    private(set) var suspensions: [UInt64: Suspension] = [:]
    /// Declared resume funclets no predecessor was found for, sorted.
    private(set) var orphans: [UInt64] = []
    /// Whether the hint sections were present (the oracle), as opposed to the
    /// code-only fallback.
    let hintSectionsPresent: Bool

    var isEmpty: Bool { funclets.isEmpty }

    static let empty = AsyncFuncletIndex(hintSectionsPresent: false)

    private init(hintSectionsPresent: Bool) {
        self.hintSectionsPresent = hintSectionsPresent
    }

    func info(for address: UInt64, parentName: (UInt64) -> String?) -> AsyncFuncletInfo? {
        guard let funclet = funclets[address] else { return nil }
        return AsyncFuncletInfo(
            parent: funclet.parent,
            parentName: funclet.parent.flatMap(parentName),
            ordinal: funclet.ordinal,
            kind: funclet.kind,
            predecessor: funclet.predecessor,
            chain: funclet.parent.flatMap { chains[$0] } ?? [],
            resumedBy: funclet.resumedBy,
            sharedBy: funclet.sharedBy
        )
    }

    /// Memory instructions that never write memory. Any other one (a store,
    /// an atomic, an exclusive) may overwrite a saved resume field.
    static let readsMemoryOnly: Set<aarch64_insn> = [
        AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDP, AARCH64_INS_LDNP, AARCH64_INS_LDPSW,
        AARCH64_INS_LDRB, AARCH64_INS_LDRH, AARCH64_INS_LDRSB, AARCH64_INS_LDRSH, AARCH64_INS_LDRSW,
        AARCH64_INS_LDURB, AARCH64_INS_LDURH, AARCH64_INS_LDURSB, AARCH64_INS_LDURSH, AARCH64_INS_LDURSW,
        AARCH64_INS_LDAR, AARCH64_INS_LDARB, AARCH64_INS_LDARH,
        AARCH64_INS_LDAPR, AARCH64_INS_LDAPRB, AARCH64_INS_LDAPRH, AARCH64_INS_LDAPUR,
        AARCH64_INS_PRFM, AARCH64_INS_PRFUM,
    ]

    /// A context word: the allocating call site (or `ownContext`) plus a byte
    /// offset from that context's start.
    struct ContextAddress: Hashable {
        let identity: UInt64
        let offset: Int64
        func advanced(by bytes: Int64) -> ContextAddress {
            ContextAddress(identity: identity, offset: offset &+ bytes)
        }
    }

    /// The identity of a funclet's own incoming context (x22 at its entry).
    static let ownContext = UInt64.max

    /// A memory operand based on sp, or on x29, which the Apple arm64 ABI
    /// keeps as the frame pointer.
    static func addressesFrame(_ operand: StructuredOperand) -> Bool {
        guard case .memory(let base?, _, _) = operand else { return false }
        return base.kind == .stackPointer || base.key == "x29"
    }

    /// Runtime suspensions that take the resume function as an explicit
    /// argument and resume in the caller's own context, with the register that
    /// carries it (`include/swift/Runtime/Concurrency.h`; the
    /// `SWIFT_ASYNC_CONTEXT` parameter travels in x22, not in the count).
    static let runtimeWaitResumeRegister: [String: String] = [
        "swift_task_future_wait": "x2", "swift_task_future_wait_throwing": "x2",
        "swift_taskGroup_wait_next_throwing": "x2", "swift_taskGroup_waitAll": "x3",
        "swift_asyncLet_get": "x2", "swift_asyncLet_get_throwing": "x2",
        "swift_asyncLet_finish": "x2",
        "swift_asyncLet_consume": "x2", "swift_asyncLet_consume_throwing": "x2",
    ]

    static func runtimeWait(_ name: String?) -> String? {
        guard var name else { return nil }
        if name.hasPrefix("_swift_") { name.removeFirst() }
        return runtimeWaitResumeRegister[name] == nil ? nil : name
    }

    static func isContinuationInit(_ name: String?) -> Bool {
        name == "swift_continuation_init" || name == "_swift_continuation_init"
    }

    /// Pointer-authentication instructions that sign or strip one register in
    /// place, leaving the address it holds unchanged.
    static let signsInPlace: Set<aarch64_insn> = [
        AARCH64_INS_PACIA, AARCH64_INS_PACIB, AARCH64_INS_PACDA, AARCH64_INS_PACDB,
        AARCH64_INS_PACIZA, AARCH64_INS_PACIZB, AARCH64_INS_PACDZA, AARCH64_INS_PACDZB,
        AARCH64_INS_XPACI, AARCH64_INS_XPACD,
        // Operand-less aliases: x17 signed with x16, or x30 with sp or zero.
        AARCH64_INS_ALIAS_PACIA1716, AARCH64_INS_ALIAS_PACIB1716,
        AARCH64_INS_ALIAS_PACIASP, AARCH64_INS_ALIAS_PACIBSP,
        AARCH64_INS_ALIAS_PACIAZ, AARCH64_INS_ALIAS_PACIBZ, AARCH64_INS_ALIAS_XPACLRI,
    ]

    /// Basic blocks with each trap guard folded away. arm64e checks the
    /// return address before a tail call (`autibsp; eor x16, x30, x30, lsl #1;
    /// tbz x16, #62, ok; brk #0xc471; ok: b swift_task_switch`), which ends the
    /// block a path is in at a conditional branch. Where that block is a join
    /// (the hop after a diamond), a path can neither continue forward through
    /// the `tbz` nor start behind the join. A conditional branch that skips
    /// exactly one `brk` has one non-trapping path, so its state flows straight
    /// into the skipped-to block when nothing else enters that block; every
    /// authenticated-load check (`cmp x16, x17; b.eq ok; brk #0xc472`) has the
    /// same shape.
    static func trapGuardedRuns(_ blocks: [BasicBlock]) -> [BasicBlock] {
        var entries: [UInt64: Int] = [:]
        for block in blocks {
            for insn in block.instructions {
                if let target = insn.branchTarget { entries[target, default: 0] += 1 }
            }
        }
        var runs: [BasicBlock] = []
        var index = 0
        while index < blocks.count {
            var instructions = blocks[index].instructions
            var successors = blocks[index].successors
            while index + 2 < blocks.count,
                  instructions.last?.controlFlow == .conditionalBranch,
                  blocks[index + 1].instructions.count == 1,
                  blocks[index + 1].instructions[0].detail?.id == AARCH64_INS_BRK,
                  instructions.last?.branchTarget == blocks[index + 2].startAddress,
                  entries[blocks[index + 2].startAddress] == 1 {
                instructions += blocks[index + 2].instructions
                successors = blocks[index + 2].successors
                index += 2
            }
            runs.append(BasicBlock(startAddress: instructions[0].address,
                                   instructions: instructions, successors: successors))
            index += 1
        }
        return runs
    }

    /// `run`'s instructions, preceded by those of each run that is the only
    /// way into the path so far, and followed by those of each run it continues
    /// into unconditionally (an internal `b`, or a fall-through), up to the
    /// first run that forks, leaves the function or traps. One real execution
    /// path: a resume pointer built in one arm of a diamond (`cbz x20, L; adrp
    /// x16, r1; add; paciza x16; b J; L: adrp x16, r2; …; J: mov x0, x16; …;
    /// b swift_task_switch`) is seen reaching the join's tail branch, and an
    /// arm that stores into a context allocated before the fork
    /// (`AsyncThrowingDropWhileSequence.Iterator.next()`) sees the allocation.
    /// Runs come from `trapGuardedRuns`, so arm64e's pointer checks do not
    /// count against `limit`.
    static func straightLinePath(
        from run: BasicBlock, runAt: [UInt64: BasicBlock], predecessors: [UInt64: [UInt64]],
        limit: Int = 8
    ) -> [Instruction] {
        var path = run.instructions
        var visited: Set<UInt64> = [run.startAddress]
        var first = run
        while visited.count < limit, let into = predecessors[first.startAddress], into.count == 1,
              let previous = runAt[into[0]], previous.instructions.last?.isTrap != true,
              visited.insert(previous.startAddress).inserted {
            path = previous.instructions + path
            first = previous
        }
        var current = run
        while visited.count < 2 * limit, current.successors.count == 1,
              current.instructions.last?.isTrap != true,
              let next = runAt[current.successors[0]], visited.insert(next.startAddress).inserted {
            path += next.instructions
            current = next
        }
        return path
    }

    /// The suspension inside `predecessor` that `resume` continues, if any.
    func suspension(into resume: UInt64) -> (address: UInt64, suspension: Suspension)? {
        let matches = suspensions.filter { $0.value.resume == resume }
        guard matches.count == 1, let match = matches.first else { return nil }
        return (match.key, match.value)
    }

    // MARK: - Hint sections

    /// The three relative-pointer tables, resolved to addresses inside `__text`.
    /// Nil when the binary has none of them.
    struct HintSections: Sendable {
        var entries: [UInt64] = []
        var awaitReturns: [UInt64] = []
        var continuations: [UInt64] = []
    }

    static func hintSections(
        in machO: MachOFile, read: (UInt64, Int) -> Data?
    ) -> HintSections? {
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text"
        }) else { return nil }
        let textRange = UInt64(text.address) ..< UInt64(text.address + text.size)

        func table(_ name: String) -> [UInt64]? {
            guard let section = machO.sections.first(where: {
                $0.segmentName == "__TEXT" && $0.sectionName == name
            }) else { return nil }
            let base = UInt64(section.address)
            guard section.size > 0, let bytes = read(base, section.size) else { return [] }
            var targets: [UInt64] = []
            var offset = 0
            while offset + 4 <= bytes.count {
                let raw = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
                let delta = Int64(Int32(bitPattern: raw))
                let field = base &+ UInt64(offset)
                let target = UInt64(bitPattern: Int64(bitPattern: field) &+ delta)
                // A pointer outside __text is a malformed entry; drop it rather
                // than name a data address as code.
                if textRange.contains(target) { targets.append(target) }
                offset += 4
            }
            return targets
        }

        let entries = table("__swift_as_entry")
        let returns = table("__swift_as_ret")
        let continuations = table("__swift_as_cont")
        guard entries != nil || returns != nil || continuations != nil else { return nil }
        return HintSections(
            entries: entries ?? [], awaitReturns: returns ?? [], continuations: continuations ?? []
        )
    }

    // MARK: - Build

    /// - Parameters:
    ///   - hints: the hint sections, or nil for the code-only fallback.
    ///   - functionStarts: every declared function start (the boundary set).
    ///   - instructions: decodes one function's body, by start address.
    ///   - nameOf: display name of a function or stub at an address.
    static func build(
        hints: HintSections?,
        functionStarts: Set<UInt64>,
        instructions: (UInt64) -> [Instruction],
        nameOf: (UInt64) -> String?
    ) -> AsyncFuncletIndex {
        var index = AsyncFuncletIndex(hintSectionsPresent: hints != nil)

        // Candidate funclets and the declared kind of each resume funclet.
        let declaredKinds: [UInt64: AsyncResumeKind]
        let entries: [UInt64]
        let scanSet: [UInt64]
        if let hints {
            func valid(_ address: UInt64) -> Bool {
                address % 4 == 0 && functionStarts.contains(address)
            }
            let validEntries = hints.entries.filter(valid)
            var kinds: [UInt64: AsyncResumeKind] = [:]
            for address in hints.awaitReturns.filter(valid) { kinds[address] = .awaitReturn }
            for address in hints.continuations.filter(valid) {
                // Listed as both: contradictory, so claim neither.
                kinds[address] = kinds[address] == nil ? .continuation : .unknown
            }
            declaredKinds = kinds
            entries = Set(validEntries).subtracting(kinds.keys).sorted()
            scanSet = (Set(validEntries).union(kinds.keys)).sorted()
        } else {
            declaredKinds = [:]
            entries = []
            scanSet = functionStarts.sorted()
        }
        guard !scanSet.isEmpty else { return index }

        // Per funclet: the resume pointers it materialises, in instruction order,
        // each with the suspension that hands it over.
        struct Materialisation {
            let resume: UInt64
            let suspensionAddress: UInt64?
            let callee: UInt64?
            let isExecutorHop: Bool
            /// Evidence for the fallback mode: the pointer was stored, or passed
            /// to `swift_task_switch`.
            let handedOver: Bool
            /// False for a continuation handoff, whose suspension instruction
            /// is not on this path.
            var recordsSuspension = true
            /// The runtime wait the suspension tail-calls, if it is one.
            var runtimeWait: String? = nil
            /// Resumes in the caller's own context with no result register.
            var resumesOwnContext: Bool { isExecutorHop || runtimeWait != nil }
        }
        var materialisations: [UInt64: [Materialisation]] = [:]
        var allocatesContext: Set<UInt64> = []

        for start in scanSet {
            let body = instructions(start)
            guard !body.isEmpty else { continue }
            let probe = DisassembledFunction(
                symbol: "", demangledName: nil, startAddress: start,
                instructions: body, source: .address
            )
            var found: [Materialisation] = []
            let runs = Self.trapGuardedRuns(probe.basicBlocks())
            let internalAddresses = Set(body.map(\.address))
            let runAt = Dictionary(runs.map { ($0.startAddress, $0) }, uniquingKeysWith: { first, _ in first })
            var predecessors: [UInt64: [UInt64]] = [:]
            for run in runs {
                for successor in Set(run.successors) { predecessors[successor, default: []].append(run.startAddress) }
            }
            for run in runs {
                let path = Self.straightLinePath(from: run, runAt: runAt, predecessors: predecessors)
                var pages: [String: UInt64] = [:]
                var held: [String: UInt64] = [:]   // register key → materialised address
                // A context is the allocating call site (or this funclet's own
                // incoming x22) plus a byte offset, tracked only through
                // full-width copies and immediate adds along this path. A
                // context may live inside another's frame: `sleep(nanoseconds:)`
                // builds its continuation context at `x22 + 0x10`.
                var contexts: [String: ContextAddress] = [:]
                if path.first?.address == start {
                    contexts["x22"] = ContextAddress(identity: Self.ownContext, offset: 0)
                }
                // The resume pointer each known context word holds.
                var resumeFields: [ContextAddress: UInt64] = [:]
                var pending: [(register: String, address: UInt64, handedOver: Bool, continuationInit: Instruction?)] = []
                // An internal `b` is not a suspension: it continues the path.
                let terminator = path.last
                let terminatorIsBranch = terminator?.controlFlow == .branch
                    && terminator?.branchTarget.map(internalAddresses.contains) != true
                let terminatorTarget = terminator?.branchTarget
                let terminatorName = terminatorTarget.flatMap(nameOf)
                    ?? terminator.flatMap { DisassembledFunction.calleeName(of: $0) }
                let hop = terminatorIsBranch && Self.isTaskSwitch(terminatorName)
                let wait = terminatorIsBranch ? Self.runtimeWait(terminatorName) : nil
                if hop || wait != nil { allocatesContext.insert(start) }

                for insn in path {
                    guard let detail = insn.detail else {
                        pages.removeAll(); held.removeAll(); contexts.removeAll(); resumeFields.removeAll(); continue
                    }
                    let name = insn.branchTarget.flatMap(nameOf)
                        ?? DisassembledFunction.calleeName(of: insn)
                    if insn.controlFlow == .call {
                        if Self.isTaskAlloc(name) || Self.isTaskSwitch(name) || Self.isContinuationInit(name) {
                            allocatesContext.insert(start)
                        }
                        // `swift_continuation_init(context, flags)`: the resume
                        // pointer already in the context's ResumeParent is where
                        // the matching `swift_continuation_await` resumes.
                        if Self.isContinuationInit(name), let context = contexts["x0"],
                           let resume = resumeFields[context.advanced(by: 8)],
                           let slot = pending.firstIndex(where: { $0.address == resume }) {
                            pending[slot].handedOver = true
                            pending[slot].continuationInit = insn
                        }
                        for n in 0...17 {
                            pages["x\(n)"] = nil; held["x\(n)"] = nil; contexts["x\(n)"] = nil
                        }
                        resumeFields.removeAll()
                        if Self.isTaskAlloc(name) {
                            contexts["x0"] = ContextAddress(identity: insn.address, offset: 0)
                        }
                        continue
                    }
                    // arm64e signs the resume pointer (`pacia x16, x17`) and the
                    // context in place: the register still holds the same address.
                    if Self.signsInPlace.contains(detail.id) { continue }
                    let operands = detail.operands
                    // Snapshot the sources before killing the destination.
                    let copiedContext = operands.last?.operand.register.flatMap { contexts[$0.key] }
                    let addendContext = operands.dropFirst().first?.operand.register.flatMap { contexts[$0.key] }
                    if ![AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP].contains(detail.id),
                       let dst = operands.first?.operand.register { contexts[dst.key] = nil }
                    switch detail.id {
                    case AARCH64_INS_ADRP:
                        if let reg = operands.first?.operand.register, reg.kind == .gpr, reg.widthBits == 64,
                           let page = operands.dropFirst().first?.operand.immediateValue {
                            pages[reg.key] = UInt64(bitPattern: page)
                            held[reg.key] = nil
                        }
                    case AARCH64_INS_ADR:
                        if let reg = operands.first?.operand.register, reg.kind == .gpr, reg.widthBits == 64,
                           let imm = operands.dropFirst().first?.operand.immediateValue {
                            let address = UInt64(bitPattern: imm)
                            held[reg.key] = address
                            pages[reg.key] = nil
                            if Self.isResumeCandidate(address, declaredKinds: declaredKinds,
                                                      functionStarts: functionStarts, hints: hints != nil,
                                                      owner: start) {
                                pending.append((reg.key, address, false, nil))
                            }
                        }
                    case AARCH64_INS_ADD:
                        if operands.count == 3,
                           let dst = operands[0].operand.register,
                           let src = operands[1].operand.register,
                           dst.kind == .gpr, dst.widthBits == 64, src.kind == .gpr, src.widthBits == 64,
                           let imm = operands[2].shiftedImmediate,
                           let page = pages[src.key] {
                            let address = page &+ UInt64(bitPattern: imm)
                            pages[dst.key] = nil
                            held[dst.key] = address
                            if Self.isResumeCandidate(address, declaredKinds: declaredKinds,
                                                      functionStarts: functionStarts, hints: hints != nil,
                                                      owner: start) {
                                pending.append((dst.key, address, false, nil))
                            }
                        } else if let dst = operands.first?.operand.register {
                            pages[dst.key] = nil; held[dst.key] = nil
                            if operands.count == 3, dst.kind == .gpr, dst.widthBits == 64,
                               let addendContext, let imm = operands[2].shiftedImmediate {
                                contexts[dst.key] = addendContext.advanced(by: imm)
                            }
                        }
                    case AARCH64_INS_MOV, AARCH64_INS_ORR:
                        if let dst = operands.first?.operand.register,
                           let src = operands.last?.operand.register, operands.count == 2,
                           dst.kind == .gpr, dst.widthBits == 64, src.kind == .gpr, src.widthBits == 64 {
                            held[dst.key] = held[src.key]
                            pages[dst.key] = nil
                            contexts[dst.key] = copiedContext
                        } else if let dst = operands.first?.operand.register {
                            pages[dst.key] = nil; held[dst.key] = nil
                        }
                    case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP:
                        // Only the ResumeParent word of a context that reaches x22
                        // is a handoff. An arbitrary memory store proves nothing.
                        let count = detail.id == AARCH64_INS_STP ? 2 : 1
                        let memory = operands.first(where: { $0.operand.isMemory })?.operand
                        if let memory, Self.addressesFrame(memory) {
                            // The C stack holds no async context: one lives in
                            // the task allocator or inside another context.
                        } else if case .memory(let base?, nil, let displacement)? = memory, !detail.writeback,
                                  let context = contexts[base.key] {
                            // Two allocations, or an allocation and the context
                            // that predates it, never share memory.
                            for (offset, operand) in operands.prefix(count).enumerated() {
                                guard let reg = operand.operand.register else { continue }
                                let width = Int64(reg.widthBits / 8)
                                let field = context.advanced(by: displacement + Int64(offset) * width)
                                resumeFields = resumeFields.filter { known, _ in
                                    known.identity != field.identity
                                        || known.offset + 8 <= field.offset || field.offset + width <= known.offset
                                }
                                if reg.kind == .gpr, reg.widthBits == 64, let resume = held[reg.key] {
                                    resumeFields[field] = resume
                                }
                            }
                        } else {
                            // Unknown aliases may overwrite a saved resume field.
                            resumeFields.removeAll()
                        }
                        if detail.writeback,
                           let mem = operands.first(where: { $0.operand.isMemory }),
                           case .memory(let base?, _, _) = mem.operand {
                            pages[base.key] = nil; held[base.key] = nil; contexts[base.key] = nil
                        }
                    default:
                        // Any other memory write may overwrite a saved resume
                        // field, unless it is to the C stack.
                        if let memory = operands.first(where: { $0.operand.isMemory })?.operand,
                           !Self.readsMemoryOnly.contains(detail.id),
                           !Self.addressesFrame(memory) {
                            resumeFields.removeAll()
                        }
                        if let dst = operands.first?.operand.register {
                            pages[dst.key] = nil; held[dst.key] = nil
                        }
                        // Pair loads also write their second register.
                        if [AARCH64_INS_LDP, AARCH64_INS_LDNP, AARCH64_INS_LDPSW].contains(detail.id),
                           operands.count > 1, let second = operands[1].operand.register {
                            pages[second.key] = nil; held[second.key] = nil; contexts[second.key] = nil
                        }
                        // `ldr x9, [x8, #0x20]!` moves x8 off what it held.
                        if detail.writeback, let memory = operands.first(where: { $0.operand.isMemory }),
                           case .memory(let base?, _, _) = memory.operand {
                            pages[base.key] = nil; held[base.key] = nil; contexts[base.key] = nil
                        }
                    }
                }
                // Handing the pointer to swift_task_switch in x0 is the other way
                // a resume address leaves the function.
                if hop, let x0 = held["x0"],
                   let slot = pending.firstIndex(where: { $0.address == x0 }) {
                    pending[slot].handedOver = true
                }
                if let wait, let register = Self.runtimeWaitResumeRegister[wait],
                   let resume = held[register],
                   let slot = pending.firstIndex(where: { $0.address == resume }) {
                    pending[slot].handedOver = true
                }
                // The callee's context passes in x22. This funclet's own context
                // is not a callee's: its ResumeParent is this function's return.
                if let context = contexts["x22"], context != ContextAddress(identity: Self.ownContext, offset: 0),
                   let resume = resumeFields[context.advanced(by: 8)],
                   let slot = pending.firstIndex(where: { $0.address == resume }) {
                    pending[slot].handedOver = true
                }
                for item in pending {
                    if let initCall = item.continuationInit {
                        // Its await is a later `swift_continuation_await`, not
                        // this call: ownership only, no suspension record.
                        found.append(Materialisation(
                            resume: item.address, suspensionAddress: initCall.address,
                            callee: nil, isExecutorHop: false, handedOver: true, recordsSuspension: false
                        ))
                        continue
                    }
                    found.append(Materialisation(
                        resume: item.address,
                        suspensionAddress: terminatorIsBranch ? terminator?.address : nil,
                        callee: hop ? nil : terminatorTarget,
                        isExecutorHop: hop,
                        handedOver: item.handedOver,
                        runtimeWait: wait
                    ))
                }
            }
            // Paths overlap: a run's own path and a longer one through it both
            // see its tail. One entry per resume and site, in first-seen order.
            var merged: [Materialisation] = []
            for item in found {
                if let slot = merged.firstIndex(where: {
                    $0.resume == item.resume && $0.suspensionAddress == item.suspensionAddress
                }) {
                    if item.handedOver && !merged[slot].handedOver { merged[slot] = item }
                } else {
                    merged.append(item)
                }
            }
            if !merged.isEmpty { materialisations[start] = merged }
        }

        // Fallback (no hint sections): a function is an async funclet only with
        // the full evidence — a handed-over resume pointer and context
        // allocation or an executor hop in the same function.
        let resumeKind: (UInt64, Materialisation) -> AsyncResumeKind
        var edges: [UInt64: [Materialisation]]
        let roots: [UInt64]
        if hints != nil {
            edges = materialisations.filter { declaredKinds[$0.key] != nil || entries.contains($0.key) }
                .mapValues { $0.filter { $0.handedOver && $0.suspensionAddress != nil } }
            roots = entries
            resumeKind = { resume, materialisation in
                guard let declared = declaredKinds[resume] else { return .unknown }
                // Cross-check the section against the tail that reaches it.
                switch declared {
                case .awaitReturn where materialisation.resumesOwnContext: return .unknown
                case .continuation where !materialisation.resumesOwnContext: return .unknown
                default: return declared
                }
            }
        } else {
            edges = materialisations
                .filter { allocatesContext.contains($0.key) }
                .mapValues { $0.filter(\.handedOver) }
                .filter { !$0.value.isEmpty }
            let targets = Set(edges.values.flatMap { $0.map(\.resume) })
            roots = edges.keys.filter { !targets.contains($0) }.sorted()
            resumeKind = { _, materialisation in
                materialisation.resumesOwnContext ? .continuation : .awaitReturn
            }
        }

        // A declared resume address is not proof of a unique owner. A resume
        // funclet reached from two chains has no provable owner; first-wins
        // would invent both ownership and result ABI. Several sites in one
        // chain are a loop (libswift_Concurrency's
        // `AsyncCompactMapSequence.Iterator.next()` re-awaits into resume #1
        // from resume #4): the owner holds, but no single predecessor does.
        edges = edges.mapValues { items in items.filter { $0.suspensionAddress != nil } }
        // Paths that share a tail share its suspension instruction: two awaits
        // built in different blocks of `AsyncFlatMapSequence.Iterator.next()`'s
        // resume #1 both leave through one `braa`. That instruction resumes
        // into either funclet, so it is no one await and gets no record. An
        // executor hop or runtime wait has no result register, so either arm
        // is fine there.
        var siteTargets: [UInt64: Set<UInt64>] = [:]
        for item in edges.values.joined() {
            if let site = item.suspensionAddress { siteTargets[site, default: []].insert(item.resume) }
        }
        var owners: [UInt64: Set<UInt64>] = [:]
        for entry in roots {
            var seen: Set<UInt64> = [entry]
            var queue = [entry]
            while let current = queue.popLast() {
                for item in edges[current] ?? [] where seen.insert(item.resume).inserted {
                    owners[item.resume, default: []].insert(entry)
                    queue.append(item.resume)
                }
            }
        }
        edges = edges.mapValues { items in items.filter { (owners[$0.resume]?.count ?? 0) <= 1 } }
        var claims: [UInt64: Set<UInt64>] = [:]
        for item in edges.values.joined() {
            if let site = item.suspensionAddress { claims[item.resume, default: []].insert(site) }
        }

        // Walk each chain from its entry, numbering resume funclets in discovery
        // order (predecessor order, then instruction order within it).
        var claimed: Set<UInt64> = []
        for entry in roots {
            index.funclets[entry] = Funclet(parent: entry, ordinal: 0, kind: nil, predecessor: nil)
            claimed.insert(entry)
            var chain = [entry]
            var queue = [entry]
            var ordinal = 0
            while !queue.isEmpty {
                let current = queue.removeFirst()
                for materialisation in edges[current] ?? [] {
                    let resume = materialisation.resume
                    if let site = materialisation.suspensionAddress, index.suspensions[site] == nil,
                       materialisation.recordsSuspension,
                       materialisation.resumesOwnContext || siteTargets[site]?.count == 1 {
                        index.suspensions[site] = Suspension(
                            resume: resume, callee: materialisation.callee,
                            calleeName: materialisation.callee.flatMap(nameOf),
                            isExecutorHop: materialisation.isExecutorHop
                        )
                    }
                    guard !claimed.contains(resume) else { continue }
                    claimed.insert(resume)
                    ordinal += 1
                    let unique = claims[resume]?.count == 1
                    index.funclets[resume] = Funclet(
                        parent: entry, ordinal: ordinal,
                        kind: resumeKind(resume, materialisation),
                        predecessor: unique ? current : nil,
                        resumedBy: unique ? materialisation.runtimeWait : nil
                    )
                    chain.append(resume)
                    queue.append(resume)
                }
            }
            index.chains[entry] = chain
        }

        // Declared resume funclets nothing reached: grouped under no parent,
        // naming the chains that do reach a shared one.
        index.orphans = declaredKinds.keys.filter { !claimed.contains($0) }.sorted()
        for orphan in index.orphans {
            index.funclets[orphan] = Funclet(
                parent: nil, ordinal: 0, kind: declaredKinds[orphan], predecessor: nil,
                sharedBy: (owners[orphan]?.count ?? 0) > 1 ? owners[orphan, default: []].sorted() : []
            )
        }
        return index
    }

    private static func isResumeCandidate(
        _ address: UInt64, declaredKinds: [UInt64: AsyncResumeKind],
        functionStarts: Set<UInt64>, hints: Bool, owner: UInt64
    ) -> Bool {
        guard address != owner else { return false }
        return hints ? declaredKinds[address] != nil : functionStarts.contains(address)
    }

    static func isTaskSwitch(_ name: String?) -> Bool {
        guard let name else { return false }
        return name == "swift_task_switch" || name == "_swift_task_switch"
    }

    static func isTaskAlloc(_ name: String?) -> Bool {
        guard let name else { return false }
        return name == "swift_task_alloc" || name == "_swift_task_alloc"
    }
}
