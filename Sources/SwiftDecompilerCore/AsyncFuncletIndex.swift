import Foundation
import MachOKit
import Ccapstone

/// How a resume funclet is entered, which fixes what its registers mean.
public enum AsyncResumeKind: String, Sendable, Equatable {
    /// Entered when an awaited async callee returns. x22 holds the *callee's*
    /// context, whose first word is this function's own context; the callee's
    /// direct results arrive in x0… / v0… exactly as a synchronous call's would.
    case awaitReturn = "await-return"
    /// Entered by `swift_task_switch` after an executor hop. x22 is this
    /// function's own context again; no result register carries anything.
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
    /// one whose suspension this funclet continues. Nil for the entry.
    public let predecessor: UInt64?
    /// Every funclet of the chain, entry first, in ordinal order.
    public let chain: [UInt64]

    public var isEntry: Bool { ordinal == 0 && kind == nil }

    public init(
        parent: UInt64?, parentName: String?, ordinal: Int, kind: AsyncResumeKind?,
        predecessor: UInt64?, chain: [UInt64]
    ) {
        self.parent = parent
        self.parentName = parentName
        self.ordinal = ordinal
        self.kind = kind
        self.predecessor = predecessor
        self.chain = chain
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
            chain: funclet.parent.flatMap { chains[$0] } ?? []
        )
    }

    /// The suspension inside `predecessor` that `resume` continues, if any.
    func suspension(into resume: UInt64) -> (address: UInt64, suspension: Suspension)? {
        suspensions.first { $0.value.resume == resume }.map { ($0.key, $0.value) }
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
            var kinds: [UInt64: AsyncResumeKind] = [:]
            for address in hints.awaitReturns { kinds[address] = .awaitReturn }
            for address in hints.continuations {
                // Listed as both: contradictory, so claim neither.
                kinds[address] = kinds[address] == nil ? .continuation : .unknown
            }
            declaredKinds = kinds
            entries = Set(hints.entries).subtracting(kinds.keys).sorted()
            scanSet = (Set(hints.entries).union(kinds.keys)).sorted()
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
            for block in probe.basicBlocks() {
                var pages: [String: UInt64] = [:]
                var held: [String: UInt64] = [:]   // register key → materialised address
                var pending: [(register: String, address: UInt64, handedOver: Bool)] = []
                let terminator = block.instructions.last
                let terminatorIsBranch = terminator?.controlFlow == .branch
                let terminatorTarget = terminator?.branchTarget
                let terminatorName = terminatorTarget.flatMap(nameOf)
                    ?? terminator.flatMap { DisassembledFunction.calleeName(of: $0) }
                let hop = terminatorIsBranch && Self.isTaskSwitch(terminatorName)
                if hop { allocatesContext.insert(start) }

                for insn in block.instructions {
                    guard let detail = insn.detail else {
                        pages.removeAll(); held.removeAll(); continue
                    }
                    let name = insn.branchTarget.flatMap(nameOf)
                        ?? DisassembledFunction.calleeName(of: insn)
                    if insn.controlFlow == .call {
                        if Self.isTaskAlloc(name) || Self.isTaskSwitch(name) {
                            allocatesContext.insert(start)
                        }
                        for n in 0...17 { pages["x\(n)"] = nil; held["x\(n)"] = nil }
                        continue
                    }
                    let operands = detail.operands
                    switch detail.id {
                    case AARCH64_INS_ADRP:
                        if let reg = operands.first?.operand.register,
                           let page = operands.dropFirst().first?.operand.immediateValue {
                            pages[reg.key] = UInt64(bitPattern: page)
                            held[reg.key] = nil
                        }
                    case AARCH64_INS_ADR:
                        if let reg = operands.first?.operand.register,
                           let imm = operands.dropFirst().first?.operand.immediateValue {
                            let address = UInt64(bitPattern: imm)
                            held[reg.key] = address
                            if Self.isResumeCandidate(address, declaredKinds: declaredKinds,
                                                      functionStarts: functionStarts, hints: hints != nil,
                                                      owner: start) {
                                pending.append((reg.key, address, false))
                            }
                        }
                    case AARCH64_INS_ADD:
                        if operands.count == 3,
                           let dst = operands[0].operand.register,
                           let src = operands[1].operand.register,
                           let imm = operands[2].shiftedImmediate,
                           let page = pages[src.key] {
                            let address = page &+ UInt64(bitPattern: imm)
                            pages[dst.key] = nil
                            held[dst.key] = address
                            if Self.isResumeCandidate(address, declaredKinds: declaredKinds,
                                                      functionStarts: functionStarts, hints: hints != nil,
                                                      owner: start) {
                                pending.append((dst.key, address, false))
                            }
                        } else if let dst = operands.first?.operand.register {
                            pages[dst.key] = nil; held[dst.key] = nil
                        }
                    case AARCH64_INS_MOV, AARCH64_INS_ORR:
                        if let dst = operands.first?.operand.register,
                           let src = operands.last?.operand.register, operands.count == 2 {
                            held[dst.key] = held[src.key]
                            pages[dst.key] = nil
                        } else if let dst = operands.first?.operand.register {
                            pages[dst.key] = nil; held[dst.key] = nil
                        }
                    case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP:
                        // The stored registers are the first one (str) or two (stp).
                        let count = detail.id == AARCH64_INS_STP ? 2 : 1
                        for operand in operands.prefix(count) {
                            if let reg = operand.operand.register, let address = held[reg.key],
                               let slot = pending.firstIndex(where: { $0.address == address }) {
                                pending[slot].handedOver = true
                            }
                        }
                        if detail.writeback,
                           let mem = operands.first(where: { $0.operand.isMemory }),
                           case .memory(let base?, _, _) = mem.operand {
                            pages[base.key] = nil; held[base.key] = nil
                        }
                    default:
                        if let dst = operands.first?.operand.register {
                            pages[dst.key] = nil; held[dst.key] = nil
                        }
                        // Pair loads also write their second register.
                        if detail.id == AARCH64_INS_LDP, operands.count > 1,
                           let second = operands[1].operand.register {
                            pages[second.key] = nil; held[second.key] = nil
                        }
                    }
                }
                // Handing the pointer to swift_task_switch in x0 is the other way
                // a resume address leaves the function.
                if hop, let x0 = held["x0"],
                   let slot = pending.firstIndex(where: { $0.address == x0 }) {
                    pending[slot].handedOver = true
                }
                for item in pending {
                    found.append(Materialisation(
                        resume: item.address,
                        suspensionAddress: terminatorIsBranch ? terminator?.address : nil,
                        callee: hop ? nil : terminatorTarget,
                        isExecutorHop: hop,
                        handedOver: item.handedOver
                    ))
                }
            }
            if !found.isEmpty { materialisations[start] = found }
        }

        // Fallback (no hint sections): a function is an async funclet only with
        // the full evidence — a handed-over resume pointer and context
        // allocation or an executor hop in the same function.
        let resumeKind: (UInt64, Materialisation) -> AsyncResumeKind
        let edges: [UInt64: [Materialisation]]
        let roots: [UInt64]
        if hints != nil {
            edges = materialisations.filter { declaredKinds[$0.key] != nil || entries.contains($0.key) }
            roots = entries
            resumeKind = { resume, materialisation in
                guard let declared = declaredKinds[resume] else { return .unknown }
                // Cross-check the section against the tail that reaches it.
                switch declared {
                case .awaitReturn where materialisation.isExecutorHop: return .unknown
                case .continuation where !materialisation.isExecutorHop: return .unknown
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
                materialisation.isExecutorHop ? .continuation : .awaitReturn
            }
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
                    if let site = materialisation.suspensionAddress, index.suspensions[site] == nil {
                        index.suspensions[site] = Suspension(
                            resume: resume, callee: materialisation.callee,
                            calleeName: materialisation.callee.flatMap(nameOf),
                            isExecutorHop: materialisation.isExecutorHop
                        )
                    }
                    guard !claimed.contains(resume) else { continue }
                    claimed.insert(resume)
                    ordinal += 1
                    index.funclets[resume] = Funclet(
                        parent: entry, ordinal: ordinal,
                        kind: resumeKind(resume, materialisation), predecessor: current
                    )
                    chain.append(resume)
                    queue.append(resume)
                }
            }
            index.chains[entry] = chain
        }

        // Declared resume funclets nothing reached: grouped under no parent.
        index.orphans = declaredKinds.keys.filter { !claimed.contains($0) }.sorted()
        for orphan in index.orphans {
            index.funclets[orphan] = Funclet(
                parent: nil, ordinal: 0, kind: declaredKinds[orphan], predecessor: nil
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
