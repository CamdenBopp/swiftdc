import Foundation
import MachOKit
import MachOSwiftSection
import Demangling
import Synchronization
import Ccapstone

/// A per-run memoization cache for `Disassembler.demangle`.
///
/// Demangling a symbol builds and prints a node tree; the same symbol recurs
/// many times in one run (a definition's own label, the names given to calls
/// that target it, xref edges — ~2.5x on the fixtures, more on frameworks).
/// The stored value is `String?`, so a symbol that demangles to nothing is
/// cached too and a "present but nil" entry is distinguished from an absent one.
/// A `Mutex` keeps it thread-safe so `Disassembler` stays `Sendable`; correct
/// caching relies on demangling being a pure function of (symbol, preset), which
/// is why `Disassembler.preset` is immutable per instance.
final class DemangleCache: Sendable {
    private let store = Mutex<[String: String?]>([:])
    private let kinds = Mutex(NominalTypeEvidence())
    private let presentations = Mutex<[String: String]>([:])

    func rememberPresentation(_ display: String, for semantic: String) {
        presentations.withLock { $0[semantic] = display }
    }
    func presentation(of semantic: String) -> String {
        presentations.withLock { $0[semantic] ?? semantic }
    }

    var nominalTypes: NominalTypeEvidence { kinds.withLock { $0 } }

    func rememberNominalTypes(from node: Node, options: DemangleOptions) {
        var evidence = NominalTypeEvidence()
        evidence.collect(from: node, options: options)
        kinds.withLock { $0.formUnion(evidence) }
    }

    /// The cached result for `key`, computing and storing it on a miss.
    func value(for key: String, compute: (String) -> String?) -> String? {
        if let hit = store.withLock({ $0[key] }) { return hit }
        let result = compute(key)
        store.withLock { $0[key] = result }
        return result
    }
}

/// A single decoded ARM64 instruction.
public struct Instruction: Sendable {
    /// Virtual address of the instruction.
    public let address: UInt64
    /// Raw textual form from the disassembler, e.g. `bl _$s6sample3runyyF`.
    public let text: String
    /// Human-readable annotation (e.g. a demangled call target), if any.
    public let annotation: String?
    /// Control-flow class (from Capstone), when available.
    public let controlFlow: ControlFlow?
    /// Resolved branch/call target (from Capstone), when statically known.
    public let branchTarget: UInt64?
    /// For call instructions: recovered argument values (x0…), rendered, when
    /// value-tracking could infer them.
    public let callArguments: [String]?
    /// For calls to a Swift function: the rendered `self` (x20), when known.
    /// Only set for Swift callees — x20 is `self` under the Swift calling
    /// convention, and merely a callee-saved register everywhere else.
    public let callSelf: String?
    /// The call's result is embedded in a later recovered expression, so flat
    /// pseudocode should not also emit it as a duplicate standalone call.
    public let resultConsumed: Bool
    /// Metadata type of a field read or written by this instruction, when the
    /// access was resolved exactly enough to name it. Objective-C encodings
    /// such as `B` let structured output distinguish booleans from integers.
    public let sourceType: String?
    /// Structured operands from Capstone's detail mode.
    ///
    /// Present on both front-ends: the objdump path already runs the full
    /// Capstone decoder and merges it by address (objdump supplies text,
    /// Capstone supplies semantics), so this is threaded through that same
    /// merge. Nil only where Capstone failed to decode an address objdump
    /// emitted — data in `__text`, or an encoding Capstone doesn't know.
    public let detail: StructuredInsn?
    /// Display-only callee spelling. Semantic consumers retain the full name
    /// in annotation, so hiding argument types cannot change the call ABI.
    public let calleeDisplayName: String?
    /// For a call or branch: the name of its target, fixed where the target
    /// is named (decode, the Capstone merge, the call-target and indirect
    /// target passes) and kept through every rebuild that only adds notes.
    /// A note appended to the annotation later cannot become the callee.
    /// Nil for anything else and for an unnamed target.
    public let callee: String?
    /// What enrichment proved about this instruction, boxed: nearly every
    /// instruction has none, and those pay one pointer for all of them.
    private let factBox: FactBox?

    /// What enrichment proved about this instruction beside its callee.
    /// Each fact is set where its note is appended, kept through every
    /// rebuild that only adds notes (`facts: insn.facts`), and the only
    /// thing renderers read: the annotation spells the same facts for
    /// display, and a note found by splitting it can be a piece of a
    /// rendered string literal. Empty for an instruction built by hand
    /// without any.
    public var facts: Facts { factBox?.facts ?? Facts() }
    /// `facts.exit`.
    public var exit: Exit? { factBox?.facts.exit }
    /// `facts.binding`.
    public var binding: Binding? { factBox?.facts.binding }
    /// `facts.thenThrows`.
    public var thenThrows: Bool { factBox?.facts.thenThrows ?? false }
    /// `facts.statement`.
    public var statement: Statement? { factBox?.facts.statement }
    /// `facts.awaitBinding`.
    public var awaitBinding: String? { factBox?.facts.awaitBinding }
    /// `facts.indirectJumpTarget`.
    public var indirectJumpTarget: String? { factBox?.facts.indirectJumpTarget }
    /// `facts.condition`.
    public var condition: String? { factBox?.facts.condition }
    /// `facts.loopUpdates`.
    public var loopUpdates: [String] { factBox?.facts.loopUpdates ?? [] }
    /// `facts.loopInitializations`.
    public var loopInitializations: [String] { factBox?.facts.loopInitializations ?? [] }
    /// `facts.loopEntryDeclarations`.
    public var loopEntryDeclarations: [String] { factBox?.facts.loopEntryDeclarations ?? [] }
    /// `facts.fieldRead`.
    public var fieldRead: String? { factBox?.facts.fieldRead }
    /// `facts.isSelfDispatch`.
    public var isSelfDispatch: Bool { factBox?.facts.isSelfDispatch ?? false }

    /// What enrichment proved about an instruction. Each fact names the
    /// note that spells it.
    public struct Facts: Sendable, Equatable {
        /// For an exit: what it does (`return …`, `throw …`,
        /// `swift-exit=…`). Nil for anything that is not an exit.
        public var exit: Exit?
        /// For a call whose result is named once rather than spelled at
        /// every use: the name and the call as it is spelled (`let r0 = …`).
        public var binding: Binding?
        /// A path throws right after this instruction: a throw merged into
        /// the shared epilogue, so the statement is followed by `throw ?`
        /// (`then throw ?`).
        public var thenThrows: Bool
        /// A statement this instruction performs that is not a call, an exit
        /// or a binding: an assignment to self's storage, `self = …`, a
        /// yield or an executor hop. The note is the statement.
        public var statement: Statement?
        /// For a suspension's tail call (`await=…`): the name its result is
        /// read under in the resume funclet, empty when that is not proven.
        /// Nil for a call that is not a suspension.
        public var awaitBinding: String?
        /// For a `br` through a register to no known function (`jump=…`):
        /// the rendered target, `?` when not proven.
        public var indirectJumpTarget: String?
        /// For a conditional branch whose comparison the tracer rebuilt with
        /// real operands: that comparison, rendered (`cond: …`).
        public var condition: String?
        /// For a loop header's branch: the proven induction updates, in the
        /// order the back edge runs them (`loop-update: a | b`).
        public var loopUpdates: [String]
        /// For a loop header's branch: the induction variables' declarations
        /// (`loop-init: a | b`).
        public var loopInitializations: [String]
        /// For the last instruction before a loop it enters: that loop's
        /// induction variables' declarations, for the flat views
        /// (`loop-entry: a | b`).
        public var loopEntryDeclarations: [String] = []
        /// For a read of a field of self: the field's path (`self.x`).
        public var fieldRead: String?
        /// For a call through self's own vtable slot (`dispatch=self`): an
        /// override in a subclass runs instead when self is one.
        public var isSelfDispatch: Bool
        /// For a call through a protocol witness table (`<requirement>
        /// witness for A`): the requirement's printed signature, which
        /// gives the call its parameters. The note is the callee's name.
        public var witnessRequirement: String?
        /// The site was a `bl` or `b` to an outlined fragment, and is now
        /// what the fragment does there (`inlined …`). The call graph reads
        /// the site as the call or branch to the fragment it is in the binary.
        public var inlinedFragment: InlinedFragment? = nil
        /// A call named for the value or protocol witness it calls through
        /// a table of a type the binary does not fix (`destroy value witness
        /// for A`): an operation, not an address. Its target may be any
        /// conforming type's witness, in this image or another, so the call
        /// graph counts it unresolved, not as an import.
        public var isWitnessDispatch: Bool = false
        /// The exact call target was resolved to an ARC entry point in its
        /// runtime image. A matching symbol spelling alone proves no contract.
        public var arcIdentityContract: Bool = false

        public init(
            exit: Exit? = nil,
            binding: Binding? = nil,
            thenThrows: Bool = false,
            statement: Statement? = nil,
            awaitBinding: String? = nil,
            indirectJumpTarget: String? = nil,
            condition: String? = nil,
            loopUpdates: [String] = [],
            loopInitializations: [String] = [],
            fieldRead: String? = nil,
            isSelfDispatch: Bool = false,
            witnessRequirement: String? = nil
        ) {
            self.witnessRequirement = witnessRequirement
            self.exit = exit
            self.binding = binding
            self.thenThrows = thenThrows
            self.statement = statement
            self.awaitBinding = awaitBinding
            self.indirectJumpTarget = indirectJumpTarget
            self.condition = condition
            self.loopUpdates = loopUpdates
            self.loopInitializations = loopInitializations
            self.fieldRead = fieldRead
            self.isSelfDispatch = isSelfDispatch
        }
    }

    /// Where an inlined site's instruction came from (`Facts.inlinedFragment`).
    public struct InlinedFragment: Sendable, Equatable {
        /// The fragment's start: the site's branch target in the binary.
        public let address: UInt64
        /// The site was a `bl`; otherwise a `b`.
        public let reachedByCall: Bool
    }

    /// `facts.inlinedFragment`.
    public var inlinedFragment: InlinedFragment? { factBox?.facts.inlinedFragment }

    private final class FactBox: Sendable {
        let facts: Facts
        init(_ facts: Facts) { self.facts = facts }
    }

    /// A statement an instruction performs that is not a call.
    public enum Statement: Sendable, Equatable {
        /// An assignment to self's storage: a store to a field (`self.x = v`,
        /// `self.x += v`, `self->_x = v`, `(self->_a, self->_b) = (…)`), a
        /// call to one of self's own setters, or an Objective-C property
        /// helper's ivar write. Spelled whole.
        case assignment(String)
        /// An Objective-C initializer's `self = …`: the call to super.
        case selfInitialization(String)
        /// A `_modify` accessor's yield of its storage (`&self.x`).
        case yield(String)
        /// An executor hop, naming the executor (`MainActor`, `generic`, `?`).
        case executorHop(String)

        /// The annotation note, and the statement.
        public var text: String {
            switch self {
            case .assignment(let assignment): assignment
            case .selfInitialization(let call): "self = \(call)"
            case .yield(let storage): "yield \(storage)"
            case .executorHop(let executor): "await hop_to_executor(\(executor))"
            }
        }
    }

    /// How a path ends. A `ret` that no rule classifies has no exit.
    public enum Exit: Sendable, Equatable {
        /// A return. The value is rendered, `?` when not proven; nil for a
        /// throwing function's exit proven normal with no value to print.
        case normal(String?)
        /// A throw of the rendered error, `?` when not proven.
        case `throw`(String)
        /// A throwing function's exit proven neither a return nor a throw.
        case unclassified
        /// A throwing function's exit that hands on a throwing call's
        /// outcome, its error in x21 or the rendered value of its result:
        /// `return try value`.
        case forwarded(String)

        /// The annotation note that carries this exit.
        public var note: String {
            switch self {
            case .normal(let value?): "return \(value)"
            case .normal(nil): DisassembledFunction.normalSwiftExitNote
            case .throw(let error): "throw \(error)"
            case .unclassified: DisassembledFunction.unresolvedSwiftExitNote
            case .forwarded(let value): "return try \(value)"
            }
        }

        /// The exit an instruction carries when it noted `noted`, in order:
        /// the first, unless a throwing function's verdict on the exit was
        /// noted, which renderers read ahead of any other note.
        static func carried(from noted: [Exit]) -> Exit? {
            noted.first { $0 == .unclassified } ?? noted.first { $0 == .normal(nil) } ?? noted.first
        }

        /// The source statement for this exit.
        public var statement: String {
            switch self {
            case .normal(let value?): "return \(value)"
            case .normal(nil): "return"
            case .throw(let error): "throw \(error)"
            case .unclassified: DisassembledFunction.unresolvedSwiftExitStatement
            case .forwarded(let value): "return try \(value)"
            }
        }
    }

    /// A call's result bound to a name.
    public struct Binding: Sendable, Equatable {
        /// The name every use reads (`r0`).
        public let name: String
        /// The call, spelled once.
        public let expression: String

        public init(name: String, expression: String) {
            self.name = name
            self.expression = expression
        }

        /// The annotation note, and the statement: `let r0 = …`.
        public var statement: String { "let \(name) = \(expression)" }
    }

    /// Where a new instruction's `callee` comes from.
    public enum CalleeFact: Sendable {
        /// Named from this instruction's text and annotation: where the
        /// target is named.
        case derived
        /// Carried from the instruction being rebuilt.
        case kept(String?)
    }

    public init(
        address: UInt64,
        text: String,
        annotation: String? = nil,
        controlFlow: ControlFlow? = nil,
        branchTarget: UInt64? = nil,
        callArguments: [String]? = nil,
        callSelf: String? = nil,
        resultConsumed: Bool = false,
        sourceType: String? = nil,
        detail: StructuredInsn? = nil,
        calleeDisplayName: String? = nil,
        callee: CalleeFact = .derived,
        facts: Facts = Facts()
    ) {
        self.address = address
        self.text = text
        self.annotation = annotation
        self.controlFlow = controlFlow
        self.branchTarget = branchTarget
        self.callArguments = callArguments
        self.callSelf = callSelf
        self.resultConsumed = resultConsumed
        self.sourceType = sourceType
        self.detail = detail
        self.calleeDisplayName = calleeDisplayName
        self.factBox = facts == Facts() ? nil : FactBox(facts)
        switch callee {
        case .kept(let name):
            self.callee = name
        case .derived:
            self.callee = controlFlow == .call || controlFlow == .branch
                ? DisassembledFunction.parsedCalleeName(text: text, annotation: annotation) : nil
        }
    }
}

/// How a function's name/boundary was recovered — useful context, especially
/// for stripped binaries.
public enum RecoverySource: String, Sendable {
    /// Named by a symbol-table label emitted by the disassembler.
    case symbol
    /// Named from Swift `__swift5_*` metadata (survives stripping).
    case metadata
    /// Named because its whole body is a helper IRGen emits with a fixed
    /// shape (`recognizedHelperNames`).
    case helperShape = "helper-shape"
    /// Named from an Objective-C class/category method record (survives
    /// stripping and carries selector, type encoding, and IMP).
    case objcMetadata = "objc-metadata"
    /// Boundary known (`BoundaryEvidence` says from what) but no name —
    /// synthesized `sub_<addr>`.
    case address
    /// Boundary known, but the symbol table lists two or more *distinct* symbols
    /// at this address. The release linker's identical-code-folding pass merged
    /// several unrelated declarations onto one instruction stream, and nothing in
    /// their mangled names records the merge — so no single symbol can be
    /// attributed. Rendered `sub_<addr>` with the candidates listed, never guessed.
    case foldedSymbols = "folded-symbols"
    /// Boundary known and no symbol, but the address is a
    /// resume funclet of an async function: it is stored as a resume pointer by
    /// that function's chain, so it is titled after its parent
    /// (`resume #N of <parent>`). See `AsyncFuncletIndex`.
    case asyncFunclet = "async-funclet"
}

/// What marks a nameless function's first address.
public enum BoundaryEvidence: Sendable {
    case functionStarts
    /// Nothing does: decoding began here, at the start of a code section or
    /// of a span. A stripped image with no LC_FUNCTION_STARTS can have one
    /// such function hold every body up to the next symbol.
    case decodeStart

    var note: String {
        switch self {
        case .functionStarts: "boundary from LC_FUNCTION_STARTS"
        case .decodeStart: "no recorded boundary: decoding began here"
        }
    }
}

/// A contiguous function body recovered from `__text`.
public struct DisassembledFunction: Sendable {
    /// Raw symbol/label (e.g. `_$s6sample3runyyF`) or a synthesized `sub_<addr>`.
    public let symbol: String
    /// Demangled, readable name, if recoverable.
    public let demangledName: String?
    /// Canonical identity/signature retained independently of display options.
    /// Nil for legacy/manual constructions; those use demangledName as before.
    public let semanticName: String?
    /// Virtual address of the first instruction.
    public let startAddress: UInt64
    public let instructions: [Instruction]
    /// Where the name/boundary came from.
    public let source: RecoverySource
    /// Objective-C owner/selector/signature when this entry point is an IMP.
    public let objcMethod: ObjCMethodBinding?
    /// When `source == .foldedSymbols`: the distinct symbol names (raw, sorted)
    /// the symbol table places at this address, listed instead of one being
    /// picked. Nil for every other source.
    public let foldedCandidates: [String]?
    /// This function's place in an async function's funclet chain, when it is
    /// an async entry or resume funclet. Nil for a synchronous function.
    public let asyncFunclet: AsyncFuncletInfo?
    /// Recovered jump tables: `br` address → the target of each case, in case
    /// order (`JumpTables`). Empty when none was proven.
    public let switchTargets: [UInt64: [UInt64]]
    /// What marks the start of a function no name marks.
    public let boundary: BoundaryEvidence
    /// The final analysis graph, when this function came through enrichment.
    /// It stores only topology; instruction payloads always come from `instructions`.
    private let retainedCFG: FunctionCFG?
    /// Its callers prove it returns one integer word in x0, though no
    /// signature says so (`CalleeRegisterSummary.callerProvenResults`). Set by
    /// analysis; every rebuild carries it.
    var callerProvenResult = false

    /// Legacy/manual functions safely recover their graph on demand without
    /// changing the public initializer or introducing mutable shared storage.
    var controlFlowGraph: FunctionCFG { retainedCFG ?? FunctionCFG(self) }

    public init(
        symbol: String,
        demangledName: String?,
        startAddress: UInt64,
        instructions: [Instruction],
        source: RecoverySource,
        objcMethod: ObjCMethodBinding? = nil,
        foldedCandidates: [String]? = nil,
        asyncFunclet: AsyncFuncletInfo? = nil,
        switchTargets: [UInt64: [UInt64]] = [:],
        semanticName: String? = nil,
        boundary: BoundaryEvidence = .functionStarts
    ) {
        self.init(
            symbol: symbol, demangledName: demangledName, startAddress: startAddress,
            instructions: instructions, source: source, objcMethod: objcMethod,
            foldedCandidates: foldedCandidates, asyncFunclet: asyncFunclet,
            switchTargets: switchTargets, semanticName: semanticName, boundary: boundary, retainedCFG: nil
        )
    }

    private init(
        symbol: String, demangledName: String?, startAddress: UInt64,
        instructions: [Instruction], source: RecoverySource,
        objcMethod: ObjCMethodBinding?, foldedCandidates: [String]?,
        asyncFunclet: AsyncFuncletInfo?, switchTargets: [UInt64: [UInt64]],
        semanticName: String?, boundary: BoundaryEvidence, retainedCFG: FunctionCFG?
    ) {
        self.boundary = boundary
        self.symbol = symbol
        self.demangledName = demangledName
        self.semanticName = semanticName
        self.startAddress = startAddress
        self.instructions = instructions
        self.source = source
        self.objcMethod = objcMethod
        self.foldedCandidates = foldedCandidates
        self.asyncFunclet = asyncFunclet
        self.switchTargets = switchTargets
        self.retainedCFG = retainedCFG
    }

    /// Replacing machine instructions invalidates the retained topology, even
    /// at the same count. Every other function field is carried over.
    func replacingInstructions(_ instructions: [Instruction]) -> DisassembledFunction {
        replacingInstructions(instructions, foldedCandidates: foldedCandidates)
    }

    func replacingInstructions(_ instructions: [Instruction], foldedCandidates: [String]?) -> DisassembledFunction {
        var result = DisassembledFunction(
            symbol: symbol, demangledName: demangledName, startAddress: startAddress,
            instructions: instructions, source: source, objcMethod: objcMethod,
            foldedCandidates: foldedCandidates, asyncFunclet: asyncFunclet,
            switchTargets: switchTargets, semanticName: semanticName, boundary: boundary
        )
        result.callerProvenResult = callerProvenResult
        return result
    }

    /// A payload-only rebuild: addresses, order, control flow, branch targets,
    /// trap classification and switch cases must remain unchanged. The graph
    /// owns no instruction copies, so its views read the new payloads.
    func replacingInstructionPayload(_ instructions: [Instruction]) -> DisassembledFunction {
        var result = DisassembledFunction(
            symbol: symbol, demangledName: demangledName, startAddress: startAddress,
            instructions: instructions, source: source, objcMethod: objcMethod,
            foldedCandidates: foldedCandidates, asyncFunclet: asyncFunclet,
            switchTargets: switchTargets, semanticName: semanticName, boundary: boundary, retainedCFG: retainedCFG
        )
        result.callerProvenResult = callerProvenResult
        retainedCFG?.observeUse(of: result, consumer: "instruction-payload-copy")
        return result
    }

    /// Attach a graph proven for this exact final instruction topology.
    func retainingCFG(_ cfg: FunctionCFG) -> DisassembledFunction {
        cfg.observeUse(of: self, consumer: "final-cfg-attachment")
        var result = DisassembledFunction(
            symbol: symbol, demangledName: demangledName, startAddress: startAddress,
            instructions: instructions, source: source, objcMethod: objcMethod,
            foldedCandidates: foldedCandidates, asyncFunclet: asyncFunclet,
            switchTargets: switchTargets, semanticName: semanticName, boundary: boundary, retainedCFG: cfg
        )
        result.callerProvenResult = callerProvenResult
        return result
    }

    /// The same function with its recovered jump tables attached.
    func attachingSwitchTargets(_ tables: [UInt64: [UInt64]]) -> DisassembledFunction {
        var result = DisassembledFunction(
            symbol: symbol, demangledName: demangledName, startAddress: startAddress,
            instructions: instructions, source: source, objcMethod: objcMethod,
            foldedCandidates: foldedCandidates, asyncFunclet: asyncFunclet,
            switchTargets: tables, semanticName: semanticName, boundary: boundary
        )
        result.callerProvenResult = callerProvenResult
        return result
    }

    /// The same function with the async-funclet grouping attached and, for a
    /// nameless resume funclet, titled after its parent. A symbol- or
    /// metadata-named funclet keeps its proven name; only the grouping is added.
    func attachingAsyncFunclet(_ info: AsyncFuncletInfo) -> DisassembledFunction {
        let title: String? = if source == .address, !info.isEntry, let parentName = info.parentName {
            "resume #\(info.ordinal) of \(parentName)"
        } else {
            nil
        }
        return DisassembledFunction(
            symbol: symbol,
            demangledName: title ?? demangledName,
            startAddress: startAddress, instructions: instructions,
            source: title == nil ? source : .asyncFunclet, objcMethod: objcMethod,
            foldedCandidates: foldedCandidates, asyncFunclet: info,
            switchTargets: switchTargets, semanticName: semanticName, boundary: boundary, retainedCFG: retainedCFG
        )
    }

    /// The comment line placing this function in its async funclet chain, for
    /// every renderer. Nil for a synchronous function.
    func asyncHeaderLine() -> String? {
        guard let info = asyncFunclet else { return nil }
        func hex(_ a: UInt64) -> String { "0x" + String(a, radix: 16) }
        if info.isEntry {
            let resumes = info.chain.dropFirst()
            if resumes.isEmpty { return "// async function: no suspension point" }
            let list = resumes.enumerated().map { "resume #\($0.offset + 1) @\(hex($0.element))" }
            return "// async function: \(resumes.count) resume funclet(s): \(list.joined(separator: ", "))"
        }
        guard let parent = info.parent else {
            let kind = info.kind.map { " (\($0.rawValue))" } ?? ""
            if !info.sharedBy.isEmpty {
                let owners = info.sharedBy.map { "@" + hex($0) }.joined(separator: ", ")
                return "// async resume funclet\(kind) shared by \(info.sharedBy.count) async functions "
                    + "(\(owners)); it has no single parent"
            }
            return "// async resume funclet\(kind); its parent async function was not recovered"
        }
        let entered: String
        if let predecessor = info.predecessor {
            let from = hex(predecessor)
            entered = switch info.kind {
            case .awaitReturn: "entered when the await in \(from) returns"
            case .continuation:
                info.resumedBy.map { "entered when \($0) in \(from) resumes it" }
                    ?? "entered after the executor hop in \(from)"
            case .unknown, nil: "entered from \(from); how is not recovered"
            }
        } else {
            // Several suspensions of this chain continue here (a loop).
            entered = switch info.kind {
            case .awaitReturn: "entered when one of several awaits returns"
            case .continuation: "entered after one of several executor hops"
            case .unknown, nil: "entered from several suspensions; how is not recovered"
            }
        }
        return "// resume #\(info.ordinal) of the async function @\(hex(parent)): \(entered)"
    }

    /// The name to show: demangled if available, else the raw symbol.
    public var displayName: String { demangledName ?? symbol }
    var analysisName: String? { semanticName ?? demangledName }
    /// What the mangled clauses of this function's symbol prove.
    var specializationClause: SpecializationClause {
        analysisName.map { Self.specializationClause(symbol: symbol, printedName: $0) } ?? .absent
    }
    /// The name this function's own registers follow, which is what numbers
    /// its parameters: a proven specialization's real signature, or the name.
    /// Every query that indexes a parameter reads this: seeded from the real
    /// list, `fl<Int8>(A.Type, Swift.Double, Swift.Int)`'s `arg1` is the Int,
    /// and its printed list calls that a Double.
    var layoutName: String? {
        if case .proven(let layout) = specializationClause { return layout.signature }
        return analysisName
    }
    var analysisDisplayName: String { analysisName ?? symbol }

    /// Render this function as annotated assembly text.
    /// The body of a function boundary with no instruction in its span: a
    /// table in `__text` that LC_FUNCTION_STARTS marks (AGXMetalG15G_B0's
    /// 2,596 bytes at 0x24ae4e7a4). Dropped, it read as no function at all;
    /// as an empty body, as a leaf with no calls.
    static let noDecodedInstructionNote =
        "// no instruction decodes here: the image marks a function, but its bytes are not code"

    public func render() -> String {
        var lines: [String] = []
        lines.append("\(displayName):")
        let tag: String = switch source {
        case .metadata: "  [recovered from Swift metadata]"
        case .helperShape: "  [recognized by its body: a helper IRGen emits]"
        case .objcMetadata: "  [recovered from Objective-C metadata]"
        case .asyncFunclet: "  [titled from its async parent; \(boundary.note)]"
        case .symbol, .address, .foldedSymbols: ""
        }
        if let objcMethod {
            lines.append("  // \(objcMethod.signature)  @ 0x\(String(startAddress, radix: 16))\(tag)")
            if source == .symbol { lines.append("  // \(symbol)") }
        } else if demangledName != nil {
            lines.append("  // \(symbol)  @ 0x\(String(startAddress, radix: 16))\(tag)")
        } else if source == .foldedSymbols, let foldedCandidates {
            lines.append("  // \(foldedCandidates.count) symbols folded onto 0x\(String(startAddress, radix: 16)) by identical code folding; none can be attributed")
            for candidate in foldedCandidates { lines.append("  //   \(candidate)") }
        } else if source == .address {
            lines.append("  // unnamed function  @ 0x\(String(startAddress, radix: 16))  [\(boundary.note)]")
        }
        if source != .foldedSymbols, foldedCandidates != nil {
            lines.append("  // a body this short can be shared after strip: references to 0x\(String(startAddress, radix: 16)) decline this name")
        }
        if let asyncLine = asyncHeaderLine() { lines.append("  \(asyncLine)") }
        if instructions.isEmpty { lines.append("  \(Self.noDecodedInstructionNote)") }
        for insn in instructions {
            let addr = String(insn.address, radix: 16)
            var line = "  \(addr):  \(insn.text)"
            var annotation = insn.annotation
            if let display = insn.calleeDisplayName, let semantic = Self.calleeName(of: insn),
               let range = annotation?.range(of: semantic) {
                annotation?.replaceSubrange(range, with: display)
            }
            if let annotation, !insn.text.contains(annotation) {
                line += "  ; \(annotation)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

/// Disassembles a Mach-O's `__text` to ARM64 using `llvm-objdump`, then
/// re-segments the flat instruction stream into functions using
/// `LC_FUNCTION_STARTS` (which survives stripping) and names them from the
/// symbol table or, failing that, Swift metadata.
public struct Disassembler: Sendable {
    // Immutable per instance: the demangle cache keys on the symbol alone, which
    // is only sound because the preset it demangles under cannot change under it.
    public let preset: DemanglePreset
    /// Memoizes `demangle` for the lifetime of this instance (one run).
    let demangleCache = DemangleCache()
    /// Memoizes what each callee name proves to the tracer, for one run.
    let callFactsCache = ValueTracer.CallFactsCache()
    /// Memoizes each image's code sections, for one run.
    let codeSectionCache = CodeSection.Cache()
    /// Memoizes each image's Go function table, for one run.
    let goFunctionCache = GoFunctionTable.Cache()
    /// Memoizes each image's LC_FUNCTION_STARTS as a set, for one run.
    let boundaryCache = BoundaryCache()

    public init(preset: DemanglePreset = .default) {
        self.preset = preset
    }

    public enum DisassembleError: Error, CustomStringConvertible {
        case toolFailed(String)
        /// The tool succeeded and produced output, but nothing in it parsed as an
        /// instruction — while the binary's own `LC_FUNCTION_STARTS` says it has
        /// functions. An empty result is only trustworthy when an independent
        /// source agrees the binary is empty; here one does not, so this is an
        /// analysis failure and must be reported as one rather than returned as
        /// "no functions".
        /// `toolReport` is llvm-objdump's own complaint about the input
        /// (`section data ends, _add lies outside valid range`), when it made
        /// one: then the input is damaged, and the parser is not at fault.
        case parsedNothing(lines: Int, knownStarts: Int, toolReport: String? = nil)
        /// The image's code is not arm64: the decoder would read its bytes as
        /// ARM64 anyway and fabricate instructions, so nothing decodes them.
        case unsupportedArchitecture(String)
        public var description: String {
            switch self {
            case .unsupportedArchitecture(let architecture):
                return """
                    \(architecture) code cannot be analyzed: swiftdc decodes arm64 only. `dump`, `interface`, \
                    `layout` and `objc` read this image's metadata, and plain `disasm` on a file prints \
                    llvm-objdump's text.
                    """
            case .toolFailed(let m): return "llvm-objdump failed: \(m)"
            case .parsedNothing(let lines, let starts, let report?):
                return """
                    llvm-objdump could not disassemble this image (\(lines) lines, no instruction), \
                    though LC_FUNCTION_STARTS lists \(starts) function(s), and it reported: \(report). \
                    The input looks damaged; `disasm --structured` and `--pseudo` decode it without llvm-objdump.
                    """
            case .parsedNothing(let lines, let starts, nil):
                return """
                    disassembly parse failed: llvm-objdump produced \(lines) lines but no \
                    instruction was recognised, while LC_FUNCTION_STARTS lists \(starts) \
                    function(s). This is a parser defect, not an empty binary.
                    """
            }
        }
    }

    /// Whether the decoder can read this image's code. Exactly arm64: x86_64
    /// bytes decoded as ARM64 printed `mem0[x2 + 0x4a] = ?` for `pushq %rbp`
    /// and exit 0, and arm64_32 decodes but has 32-bit pointers, which every
    /// analysis behind the decoder assumes are 64.
    public static func decodesCode(of machO: MachOFile) -> Bool {
        machO.header.cpu.type == .arm64
    }

    /// Fails on an image whose code cannot be decoded. Every command that
    /// reads code calls this: the non-throwing entry points decline to an
    /// empty result (`codeSections`), and a refusal must not read as one.
    public static func requireDecodableCode(_ machO: MachOFile) throws {
        guard decodesCode(of: machO) else {
            throw DisassembleError.unsupportedArchitecture(BinaryLoader.archName(machO))
        }
    }

    /// llvm-objdump's own text for a file, which decodes the slice's real
    /// architecture. Nothing here goes through the ARM64 decoder, so it
    /// carries no analysis.
    public func objdumpListing(path: String, architecture: String? = nil) throws -> String {
        var args = ["-d", "--macho", "--no-show-raw-insn"]
        if let architecture { args += ["--arch", architecture] }
        let result = try Shell.xcrun("llvm-objdump", args + [path])
        guard result.status == 0 else {
            throw DisassembleError.toolFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout
    }

    /// Disassemble the binary at `path`. For fat binaries pass `architecture`.
    /// `functionFilter`, if given, keeps only functions whose raw symbol or
    /// demangled name contains it (case-insensitive).
    public func disassemble(
        path: String,
        architecture: String? = nil,
        functionFilter: String? = nil
    ) async throws -> [DisassembledFunction] {
        let machO = try BinaryLoader.load(path: path, architecture: architecture)
        try Self.requireDecodableCode(machO)

        // Filtered: decode in-process with Capstone (only the matched functions'
        // ranges). `llvm-objdump` re-parses the whole binary on every invocation
        // and `--start/--stop-address` only bounds *decoding*, not parsing — so on
        // a large binary a filtered objdump run costs the same as a full one. The
        // in-process path reads just the matched bytes. Its instruction text is
        // Capstone's rather than objdump's, but the structure is identical.
        if let filter = functionFilter, !filter.isEmpty {
            return await disassemble(machO: machO, functionFilter: filter)
        }

        // Unfiltered: one full objdump pass (its text is the default file listing).
        // Every architecture extension, as Capstone decodes: with no CPU or
        // features a plain arm64 slice decodes as ARMv8.0, and the LSE and
        // RCpc atomics clang emits by default printed as `.long` data (17
        // instructions in GoodLinks) under Capstone's operands.
        var args = ["-d", "--macho", "--no-show-raw-insn", "--mattr=+all"]
        if let architecture {
            args += ["--arch", architecture]
        }
        // `-d --macho` always lists `__text`; a named section is appended
        // after it, so instructions are sorted back into address order below.
        for section in codeSections(in: machO) where section.name != "__text" {
            args.append("--section=\(section.segment),\(section.name)")
        }
        args.append(path)

        // Flat instruction stream + objdump's symbol labels, enriched with
        // Capstone's control-flow class + branch target (data objdump doesn't show).
        var (instructions, labelByAddress) = try objdumpInstructions(args, machO: machO)
        if instructions.isEmpty { return [] }
        attachCapstoneControlFlow(to: &instructions, in: machO)

        return await assemble(
            instructions: instructions,
            labelByAddress: labelByAddress,
            in: machO,
            functionFilter: nil,
            decodedWholeImage: true
        )
    }

    /// Disassemble a `MachOFile` fully in-process with Capstone — no
    /// `llvm-objdump` subprocess, so it works on images that have no standalone
    /// file on disk (dyld shared-cache frameworks). Boundaries come from
    /// `LC_FUNCTION_STARTS`, names from Swift metadata, and adrp/call operand
    /// targets are resolved against recovered function/descriptor addresses.
    public func disassemble(
        machO: MachOFile,
        functionFilter: String? = nil
    ) async -> [DisassembledFunction] {
        // Filtering needs ObjC names before decoding; carry the same index into
        // assembly so large class graphs are parsed once, not twice.
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        // Filtered: decode only the matched functions' ranges of __text.
        let instructions: [Instruction]
        // A matched range whose bytes are not code: shown, not "no match".
        var undecodedStarts: [UInt64] = []
        if let filter = functionFilter, !filter.isEmpty {
            let ranges = await matchedRanges(filter: filter, in: machO, objcIndex: objcIndex)
            guard !ranges.isEmpty else { return [] }
            let decodedRanges = ranges.map { capstoneInstructions(in: machO, span: $0) }
            undecodedStarts = zip(ranges, decodedRanges).filter { $0.1.isEmpty }.map(\.0.start)
            let matched = decodedRanges.flatMap { $0 }
            // The matched functions' direct callees are decoded too (one level),
            // because a caller's analysis consults each callee's body for whether
            // it returns through x8 (`PerFunctionContext.indirectResultUses`).
            // Without them a filtered run would see fewer facts than the whole-
            // binary run and render the same function differently.
            let callees = calleeRanges(of: matched, excluding: ranges, in: machO, objcIndex: objcIndex)
            instructions = (matched + callees.flatMap { capstoneInstructions(in: machO, span: $0) })
                .sorted { $0.address < $1.address }
        } else {
            instructions = capstoneInstructions(in: machO, span: nil)
        }
        let labels = symbolLabels(in: machO)
        let undecoded = undecodedStarts.map {
            makeFunction(start: $0, instructions: [], labelByAddress: labels, foldedByAddress: [:],
                         metadataNames: [:], objcIndex: objcIndex, in: machO)
        }
        guard !instructions.isEmpty else { return undecoded }
        let functions = await assemble(
            instructions: instructions,
            labelByAddress: labels,
            in: machO,
            functionFilter: functionFilter,
            objcIndex: objcIndex,
            decodedWholeImage: (functionFilter ?? "").isEmpty
        )
        guard !undecoded.isEmpty else { return functions }
        return (functions + undecoded).sorted { $0.startAddress < $1.startAddress }
    }

    /// Render every function of a cache image **streaming** — decode, analyse,
    /// render, and release one function at a time, never holding the whole
    /// image's instructions. This is the memory fix for the whole-image path:
    /// the array `disassemble(machO:)` holds all decoded instructions at once
    /// (the measured peak), whereas this bounds resident memory to roughly one
    /// function plus the cross-function name index.
    ///
    /// Output is identical to mapping `render` over `disassemble(machO:)` because
    /// it reuses the same building blocks: boundaries are instruction-aligned, so
    /// the spans between sorted boundaries are exactly the functions `segment`
    /// would cut, and each is named by the same `makeFunction` and analysed by
    /// the same `analyzeFunction`.
    ///
    /// Returns the rendered blocks in address order. Only for the unfiltered
    /// whole-image case; callers wanting the `[DisassembledFunction]` array (JSON,
    /// xrefs, analyze) keep using `disassemble(machO:)`.
    public func disassembleStreamingRender(
        machO: MachOFile, render: (DisassembledFunction) -> String,
        progress: ((_ done: Int, _ total: Int) -> Void)? = nil
    ) async -> [String] {
        await disassembleStreaming(machO: machO, transform: render, progress: progress)
    }

    /// Every function of the image, analysed one at a time and handed to
    /// `transform` before the next is decoded; what `transform` returns is all
    /// that stays resident. `disassembleStreamingRender` keeps the rendered
    /// text; the call graph keeps only call sites.
    public func disassembleStreaming<T>(
        machO: MachOFile, transform: (DisassembledFunction) -> T,
        progress: ((_ done: Int, _ total: Int) -> Void)? = nil
    ) async -> [T] {
        Probe.image(machO)
        warnOfUnreliableBoundaries(in: machO)
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        let labelByAddress = symbolLabels(in: machO)
        var foldedByAddress = foldedSymbolAddresses(in: machO)
        let sections = codeSections(in: machO)
        guard !sections.isEmpty else { return [] }

        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(labelByAddress.keys)
        boundarySet.formUnion(objcIndex.addresses)
        // `segment` starts the first function at the first decoded instruction
        // of each section, even when that address is not itself a boundary.
        boundarySet.formUnion(sections.map(\.range.lowerBound))
        let boundaries = boundarySet.filter { CodeSection.containing($0, in: sections) != nil }.sorted()
        guard !boundaries.isEmpty else { return [] }

        // Metadata names, on the same gate `assemble`/`matchedRanges` use.
        let unlabeled = Set(boundaries).subtracting(labelByAddress.keys)
        var metadataNames: [UInt64: String] = [:]
        if Double(unlabeled.count) > Double(max(boundaries.count, 1)) * 0.25 {
            let metadata = MetadataSymbolizer().functionNames(in: machO)
            metadataNames = metadata.unique
            Self.mergeMetadataFolds(metadata.folded, into: &foldedByAddress, labels: labelByAddress)
        }
        metadataNames.merge(recognizedHelperNames(in: machO, boundaries: boundaries, labels: labelByAddress)) { a, _ in a }
        let foldSuspects = self.foldSuspects(in: machO, labels: labelByAddress, metadataNames: metadataNames,
                                             folded: foldedByAddress, objcIndex: objcIndex)
        let referenceFolds = foldedByAddress.merging(foldSuspects) { a, _ in a }

        func span(_ index: Int) -> (start: UInt64, stop: UInt64) {
            let end = CodeSection.containing(boundaries[index], in: sections)!.range.upperBound
            return (boundaries[index], min(index + 1 < boundaries.count ? boundaries[index + 1] : end, end))
        }

        // Cross-function name index. `referenceIndex` and `swiftTargets` read only
        // name-level fields, so name-only stubs (no instructions) suffice.
        // Scoped: a function record per boundary (312 bytes each, 20 MB on
        // GoodLinks) is not held through pass 1, where the footprint peaks;
        // `swiftTargets` needs only which of them are Swift.
        let (indexedNames, swiftStubStarts): ([UInt64: String], [UInt64]) = {
            let stubs = boundaries.map {
                makeFunction(start: $0, instructions: [], labelByAddress: labelByAddress,
                             foldedByAddress: foldedByAddress,
                             metadataNames: metadataNames, objcIndex: objcIndex, in: machO)
            }
            let names = referenceIndex(
                functions: stubs, labelByAddress: labelByAddress,
                metadataNames: metadataNames, objcIndex: objcIndex,
                foldedByAddress: foldedByAddress, foldSuspects: foldSuspects, in: machO
            )
            return (names, stubs.filter {
                $0.objcMethod == nil && (Self.isSwiftMangled($0.symbol) || $0.source == .metadata)
            }.map(\.startAddress))
        }()
        let cacheSymbols = CacheSymbolResolver(machO: machO)
        var names = indexedNames
        // Pass 1: gather cross-image call targets, one function's instructions at
        // a time, then resolve once — reproduces `crossImageNames` without holding
        // the whole image.
        var targets = Set<UInt64>()
        var indirectResultUses: [UInt64: IndirectResultUse] = [:]
        var registerSummaries: [UInt64: CalleeRegisterSummary] = [:]
        var outlinedFragments: [UInt64: OutlinedFragment] = [:]
        let functionStarts = Set(boundaries)
        let isFunction = { (target: UInt64) in functionStarts.contains(target) }
        let arcReferences = arcFunctionReferences(in: machO)
        // Names and function membership are fixed for this summary pass.
        // Remember unknown arities too; sharing an address across images
        // must never share this image-local result.
        var summaryArities: [UInt64: Int?] = [:]
        let arity = { [names] target in
            if let cached = summaryArities[target] { return cached }
            let result = self.knownArity(ofCallTarget: target, names: names, cacheSymbols: cacheSymbols,
                                         arcFunctions: arcReferences, isFunction: isFunction)
            summaryArities[target] = .some(result)
            return result
        }
        let fileRanges = FileBackedRanges(standalone: machO)
        let importStubs = CodeSection.importStubRanges(of: machO)
        let isImportStub = { (target: UInt64) in importStubs.contains { $0.contains(target) } }
        let isStackProbe = stackProbeRecognizer(in: machO, importStubs: importStubs)
        var swiftTargets = Set(labelByAddress.compactMap { address, symbol in
            Self.isSwiftMangled(symbol) ? address : nil
        })
        swiftTargets.formUnion(metadataNames.keys)
        // A recognised IRGen helper is a C function: its x20 is no `self`.
        swiftTargets.subtract(metadataNames.filter { Self.helperShapeNames.contains($0.value) }.keys)
        swiftTargets.formUnion(swiftStubStarts)
        swiftTargets.formUnion(swiftStubAddresses(in: machO))
        swiftTargets.subtract(objcIndex.addresses)
        var hasEntryRoleConsumer = Self.needsEntryRegisterProofs(
            in: machO, names: names, folded: foldedByAddress, swiftTargets: swiftTargets)
        let section = textSection(in: machO)
        func decode(_ span: (start: UInt64, stop: UInt64)) -> [Instruction] {
            section?.instructions(span: span) ?? capstoneInstructions(in: machO, span: span)
        }
        for index in boundaries.indices {
            // Muted: pass 2 decodes the same span again and records its events.
            let instructions = Probe.muted { decode(span(index)) }
            hasEntryRoleConsumer = hasEntryRoleConsumer || Self.hasRawSwiftCall(in: instructions)
            collectUnnamedCallTargets(in: instructions, names: names, into: &targets)
            // The callee-side x8 fact every caller's analysis consults (see
            // `PerFunctionContext.indirectResultUses`); decoded here so pass 2
            // need not look ahead.
            if !instructions.isEmpty {
                let function = makeFunction(
                    start: boundaries[index], instructions: instructions,
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex, in: machO
                )
                indirectResultUses[boundaries[index]] = Self.indirectResultUse(of: function)
                // Without a dyld cache no later pass renames anything, so a
                // fragment no call may inline is not held through pass 1,
                // where this run's footprint peaks; with one, the names it
                // adds decide (`inlinableFragments`, after the resolve).
                if let fragment = OutlinedFragment(start: boundaries[index], instructions: function.instructions),
                   cacheSymbols != nil || Self.mayInline(fragment, named: names[boundaries[index]]) {
                    outlinedFragments[boundaries[index]] = fragment
                }
                registerSummaries[boundaries[index]] = CalleeRegisterSummary.of(
                    Self.withJumpTables(function, machO: machO, ranges: fileRanges),
                    calleeArity: arity, isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe)
            }
        }
        // Reads first: whether a callee uses the caller's x29 is part of
        // the effect the clobber closure carries.
        let memorySpanIndex = Dictionary(boundaries.indices.map { (boundaries[$0], $0) }, uniquingKeysWith: { a, _ in a })
        CalleeRegisterSummary.refineMemory(&registerSummaries) { start, effects in
            guard let index = memorySpanIndex[start] else { return nil }
            return Probe.muted {
                let function = makeFunction(start: start, instructions: decode(span(index)),
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex, in: machO)
                return CalleeRegisterSummary.of(Self.withJumpTables(function, machO: machO, ranges: fileRanges),
                    calleeEffects: effects, calleeArity: arity, isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe)
            }
        }
        CalleeRegisterSummary.closeOverReads(&registerSummaries)
        // Keep the arity closure's original name snapshot. The complete name
        // index is needed here only to decide whether positive entry-role
        // proofs have any possible consumer in this image.
        names = resolveCrossImageNames(targets, into: names, resolver: cacheSymbols)
        let rebuildingEntryRoles = hasEntryRoleConsumer || Self.needsEntryRegisterProofs(
            in: machO, names: names, folded: foldedByAddress, swiftTargets: swiftTargets)
        // Clobbers and reloads carried through calls; the few functions
        // whose callees change anything are decoded again.
        let spanIndex = Dictionary(boundaries.indices.map { (boundaries[$0], $0) }, uniquingKeysWith: { a, _ in a })
        CalleeRegisterSummary.closeOverCalls(&registerSummaries, rebuildingEntryRoles: rebuildingEntryRoles) { start, effects, readFacts, reusePreservation in
            guard let index = spanIndex[start] else { return nil }
            let instructions = Probe.muted { decode(span(index)) }
            guard !instructions.isEmpty else { return nil }
            let function = makeFunction(
                start: start, instructions: instructions,
                labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                metadataNames: metadataNames, objcIndex: objcIndex, in: machO
            )
            return Probe.muted {
                CalleeRegisterSummary.recomputingPreservation(
                    Self.withJumpTables(function, machO: machO, ranges: fileRanges),
                    retainingReadsFrom: readFacts, reusingPreservation: reusePreservation,
                    rebuildingEntryRoles: rebuildingEntryRoles, calleeEffects: effects, calleeArity: arity,
                    isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe)
            }
        }
        names = resolveCrossImageNames(targets, into: names, resolver: cacheSymbols)
        outlinedFragments = Self.inlinableFragments(outlinedFragments, names: names)
        if rebuildingEntryRoles { CalleeRegisterSummary.closeOverProvenEntryReads(&registerSummaries) }
        let resolver = ReferenceResolver(
            names: names,
            stringRanges: stringSectionRanges(in: machO),
            machO: machO,
            demangleSymbol: { self.demangle($0) },
            selectors: ObjCSelectors.selectorTable(in: machO),
            cfStringRange: sectionRange(named: "__cfstring", in: machO),
            cacheSymbols: cacheSymbols,
            cacheReader: machO.fullCache.map { CacheReader(full: $0) },
            arcFunctions: arcFunctionReferences(in: machO),
            fileRanges: fileRanges,
            foldedCandidates: referenceFolds,
            witnessTables: foldedByAddress.isEmpty ? [] : witnessTables(in: machO),
            protocolDescriptorSymbols: protocolDescriptorSymbols(in: machO),
            importedStubFunctions: importedStubFunctions(in: machO),
            specializationSymbols: ReferenceResolver.specializationSymbols(
                labels: labelByAddress, names: names, folded: referenceFolds)
        )
        CalleeRegisterSummary.closeOverFieldWrites(&registerSummaries, arcIdentityContract: { target, callee in
            resolver.arcIdentityContract(at: target, named: callee)
        }) { names[$0] }

        // Async funclet chains, from the hint sections plus a decode of just the
        // funclets' own spans, so the grouping costs no whole-image residency.
        let asyncIndex = asyncFuncletIndex(
            in: machO, boundaries: Set(boundaries),
            instructions: { self.decodeFunction(at: $0, boundaries: boundaries, in: machO, section: section) },
            nameOf: { names[$0] }
        )
        let enumCaseIndex = EnumCaseIndex.build(in: machO)
        let classTypeIndex = ClassTypeIndex.build(in: machO).adding(demangleCache.nominalTypes)
        // The chain pass decodes each chain's funclets once more, on demand, so
        // it still holds nothing beyond one chain at a time.
        let chainSlots = asyncChainSlots(
            index: asyncIndex,
            function: { address in
                let instructions = self.decodeFunction(at: address, boundaries: boundaries, in: machO, section: section)
                guard !instructions.isEmpty else { return nil }
                let function = makeFunction(
                    start: address, instructions: instructions,
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex, in: machO
                )
                return asyncIndex.info(for: address, parentName: { names[$0] })
                    .map(function.attachingAsyncFunclet) ?? function
            },
            enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex
        )
        let fieldMaps = (try? FieldMapBuilder.build(in: machO)) ?? [:]
        // Every closure is done: analysis reads only the facts.
        let finished = CalleeRegisterFacts.finish(&registerSummaries)
        let context = PerFunctionContext(
            resolver: resolver, swiftTargets: swiftTargets, objcIndex: objcIndex,
            fieldMaps: fieldMaps,
            selfIndex: SelfTypeIndex.build(in: machO),
            vtableIndex: VTableIndex.build(in: machO),
            enumCaseIndex: enumCaseIndex,
            payloadEnumIndex: PayloadEnumCaseIndex.build(in: machO),
            classTypeIndex: classTypeIndex,
            classParameterFields: ClassParameterFieldIndex.build(
                in: machO, fieldMaps: fieldMaps, classTypeIndex: classTypeIndex, demangle: demangle),
            indirectResultUses: indirectResultUses,
            registerSummaries: finished.facts,
            outlinedFragments: outlinedFragments,
            callerProvenResults: finished.callerProvenResults,
            asyncIndex: asyncIndex, asyncChainSlots: chainSlots
        )

        // Pass 2: decode each span, analyse, render, release. `segment` skips a
        // span that decodes to nothing, so this does too.
        var rendered: [T] = []
        rendered.reserveCapacity(boundaries.count)
        let total = boundaries.count
        if Self.analysesInParallel(machO: machO, resolver: context.resolver) {
            // Each function's analysis reads only the finished context, so
            // functions are analysed across the cores in bounded batches and
            // handed to `transform` in input order: the same results, in the
            // same order, as the loop below.
            _ = machO.cache // resolve MachOKit's lazy memo once, before any reader thread
            let frozenNames = names
            let work = ParallelPassTwo(section: section) { index, decoder in
                let span = span(index)
                let instructions = decoder?.instructions(span: span) ?? self.capstoneInstructions(in: machO, span: span)
                let function = self.makeFunction(
                    start: boundaries[index], instructions: instructions,
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex, in: machO
                )
                guard !instructions.isEmpty else { return function }
                let grouped = asyncIndex.info(for: function.startAddress, parentName: { frozenNames[$0] })
                    .map(function.attachingAsyncFunclet) ?? function
                return self.analyzeFunction(grouped, context: context)
            }
            var start = 0
            while start < total {
                let end = min(start + Self.parallelBatch, total)
                let functions = Parallel.mapChunks(start ..< end, chunk: Self.parallelChunk) { range in
                    work.analyze(range)
                }
                for function in functions { rendered.append(transform(function)) }
                if let progress { progress(end, total) }
                start = end
            }
            return rendered
        }
        for index in boundaries.indices {
            let instructions = decode(span(index))
            if instructions.isEmpty {
                // A marked start whose bytes are not code is shown as such,
                // not left out.
                rendered.append(transform(makeFunction(
                    start: boundaries[index], instructions: [],
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex, in: machO
                )))
            } else {
                let function = makeFunction(
                    start: boundaries[index], instructions: instructions,
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex, in: machO
                )
                let grouped = asyncIndex.info(for: function.startAddress, parentName: { names[$0] })
                    .map(function.attachingAsyncFunclet) ?? function
                rendered.append(transform(analyzeFunction(grouped, context: context)))
            }
            // Throttled so the callback overhead is negligible on a 100k-function
            // image; always report the final position so the display completes.
            if let progress, index % 256 == 0 || index == total - 1 {
                progress(index + 1, total)
            }
        }
        return rendered
    }

    /// Whether an address a call reaches is `___chkstk_darwin`: a GOT slot
    /// the loader binds to it, or an import stub whose `adrp; ldr; br`
    /// loads such a slot. For the preservation summary, which runs before
    /// any name is resolved. Results are cached; lookups only.
    func stackProbeRecognizer(in machO: MachOFile, importStubs: [Range<UInt64>]) -> (UInt64) -> Bool {
        let resolver = ReferenceResolver(names: [:], stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
        let cache = Mutex<[UInt64: Bool]>([:])
        return { address in
            if let known = cache.withLock({ $0[address] }) { return known }
            var result = resolver.loadedName(at: address) == "__chkstk_darwin"
            // An import stub lies outside the code sections the decoder
            // reads (`decodeText`), so its three instructions are decoded
            // from its own bytes: through the code sections a stub decoded
            // to nothing, and a probe called through one went unrecognised.
            if !result, importStubs.contains(where: { $0.contains(address) }),
               let bytes = self.sectionBytes(address: address, size: 12, in: machO), let engine = CapstoneEngine() {
                let stub = engine.disassemble(bytes, address: address).map(Self.instruction(decoded:))
                if stub.count == 3, let slot = CalleeRegisterSummary.stackProbeAddress(
                    of: Instruction(address: stub[2].address, text: stub[2].text, controlFlow: .call,
                                    branchTarget: nil, detail: stub[2].detail),
                    in: stub, index: [stub[2].address: 2]) {
                    result = resolver.loadedName(at: slot) == "__chkstk_darwin"
                }
            }
            cache.withLock { $0[address] = result }
            return result
        }
    }

    /// Functions per batch of pass 2: what is analysed and held at once
    /// before `transform` releases it.
    static let parallelBatch = 256
    /// Consecutive functions one thread analyses, with one decoder.
    static let parallelChunk = 8

    /// Whether pass 2 may analyse functions concurrently. Not while a probe
    /// records (its events must keep their order), not for a dyld-cache
    /// image (its resolver's cache reader keeps unlocked memo state), and
    /// not when `SWIFTDC_SERIAL` is set, which is the A/B switch and the
    /// determinism oracle for this path.
    static func analysesInParallel(machO: MachOFile, resolver: ReferenceResolver) -> Bool {
        !Probe.isActive && !machO.isLoadedFromDyldCache
            && resolver.cacheSymbols == nil && resolver.cacheReader == nil
            && ProcessInfo.processInfo.environment["SWIFTDC_SERIAL"] == nil
            && ProcessInfo.processInfo.activeProcessorCount > 1
    }

    /// Pass 2's per-function work handed to the worker threads. Unchecked
    /// because it captures the image and the context, which are only read
    /// once pass 1 ends: their caches are lock-guarded (`SelfMemberCache`,
    /// `CallResultBankCache`, `ChainedFixupTable`, `DemangleCache`), the one
    /// unguarded memo (`MachOFile.cache`) is resolved before the threads
    /// start, and each chunk decodes with an engine of its own.
    struct ParallelPassTwo: @unchecked Sendable {
        let section: TextSection?
        let body: (Int, TextSection?) -> DisassembledFunction

        init(section: TextSection?, body: @escaping (Int, TextSection?) -> DisassembledFunction) {
            self.section = section
            self.body = body
        }

        func analyze(_ range: Range<Int>) -> [DisassembledFunction] {
            let decoder = section?.withOwnEngine()
            return range.map { body($0, decoder) }
        }
    }

    /// Disassemble only the functions beginning at `addresses`, each decoded up
    /// to the next function boundary. Lets a caller classify a handful of
    /// Objective-C accessor IMPs without decoding the whole binary.
    ///
    /// `groupsAsyncFunclets: false` skips the async funclet grouping, which
    /// in an image without Swift's async hint sections decodes every function
    /// start; a caller that only reads these bodies (accessor classification)
    /// has no async function to group.
    ///
    /// `prefixBytes` decodes at most that much of each extent: in an image
    /// with no LC_FUNCTION_STARTS (Electron Framework, 140 MB of `__text`)
    /// the next boundary can be megabytes away, and `objc` decoding every
    /// accessor that far passed 6 GB.
    public func disassembleFunctions(
        at addresses: Set<UInt64>,
        in machO: MachOFile,
        prefixBytes: UInt64? = nil,
        groupsAsyncFunclets: Bool = true
    ) async -> [DisassembledFunction] {
        guard !addresses.isEmpty else { return [] }
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        let labels = symbolLabels(in: machO)
        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(objcIndex.addresses)
        boundarySet.formUnion(labels.keys)
        let boundaries = boundarySet.sorted()
        let sections = codeSections(in: machO)

        let instructions = addresses.sorted().flatMap { start -> [Instruction] in
            guard let end = CodeSection.containing(start, in: sections)?.range.upperBound else { return [] }
            var low = 0, high = boundaries.count
            while low < high {
                let mid = (low + high) / 2
                if boundaries[mid] <= start { low = mid + 1 } else { high = mid }
            }
            var stop = min(low < boundaries.count ? boundaries[low] : end, end)
            if let prefixBytes, stop - start > prefixBytes { stop = start + prefixBytes }
            guard stop > start else { return [] }
            return capstoneInstructions(in: machO, span: (start, stop))
        }
        guard !instructions.isEmpty else { return [] }
        return await assemble(
            instructions: instructions,
            labelByAddress: labels,
            in: machO,
            functionFilter: nil,
            objcIndex: objcIndex,
            groupsAsyncFunclets: groupsAsyncFunclets
        )
    }

    /// What `disassembleFunctions(at:in:prefixBytes:groupsAsyncFunclets: false)`
    /// returns, one function at a time: each analysed function is handed to
    /// `transform` and released before the next is decoded, and only what
    /// `transform` returns stays resident, keyed by the function's start.
    ///
    /// The array call decoded every span into one instruction list and held
    /// it, the segmented functions, a copy of each with its jump tables for
    /// the register summaries, and every analysed function at once: `objc`
    /// on a large app passed 4.5 GB classifying accessors. This keeps the
    /// same cross-function state (names, cross-image names, register
    /// summaries, indirect-result uses), built the same way, but decodes a
    /// span again for each pass instead of holding it: one for the names
    /// and call targets, one for the summaries (which read the resolved
    /// names), one to analyse.
    ///
    /// No async grouping: a caller that only reads these bodies (accessor
    /// classification) has no async function to group.
    func analyzeEachFunction<T>(
        at addresses: Set<UInt64>,
        in machO: MachOFile,
        prefixBytes: UInt64? = nil,
        transform: (DisassembledFunction) -> T?
    ) async -> [UInt64: T] {
        guard !addresses.isEmpty else { return [:] }
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        let labels = symbolLabels(in: machO)
        var spanBoundarySet = Set(functionStarts(of: machO))
        spanBoundarySet.formUnion(objcIndex.addresses)
        spanBoundarySet.formUnion(labels.keys)
        let spanBoundaries = spanBoundarySet.sorted()
        let sections = codeSections(in: machO)

        // Each requested address's decode span, as `disassembleFunctions`
        // cuts it. An empty span decodes nothing there either.
        let spans: [(start: UInt64, stop: UInt64)] = addresses.sorted().compactMap { start in
            guard let end = CodeSection.containing(start, in: sections)?.range.upperBound else { return nil }
            var low = 0, high = spanBoundaries.count
            while low < high {
                let mid = (low + high) / 2
                if spanBoundaries[mid] <= start { low = mid + 1 } else { high = mid }
            }
            var stop = min(low < spanBoundaries.count ? spanBoundaries[low] : end, end)
            if let prefixBytes, stop - start > prefixBytes { stop = start + prefixBytes }
            guard stop > start else { return nil }
            return (start, stop)
        }
        guard !spans.isEmpty else { return [:] }

        // From here on, what `assemble` builds, in its order.
        Probe.image(machO)
        var labelByAddress = labels
        goLabels(in: machO, adding: &labelByAddress)
        var boundaries = Set(functionStarts(of: machO))
        boundaries.formUnion(labelByAddress.keys)
        boundaries.formUnion(objcIndex.addresses)
        let unlabeled = boundaries.subtracting(labelByAddress.keys)
        var metadataNames: [UInt64: String] = [:]
        var metadataFolds: [UInt64: [String]] = [:]
        if Double(unlabeled.count) > Double(max(boundaries.count, 1)) * 0.25 {
            let metadata = MetadataSymbolizer().functionNames(in: machO)
            metadataNames = metadata.unique
            metadataFolds = metadata.folded
        }
        let sortedBoundaries = boundaries.sorted()
        metadataNames.merge(recognizedHelperNames(in: machO, boundaries: sortedBoundaries, labels: labelByAddress)) { a, _ in a }
        var foldedByAddress = foldedSymbolAddresses(in: machO)
        Self.mergeMetadataFolds(metadataFolds, into: &foldedByAddress, labels: labelByAddress)
        let foldSuspects = self.foldSuspects(in: machO, labels: labelByAddress, metadataNames: metadataNames,
                                             folded: foldedByAddress, objcIndex: objcIndex)
        let referenceFolds = foldedByAddress.merging(foldSuspects) { a, _ in a }

        // One Capstone engine for every span; each span's bytes are read on
        // their own, so no section is held.
        let engine = CapstoneEngine()
        func decode(_ span: (start: UInt64, stop: UInt64)) -> [Instruction] {
            guard let engine else { return [] }
            var decoded: [Instruction] = []
            for section in sections {
                let lo = max(span.start, section.range.lowerBound)
                let hi = min(span.stop, section.range.upperBound)
                guard hi > lo, let bytes = sectionBytes(address: lo, size: Int(hi - lo), in: machO) else { continue }
                decoded += engine.disassemble(bytes, address: lo).map(Self.instruction(decoded:))
            }
            return decoded
        }
        // The functions of one span, as `segment` cuts the whole list: a
        // span ends at the next span boundary, so no function crosses two.
        let goData = goFunctions(in: machO)?.dataSpans ?? [:]
        func functions(of span: (start: UInt64, stop: UInt64)) -> [DisassembledFunction] {
            segment(
                decode(span), boundaries: boundaries, labelByAddress: labelByAddress,
                foldedByAddress: foldedByAddress, metadataNames: metadataNames, objcIndex: objcIndex,
                in: machO,
                sortedBoundaries: sortedBoundaries,
                dataSpans: goData.filter { $0.key >= span.start && $0.key < span.stop })
        }

        // Pass 1: name-level stubs for the name index, and every call
        // target; the ones the index leaves unnamed are the cross-image
        // targets `crossImageNames` resolves.
        var stubs: [DisassembledFunction] = []
        var spanOfStart: [UInt64: Int] = [:]
        var callTargets = Set<UInt64>()
        let cacheSymbols = CacheSymbolResolver(machO: machO)
        Probe.muted {
            for (index, span) in spans.enumerated() {
                for function in functions(of: span) {
                    collectUnnamedCallTargets(in: function.instructions, names: [:], into: &callTargets)
                    stubs.append(function.replacingInstructions([]))
                    if spanOfStart[function.startAddress] == nil { spanOfStart[function.startAddress] = index }
                }
            }
        }
        let names = referenceIndex(
            functions: stubs, labelByAddress: labelByAddress,
            metadataNames: metadataNames, objcIndex: objcIndex,
            foldedByAddress: foldedByAddress, foldSuspects: foldSuspects, in: machO
        )
        let targets = callTargets.filter { names[$0] == nil }
        let resolvedNames = cacheSymbols != nil
            ? resolveCrossImageNames(targets, into: names, resolver: cacheSymbols)
            : names
        let resolver = ReferenceResolver(
            names: resolvedNames,
            stringRanges: stringSectionRanges(in: machO),
            machO: machO,
            demangleSymbol: { self.demangle($0) },
            selectors: ObjCSelectors.selectorTable(in: machO),
            cfStringRange: sectionRange(named: "__cfstring", in: machO),
            cacheSymbols: cacheSymbols,
            cacheReader: machO.fullCache.map { CacheReader(full: $0) },
            arcFunctions: arcFunctionReferences(in: machO),
            fileRanges: FileBackedRanges(standalone: machO),
            foldedCandidates: referenceFolds,
            witnessTables: foldedByAddress.isEmpty ? [] : witnessTables(in: machO),
            protocolDescriptorSymbols: protocolDescriptorSymbols(in: machO),
            importedStubFunctions: importedStubFunctions(in: machO),
            specializationSymbols: ReferenceResolver.specializationSymbols(
                labels: labelByAddress, names: resolvedNames, folded: referenceFolds)
        )
        var swiftTargets = Set(labelByAddress.compactMap { address, symbol in
            Self.isSwiftMangled(symbol) ? address : nil
        })
        swiftTargets.formUnion(metadataNames.keys)
        swiftTargets.subtract(metadataNames.filter { Self.helperShapeNames.contains($0.value) }.keys)
        swiftTargets.formUnion(stubs.filter {
            $0.objcMethod == nil && (Self.isSwiftMangled($0.symbol) || $0.source == .metadata)
        }.map(\.startAddress))
        swiftTargets.formUnion(swiftStubAddresses(in: machO))
        swiftTargets.subtract(objcIndex.addresses)
        stubs = []

        let asyncIndex = AsyncFuncletIndex.build(hints: nil, functionStarts: [], instructions: { _ in [] }, nameOf: { _ in nil })
        let fieldMaps = (try? FieldMapBuilder.build(in: machO)) ?? [:]
        let selfIndex = SelfTypeIndex.build(in: machO)
        let vtableIndex = VTableIndex.build(in: machO)
        let enumCaseIndex = EnumCaseIndex.build(in: machO)
        let payloadEnumIndex = PayloadEnumCaseIndex.build(in: machO)
        let classTypeIndex = ClassTypeIndex.build(in: machO).adding(demangleCache.nominalTypes)
        let chainSlots = asyncChainSlots(
            index: asyncIndex, function: { _ in nil },
            enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex
        )

        // Pass 2: the indirect-result uses and register summaries, as
        // `assemble` builds them, each body decoded again when it is read.
        let isFunction = { (target: UInt64) in boundaries.contains(target) }
        let importStubs = CodeSection.importStubRanges(of: machO)
        let isImportStub = { (target: UInt64) in importStubs.contains { $0.contains(target) } }
        let isStackProbe = stackProbeRecognizer(in: machO, importStubs: importStubs)
        var summaryArities: [UInt64: Int?] = [:]
        let arity = { target in
            if let cached = summaryArities[target] { return cached }
            let result = self.knownArity(
                ofCallTarget: target, names: resolver.names, cacheSymbols: cacheSymbols,
                arcFunctions: resolver.arcFunctions, isFunction: isFunction)
            summaryArities[target] = .some(result)
            return result
        }
        var indirectResultUses: [UInt64: IndirectResultUse] = [:]
        var summaries: [UInt64: CalleeRegisterSummary] = [:]
        var hasEntryRoleConsumer = Self.needsEntryRegisterProofs(
            in: machO, names: resolvedNames, folded: foldedByAddress, swiftTargets: swiftTargets)
        // The callees decoded below the requested functions, rebuilt from
        // their address when a closure reads them again.
        var calleeBodies = Set<UInt64>()
        // A callee decoded there replaces a requested function's body at the
        // same start, as it does in `assemble`'s `bodies`.
        func body(at start: UInt64) -> DisassembledFunction? {
            if !calleeBodies.contains(start), let index = spanOfStart[start] {
                return functions(of: spans[index]).first { $0.startAddress == start }
                    .map { Self.withJumpTables($0, machO: machO, ranges: resolver.fileRanges) }
            }
            guard calleeBodies.contains(start) else { return nil }
            return calleeBody(at: start, instructions: decodeFunction(at: start, boundaries: sortedBoundaries, in: machO))
        }
        func calleeBody(at start: UInt64, instructions: [Instruction]) -> DisassembledFunction? {
            guard !instructions.isEmpty else { return nil }
            return Self.withJumpTables(
                DisassembledFunction(
                    symbol: "sub_\(String(start, radix: 16))", demangledName: nil,
                    startAddress: start, instructions: instructions, source: .address),
                machO: machO, ranges: resolver.fileRanges)
        }
        // `assemble` keys both by function start, the first function at a
        // start winning.
        var firstAtStart: Set<UInt64> = []
        for span in spans {
            for function in Probe.muted({ functions(of: span) }) where firstAtStart.insert(function.startAddress).inserted {
                hasEntryRoleConsumer = hasEntryRoleConsumer || Self.hasRawSwiftCall(in: function.instructions)
                indirectResultUses[function.startAddress] = Self.indirectResultUse(of: function)
                if let summary = CalleeRegisterSummary.of(
                    Self.withJumpTables(function, machO: machO, ranges: resolver.fileRanges),
                    calleeArity: arity, isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe) {
                    summaries[function.startAddress] = summary
                }
            }
        }
        var level = Set(summaries.values.flatMap(\.callees)).filter {
            summaries[$0] == nil && boundaries.contains($0)
        }.sorted()
        var decodedCallees = 0
        while !level.isEmpty, decodedCallees < 512 {
            var next = Set<UInt64>()
            for target in level where decodedCallees < 512 && summaries[target] == nil {
                let instructions = Probe.muted {
                    self.decodeFunction(at: target, boundaries: sortedBoundaries, in: machO)
                }
                guard !instructions.isEmpty else { continue }
                hasEntryRoleConsumer = hasEntryRoleConsumer || Self.hasRawSwiftCall(in: instructions)
                decodedCallees += 1
                calleeBodies.insert(target)
                guard let callee = calleeBody(at: target, instructions: instructions), let summary = Probe.muted({
                    CalleeRegisterSummary.of(callee, calleeArity: arity, isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe)
                }) else { continue }
                summaries[target] = summary
                next.formUnion(summary.callees.filter { summaries[$0] == nil && boundaries.contains($0) })
            }
            level = next.sorted()
        }
        CalleeRegisterSummary.refineMemory(&summaries) { start, effects in
            body(at: start).flatMap { function in
                Probe.muted {
                    CalleeRegisterSummary.of(function, calleeEffects: effects, calleeArity: arity,
                        isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe)
                }
            }
        }
        CalleeRegisterSummary.closeOverReads(&summaries)
        let rebuildingEntryRoles = hasEntryRoleConsumer || Self.needsEntryRegisterProofs(
            in: machO, names: resolvedNames, folded: foldedByAddress, swiftTargets: swiftTargets)
        CalleeRegisterSummary.closeOverCalls(&summaries, rebuildingEntryRoles: rebuildingEntryRoles) { start, effects, readFacts, reusePreservation in
            body(at: start).flatMap { function in
                Probe.muted {
                    CalleeRegisterSummary.recomputingPreservation(
                        function, retainingReadsFrom: readFacts, reusingPreservation: reusePreservation,
                        rebuildingEntryRoles: rebuildingEntryRoles, calleeEffects: effects, calleeArity: arity, isFunction: isFunction,
                        isImportStub: isImportStub, isStackProbe: isStackProbe)
                }
            }
        }
        if rebuildingEntryRoles { CalleeRegisterSummary.closeOverProvenEntryReads(&summaries) }
        CalleeRegisterSummary.closeOverFieldWrites(&summaries, arcIdentityContract: { target, callee in
            resolver.arcIdentityContract(at: target, named: callee)
        }) { resolvedNames[$0] }

        // Every closure is done: analysis reads only the facts.
        let finished = CalleeRegisterFacts.finish(&summaries)
        let context = PerFunctionContext(
            resolver: resolver, swiftTargets: swiftTargets, objcIndex: objcIndex,
            fieldMaps: fieldMaps, selfIndex: selfIndex, vtableIndex: vtableIndex,
            enumCaseIndex: enumCaseIndex, payloadEnumIndex: payloadEnumIndex,
            classTypeIndex: classTypeIndex,
            classParameterFields: ClassParameterFieldIndex.build(
                in: machO, fieldMaps: fieldMaps, classTypeIndex: classTypeIndex, demangle: demangle),
            indirectResultUses: indirectResultUses,
            registerSummaries: finished.facts,
            callerProvenResults: finished.callerProvenResults,
            asyncIndex: asyncIndex, asyncChainSlots: chainSlots
        )

        // Pass 3: analyse each function, keep what `transform` returns.
        var result: [UInt64: T] = [:]
        var seen: Set<UInt64> = []
        for span in spans {
            for function in functions(of: span) where seen.insert(function.startAddress).inserted {
                if let value = transform(analyzeFunction(function, context: context)) {
                    result[function.startAddress] = value
                }
            }
        }
        return result
    }

    // MARK: - Shared pipeline

    /// Segment the flat instruction stream into functions, name them, resolve
    /// operand references, and recover call arguments. Both front-ends — objdump
    /// (files) and Capstone (in-process/cache) — feed into this.
    private func assemble(
        instructions: [Instruction],
        labelByAddress objdumpLabels: [UInt64: String],
        in machO: MachOFile,
        functionFilter: String?,
        objcIndex providedObjCIndex: ObjCMetadataIndex? = nil,
        groupsAsyncFunclets: Bool = true,
        decodedWholeImage: Bool = false
    ) async -> [DisassembledFunction] {
        Probe.image(machO)
        warnOfUnreliableBoundaries(in: machO)
        var labelByAddress = objdumpLabels
        goLabels(in: machO, adding: &labelByAddress)
        // Function boundaries: LC_FUNCTION_STARTS ∪ label addresses. Function-
        // starts survive stripping, so this re-creates boundaries a label set
        // (objdump's, or a stripped cache image's exports) couldn't cover.
        let objcIndex = providedObjCIndex ?? ObjCMetadataIndex.build(in: machO)
        var boundaries = Set(functionStarts(of: machO))
        boundaries.formUnion(labelByAddress.keys)
        // An Objective-C IMP is itself a function start. This also recovers
        // methods omitted from LC_FUNCTION_STARTS, and provides names when the
        // nlist symbol was stripped.
        boundaries.formUnion(objcIndex.addresses)

        // Names from Swift metadata (class vtables + protocol witnesses) — worth
        // computing when many boundaries lack a symbol label (stripped binaries,
        // or an in-process decode with few/no symbols).
        let unlabeled = boundaries.subtracting(labelByAddress.keys)
        var metadataNames: [UInt64: String] = [:]
        var metadataFolds: [UInt64: [String]] = [:]
        if Double(unlabeled.count) > Double(max(boundaries.count, 1)) * 0.25 {
            let metadata = MetadataSymbolizer().functionNames(in: machO)
            metadataNames = metadata.unique
            metadataFolds = metadata.folded
        }
        metadataNames.merge(recognizedHelperNames(in: machO, boundaries: boundaries.sorted(), labels: labelByAddress)) { a, _ in a }

        // Addresses the linker folded multiple distinct symbols onto (see
        // `foldedSymbolAddresses`): computed from the symbol table, so it is the
        // same on both front-ends regardless of what labels either produced.
        var foldedByAddress = foldedSymbolAddresses(in: machO)
        Self.mergeMetadataFolds(metadataFolds, into: &foldedByAddress, labels: labelByAddress)
        let foldSuspects = self.foldSuspects(in: machO, labels: labelByAddress, metadataNames: metadataNames,
                                             folded: foldedByAddress, objcIndex: objcIndex)
        let referenceFolds = foldedByAddress.merging(foldSuspects) { a, _ in a }

        var functions = segment(
            instructions,
            boundaries: boundaries,
            labelByAddress: labelByAddress,
            foldedByAddress: foldedByAddress,
            metadataNames: metadataNames,
            objcIndex: objcIndex,
            in: machO,
            emitsUndecodedSpans: decodedWholeImage,
            dataSpans: goFunctions(in: machO)?.dataSpans ?? [:]
        )

        // Resolve adrp/add(+ldr) operand references to function, type-descriptor,
        // string, and Swift-symbol names, and name direct call/branch targets.
        let cacheSymbols = CacheSymbolResolver(machO: machO)
        let resolvedNames = crossImageNames(
            for: functions,
            names: referenceIndex(
                functions: functions, labelByAddress: labelByAddress,
                metadataNames: metadataNames, objcIndex: objcIndex,
                foldedByAddress: foldedByAddress, foldSuspects: foldSuspects, in: machO
            ),
            resolver: cacheSymbols
        )
        let resolver = ReferenceResolver(
            names: resolvedNames,
            stringRanges: stringSectionRanges(in: machO),
            machO: machO,
            demangleSymbol: { self.demangle($0) },
            selectors: ObjCSelectors.selectorTable(in: machO),
            cfStringRange: sectionRange(named: "__cfstring", in: machO),
            cacheSymbols: cacheSymbols,
            cacheReader: machO.fullCache.map { CacheReader(full: $0) },
            arcFunctions: arcFunctionReferences(in: machO),
            fileRanges: FileBackedRanges(standalone: machO),
            foldedCandidates: referenceFolds,
            witnessTables: foldedByAddress.isEmpty ? [] : witnessTables(in: machO),
            protocolDescriptorSymbols: protocolDescriptorSymbols(in: machO),
            importedStubFunctions: importedStubFunctions(in: machO),
            specializationSymbols: ReferenceResolver.specializationSymbols(
                labels: labelByAddress, names: resolvedNames, folded: referenceFolds)
        )
        // Addresses whose callee uses the Swift calling convention, so `self` in
        // x20 is meaningful there.
        var swiftTargets = Set(labelByAddress.compactMap { address, symbol in
            Self.isSwiftMangled(symbol) ? address : nil
        })
        swiftTargets.formUnion(metadataNames.keys)
        // A recognised IRGen helper is a C function: its x20 is no `self`.
        swiftTargets.subtract(metadataNames.filter { Self.helperShapeNames.contains($0.value) }.keys)
        swiftTargets.formUnion(functions.filter {
            $0.objcMethod == nil && (Self.isSwiftMangled($0.symbol) || $0.source == .metadata)
        }.map(\.startAddress))
        // A Swift-mangled Objective-C entry thunk still receives self in x0.
        swiftTargets.formUnion(swiftStubAddresses(in: machO))
        swiftTargets.subtract(objcIndex.addresses)
        // Async funclet chains: group each resume funclet under its entry and
        // title the nameless ones after it. A funclet outside this decode (a
        // filtered run) is decoded on demand, so the grouping is whole-image.
        let byStart = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        let sortedBoundaries = boundaries.sorted()
        let asyncIndex = groupsAsyncFunclets
            ? asyncFuncletIndex(
                in: machO, boundaries: boundaries,
                instructions: { address in
                    byStart[address]?.instructions
                        ?? self.decodeFunction(at: address, boundaries: sortedBoundaries, in: machO)
                },
                nameOf: { resolver.callTargetName(at: $0) }
            )
            : AsyncFuncletIndex.build(hints: nil, functionStarts: [], instructions: { _ in [] }, nameOf: { _ in nil })
        functions = functions.map { function in
            asyncIndex.info(for: function.startAddress, parentName: {
                byStart[$0]?.displayName ?? resolver.callTargetName(at: $0)
            }).map(function.attachingAsyncFunclet) ?? function
        }
        // The differentiator's two halves: what lives at an offset (FieldMap),
        // and whether the pointer in x20 is that type (SelfTypeIndex). Both are
        // metadata-sourced, so both survive stripping.
        let fieldMaps = (try? FieldMapBuilder.build(in: machO)) ?? [:]
        let selfIndex = SelfTypeIndex.build(in: machO)
        let vtableIndex = VTableIndex.build(in: machO)
        // No-payload enum case names, so an immediate tag returned from an
        // enum-typed function renders as `.case` instead of a bare integer.
        let enumCaseIndex = EnumCaseIndex.build(in: machO)
        // Payload-enum empty-case names, resolved only where the encoding is
        // statically provable (see `PayloadEnumCaseIndex`).
        let payloadEnumIndex = PayloadEnumCaseIndex.build(in: machO)
        // Class (reference) type names, so a single-register `Optional<SomeClass>`
        // (nil == 0) seeds like a scalar and its `!= nil` reconstructs, while a
        // value-typed (tagged) optional still declines.
        let classTypeIndex = ClassTypeIndex.build(in: machO).adding(demangleCache.nominalTypes)
        let groupedByStart = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        let chainSlots = asyncChainSlots(
            index: asyncIndex,
            function: { groupedByStart[$0] },
            enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex
        )
        // The bodies the summaries decode, the filtered run's callees
        // included, are where a call site finds its outlined fragment.
        var outlinedFragments: [UInt64: OutlinedFragment] = [:]
        let finished: (facts: [UInt64: CalleeRegisterFacts], callerProvenResults: [UInt64: SwiftReturnRegister]) = {
                let isFunction = { (target: UInt64) in boundaries.contains(target) }
                let importStubs = CodeSection.importStubRanges(of: machO)
                let isImportStub = { (target: UInt64) in importStubs.contains { $0.contains(target) } }
                let isStackProbe = stackProbeRecognizer(in: machO, importStubs: importStubs)
                var summaryArities: [UInt64: Int?] = [:]
                let arity = { target in
                    if let cached = summaryArities[target] { return cached }
                    let result = self.knownArity(
                        ofCallTarget: target, names: resolver.names, cacheSymbols: cacheSymbols,
                        arcFunctions: resolver.arcFunctions, isFunction: isFunction)
                    summaryArities[target] = .some(result)
                    return result
                }
                // A summary reads a switch's `br` as the jump inside the body
                // it is, not as a tail call out of it.
                var bodies = Dictionary(
                    functions.map { ($0.startAddress, Self.withJumpTables($0, machO: machO, ranges: resolver.fileRanges)) },
                    uniquingKeysWith: { a, _ in a }
                )
                var summaries = Dictionary(
                    bodies.keys.sorted().compactMap { start in
                        bodies[start].flatMap { CalleeRegisterSummary.of($0, calleeArity: arity, isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe) }
                            .map { (start, $0) }
                    },
                    uniquingKeysWith: { a, _ in a }
                )
                var hasEntryRoleConsumer = Self.needsEntryRegisterProofs(
                    in: machO, names: resolvedNames, folded: foldedByAddress, swiftTargets: swiftTargets)
                    || bodies.values.contains { Self.hasRawSwiftCall(in: $0.instructions) }
                // A filtered run decodes its matches and their direct callees;
                // a clobber further down (a callee's callee) is decoded here, a
                // level at a time in address order, so the summaries see what
                // a whole-image run sees. A whole-image run decodes nothing.
                var level = Set(summaries.values.flatMap(\.callees)).filter {
                    summaries[$0] == nil && boundaries.contains($0)
                }.sorted()
                var decoded = 0
                while !level.isEmpty, decoded < 512 {
                    var next = Set<UInt64>()
                    for target in level where decoded < 512 && summaries[target] == nil {
                        let instructions = Probe.muted {
                            self.decodeFunction(at: target, boundaries: sortedBoundaries, in: machO)
                        }
                        guard !instructions.isEmpty else { continue }
                        hasEntryRoleConsumer = hasEntryRoleConsumer || Self.hasRawSwiftCall(in: instructions)
                        decoded += 1
                        let body = Self.withJumpTables(
                            DisassembledFunction(
                                symbol: "sub_\(String(target, radix: 16))", demangledName: nil,
                                startAddress: target, instructions: instructions, source: .address),
                            machO: machO, ranges: resolver.fileRanges)
                        bodies[target] = body
                        guard let summary = Probe.muted({
                            CalleeRegisterSummary.of(body, calleeArity: arity, isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe)
                        }) else { continue }
                        summaries[target] = summary
                        next.formUnion(summary.callees.filter { summaries[$0] == nil && boundaries.contains($0) })
                    }
                    level = next.sorted()
                }
                CalleeRegisterSummary.refineMemory(&summaries) { start, effects in
                    bodies[start].flatMap { function in
                        Probe.muted {
                            CalleeRegisterSummary.of(function, calleeEffects: effects, calleeArity: arity,
                                isFunction: isFunction, isImportStub: isImportStub, isStackProbe: isStackProbe)
                        }
                    }
                }
                CalleeRegisterSummary.closeOverReads(&summaries)
                let rebuildingEntryRoles = hasEntryRoleConsumer || Self.needsEntryRegisterProofs(
                    in: machO, names: resolvedNames, folded: foldedByAddress, swiftTargets: swiftTargets)
                CalleeRegisterSummary.closeOverCalls(&summaries, rebuildingEntryRoles: rebuildingEntryRoles) { start, effects, readFacts, reusePreservation in
                    bodies[start].flatMap { function in
                        Probe.muted {
                            CalleeRegisterSummary.recomputingPreservation(
                                function, retainingReadsFrom: readFacts, reusingPreservation: reusePreservation,
                                rebuildingEntryRoles: rebuildingEntryRoles, calleeEffects: effects, calleeArity: arity, isFunction: isFunction,
                                isImportStub: isImportStub, isStackProbe: isStackProbe)
                        }
                    }
                }
                if rebuildingEntryRoles { CalleeRegisterSummary.closeOverProvenEntryReads(&summaries) }
                CalleeRegisterSummary.closeOverFieldWrites(&summaries, arcIdentityContract: { target, callee in
                    resolver.arcIdentityContract(at: target, named: callee)
                }) { resolvedNames[$0] }
                for (start, body) in bodies {
                    outlinedFragments[start] = OutlinedFragment(start: start, instructions: body.instructions)
                }
                outlinedFragments = Self.inlinableFragments(outlinedFragments, names: resolvedNames)
                return CalleeRegisterFacts.finish(&summaries)
            }()
        let context = PerFunctionContext(
            resolver: resolver, swiftTargets: swiftTargets, objcIndex: objcIndex,
            fieldMaps: fieldMaps, selfIndex: selfIndex, vtableIndex: vtableIndex,
            enumCaseIndex: enumCaseIndex, payloadEnumIndex: payloadEnumIndex,
            classTypeIndex: classTypeIndex,
            classParameterFields: ClassParameterFieldIndex.build(
                in: machO, fieldMaps: fieldMaps, classTypeIndex: classTypeIndex, demangle: demangle),
            indirectResultUses: Dictionary(
                functions.map { ($0.startAddress, Self.indirectResultUse(of: $0)) },
                uniquingKeysWith: { a, _ in a }
            ),
            registerSummaries: finished.facts,
            outlinedFragments: outlinedFragments,
            callerProvenResults: finished.callerProvenResults,
            asyncIndex: asyncIndex, asyncChainSlots: chainSlots
        )
        functions = functions.map { analyzeFunction($0, context: context) }

        guard let needle = functionFilter?.lowercased(), !needle.isEmpty else {
            return functions
        }
        if let address = Self.filterAddress(needle) {
            // From its start, which an undecodable first word leaves before
            // its first instruction.
            return functions.filter { function in
                guard let last = function.instructions.last?.address else { return false }
                return function.startAddress <= address && address <= last
            }
        }
        return functions.filter {
            $0.symbol.lowercased().contains(needle)
                || ($0.demangledName?.lowercased().contains(needle) ?? false)
                || ($0.semanticName?.lowercased().contains(needle) ?? false)
                || foldedSymbolMatches($0, needle: needle)
        }
    }

    /// Whether `needle` (case-insensitive) is in one of the symbols folded
    /// onto `function`'s address, raw or demangled. A folded address
    /// declines to pick one of its symbols, so each of them selects it:
    /// `-f` on any folded symbol printed "No function matched" for a symbol
    /// the binary exports.
    public func foldedSymbolMatches(_ function: DisassembledFunction, needle: String) -> Bool {
        foldedSymbolMatches(candidates: function.foldedCandidates, needle: needle)
    }

    /// `foldedSymbolMatches(_:needle:)` over a function's folded symbols alone.
    public func foldedSymbolMatches(candidates: [String]?, needle: String) -> Bool {
        let needle = needle.lowercased()
        return (candidates ?? []).contains { candidate in
            candidate.lowercased().contains(needle)
                || (demangle(candidate).map { matchesName($0, needle: needle) } ?? false)
        }
    }

    /// Cross-function state, built once for a whole image, that the per-function
    /// analysis reads but never mutates. Bundled so the same `analyzeFunction`
    /// runs from both the array path (`assemble`) and the streaming path.
    struct PerFunctionContext {
        let resolver: ReferenceResolver
        let swiftTargets: Set<UInt64>
        let objcIndex: ObjCMetadataIndex
        let fieldMaps: [String: FieldMap]
        let selfIndex: SelfTypeIndex
        let vtableIndex: VTableIndex
        let enumCaseIndex: EnumCaseIndex
        let payloadEnumIndex: PayloadEnumCaseIndex
        let classTypeIndex: ClassTypeIndex
        /// The classes whose fields a free function names through a parameter.
        let classParameterFields: ClassParameterFieldIndex
        /// Function start → whether its body reads the incoming x8, so a call to
        /// it is known to write (or not write) through the caller's x8.
        var indirectResultUses: [UInt64: IndirectResultUse] = [:]
        /// Function start → what its body proves about the registers a call to
        /// it reads and clobbers, for callees no signature describes.
        var registerSummaries: [UInt64: CalleeRegisterFacts] = [:]
        /// Function start → its body, when it is short and straight-line
        /// enough to be an outlined fragment a call site can inline.
        var outlinedFragments: [UInt64: OutlinedFragment] = [:]
        /// Function start → the register its callers prove its result is in
        /// (`CalleeRegisterSummary.callerProvenResults`), for a function no
        /// signature describes.
        var callerProvenResults: [UInt64: SwiftReturnRegister] = [:]
        /// Async funclet chains and their suspension points.
        let asyncIndex: AsyncFuncletIndex
        /// Per resume funclet, the context-slot values definitely initialized
        /// before every entry suspension and stable throughout the chain.
        let asyncChainSlots: [UInt64: [Int: AbstractValue]]
        /// The members of `self`'s type each method's analysis looks up,
        /// computed once per type for the image.
        let selfMembers = SelfMemberCache()
        /// Where each callee's result is, computed once per callee name.
        let callResultBanks = CallResultBankCache()
    }

    /// `name(at:ownedBy:)` per (address, type) and the accessor map of each
    /// type, for one image. Both are pure functions of the context's fixed
    /// resolver and vtable index, and every method of a type asked for the
    /// same ones: libSwiftSyntax's `SyntaxVisitor` has 880 methods whose
    /// default bodies fold up to 871 symbols onto one address, and rebuilding
    /// the map per method was 99% of a whole-image run. Lookups only, never
    /// iterated, so the cache cannot change an order.
    final class SelfMemberCache: Sendable {
        struct OwnedAddress: Hashable { let address: UInt64; let typeName: String }
        typealias Accessors = [String: (property: String, isGetter: Bool)]
        private let owned = Mutex<[OwnedAddress: String?]>([:])
        private let accessors = Mutex<[String: Accessors]>([:])

        func name(at address: UInt64, ownedBy typeName: String, resolver: ReferenceResolver) -> String? {
            let key = OwnedAddress(address: address, typeName: typeName)
            if let hit = owned.withLock({ $0[key] }) { return hit }
            let name = resolver.name(at: address, ownedBy: typeName)
            owned.withLock { $0[key] = name }
            return name
        }

        func accessors(of typeName: String, build: () -> Accessors) -> Accessors {
            if let hit = accessors.withLock({ $0[typeName] }) { return hit }
            let map = build()
            accessors.withLock { $0[typeName] = map }
            return map
        }
    }

    /// Build the async funclet index for an image. The hint sections are read
    /// through `sectionBytes`, so a dyld-cache image works too.
    func asyncFuncletIndex(
        in machO: MachOFile, boundaries: Set<UInt64>,
        instructions: (UInt64) -> [Instruction], nameOf: (UInt64) -> String?
    ) -> AsyncFuncletIndex {
        let hints = AsyncFuncletIndex.hintSections(in: machO) { address, size in
            self.sectionBytes(address: address, size: size, in: machO)
        }
        return AsyncFuncletIndex.build(
            hints: hints, functionStarts: boundaries, instructions: instructions, nameOf: nameOf
        )
    }

    /// `sectionBytes` for a file on disk, so a test can feed the hint-section
    /// reader without reaching the private reader.
    func sectionBytesForTesting(address: UInt64, size: Int, path: String) -> Data? {
        guard let machO = try? BinaryLoader.load(path: path) else { return nil }
        return sectionBytes(address: address, size: size, in: machO)
    }

    /// Decode one function on demand: from `address` to the next sorted boundary
    /// (or the end of `__text`).
    func decodeFunction(at address: UInt64, boundaries: [UInt64], in machO: MachOFile,
                        section: TextSection? = nil) -> [Instruction] {
        guard let end = CodeSection.containing(address, in: codeSections(in: machO))?.range.upperBound
        else { return [] }
        var low = 0, high = boundaries.count
        while low < high {
            let mid = (low + high) / 2
            if boundaries[mid] <= address { low = mid + 1 } else { high = mid }
        }
        let stop = min(low < boundaries.count ? boundaries[low] : end, end)
        return section?.instructions(span: (address, stop)) ?? capstoneInstructions(in: machO, span: (address, stop))
    }

    /// A function as the register summaries read it: with its jump tables, so
    /// a switch's `br` is control flow inside the body rather than a tail call
    /// that may read every argument register and skip the cases. The
    /// summaries are built before `analyzeFunction` recovers the same tables
    /// for the rest of the analysis.
    static func withJumpTables(
        _ function: DisassembledFunction, machO: MachOFile, ranges: FileBackedRanges?
    ) -> DisassembledFunction {
        let tables = JumpTables.recognize(in: function, machO: machO, ranges: ranges)
        return tables.isEmpty ? function : function.attachingSwitchTargets(tables)
    }

    /// Whether an instruction between a call and the use of its result would
    /// be reordered by printing the call at the use: another call or any
    /// control flow, an instruction without detail, or a write to memory
    /// other than the frame. Loads are not: the epilogue's `ldp x29, x30`
    /// between `bl _finalize` and `ret` turned `return _finalize()` into
    /// `let r0 = _finalize(); return r0` in 158 fixture lines.
    static func isOrderingEffect(_ insn: Instruction) -> Bool {
        guard insn.controlFlow == nil || insn.controlFlow == .sequential, let detail = insn.detail else { return true }
        let mnemonic = insn.text.prefix { !$0.isWhitespace }
        let writesMemory = mnemonic.hasPrefix("st") || mnemonic.hasPrefix("swp") || mnemonic.hasPrefix("cas")
            || ["ldadd", "ldclr", "ldeor", "ldset", "ldsmax", "ldsmin", "ldumax", "ldumin"].contains { mnemonic.hasPrefix($0) }
        guard writesMemory else { return false }
        for info in detail.operands {
            if case .memory(let base?, _, _) = info.operand, base.key == "sp" || base.key == "x29" {
                return false
            }
        }
        return true
    }

    /// Whether `value` depends on what memory holds. Everything but a
    /// constant, an address, an argument, self's pointer, a call's result and
    /// arithmetic on them does: a load's value is that of its moment, and
    /// `AbstractValue` does not say which moment.
    static func readsMemory(_ value: AbstractValue) -> Bool {
        switch value {
        case .immediate, .address, .argument, .selfPointer, .callResult: false
        case .binary(_, let lhs, let rhs): readsMemory(lhs) || readsMemory(rhs)
        case .unary(_, let operand): readsMemory(operand)
        case .select(let condition, let whenTrue, let whenFalse):
            readsMemory(condition) || readsMemory(whenTrue) || readsMemory(whenFalse)
        default: true
        }
    }

    /// The address a Swift String object word `(address − 32) | 1<<63`
    /// holds, for a literal's object (see `swiftLargeStringLiteral`).
    static func largeStringObjectAddress(_ value: AbstractValue) -> UInt64? {
        guard case .binary(.bitOr, let lhs, let rhs) = value else { return nil }
        for (word, flag) in [(lhs, rhs), (rhs, lhs)] {
            if case .immediate(0x8000_0000_0000_0000) = flag, case .address(let address) = word {
                return address
            }
        }
        return nil
    }

    static func fieldFailureLabel(_ failure: FieldLookupFailure) -> String {
        switch failure {
        case .pastInstanceSize: "past-instance-size"
        case .pastTrustedPrefix(_, let reason): "past-trusted-prefix: \(reason)"
        case .padding: "padding"
        case .noLayout(let reason): "no-layout: \(reason)"
        }
    }

    /// The complete per-function analysis: resolve references and call targets,
    /// recover the receiver convention and field maps, and enrich call arguments.
    /// Extracted verbatim from `assemble`'s map so both paths produce identical
    /// output by construction; the streaming path calls it one function at a time.
    func analyzeFunction(
        _ rawFunction: DisassembledFunction, context: PerFunctionContext
    ) -> DisassembledFunction {
        Probe.inFunction(rawFunction.startAddress, rawFunction.displayName) {
            Probe.timed(.analysisTime) { analyzeFunctionBody(rawFunction, context: context) }
        }
    }

    private func analyzeFunctionBody(
        _ rawFunction: DisassembledFunction, context: PerFunctionContext
    ) -> DisassembledFunction {
        var function = annotateReferences(in: rawFunction, resolver: context.resolver)
        function = annotateCallTargets(in: function, resolver: context.resolver)
        function = Self.droppingSelfBranchCallees(function)
        let inlined = inliningOutlinedFragments(in: function, context: context)
        function = inlined.function
        let tables = JumpTables.recognize(
            in: function, machO: context.resolver.machO, ranges: context.resolver.fileRanges)
        if !tables.isEmpty { function = function.attachingSwitchTargets(tables) }
        let cfg = FunctionCFG(function)

        let objcMethod = function.objcMethod
        // Runtime-added category IMPs (an accessibility bundle is almost all
        // of them) frequently have no ObjC metadata binding, yet their symbol
        // name carries the full method shape. Recover the receiver convention
        // from the symbol so `self` survives — without it x0 is never seeded
        // and every receiver renders `?`.
        let symbolEntry = objcMethod == nil ? Self.objcEntryFromSymbol(function.symbol) : nil
        // A resume funclet is entered from the runtime, not called: its name
        // carries the parent's signature, but none of the parent's parameters
        // (nor `self`) is in a register here. Every live value was spilled to
        // the async context before the suspension, and the ABI preserves no
        // callee-saved register across it. Seeding `arg<n>` or x20 from the
        // signature would label the awaited result (x0) as the first parameter.
        let isResumeFunclet = function.asyncFunclet.map { !$0.isEntry } ?? false
        let classSelfTypeName = objcMethod == nil && symbolEntry == nil && !isResumeFunclet
            ? Self.selfType(of: function, selfIndex: context.selfIndex, fieldMaps: context.fieldMaps,
                            classTypeIndex: context.classTypeIndex)
            : nil
        // A nonmutating HFA-struct instance method passes `self` decomposed in
        // SIMD registers rather than through x20, so it needs the value-self
        // path even when the name-based `selfType` already found the type (it
        // would otherwise seed x20, which this ABI leaves as garbage). The
        // HFA + no-`[x20]` guards inside confine it to exactly that shape.
        let valueSelf = objcMethod == nil && symbolEntry == nil && !isResumeFunclet
            ? Self.swiftValueTypeSelfFields(of: function, fieldMaps: context.fieldMaps)
            : nil
        let selfTypeName = classSelfTypeName ?? valueSelf?.typeName
        let resolver = context.resolver
        let isOpaqueExistential: (String) -> Bool = { resolver.opaqueExistentialDescriptor(named: $0) != nil }
        let isClassBoundExistential: (String) -> Bool = { resolver.classBoundExistentialDescriptor(named: $0) != nil }
        let entry: MethodEntryConvention? = if isResumeFunclet {
            nil
        } else if let objcMethod {
            objcMethod.isInitializer
                ? .objectiveCInitializer(argumentCount: objcMethod.argumentCount,
                                         scalarArguments: Self.objcArgumentLocations(objcMethod))
                : .objectiveC(argumentCount: objcMethod.argumentCount,
                              scalarArguments: Self.objcArgumentLocations(objcMethod))
        } else if let symbolEntry {
            symbolEntry
        } else if let valueSelf {
            .swiftValueInstance(seededRegisters: valueSelf.seeded)
        } else if classSelfTypeName != nil || (!isResumeFunclet && symbolEntry == nil
                    && Self.swiftEnumSelfType(of: function, enumCaseIndex: context.enumCaseIndex) != nil) {
            {
                let arguments = Self.swiftArgumentRegisters(
                    of: function, enumCaseIndex: context.enumCaseIndex, classTypeIndex: context.classTypeIndex,
                    fieldMaps: context.fieldMaps, isOpaqueExistential: isOpaqueExistential,
                    isClassBoundExistential: isClassBoundExistential)
                return .swiftInstance(scalarArguments: arguments?.scalars ?? [:],
                                      existentialTables: arguments?.existentialTables ?? [:])
            }()
        } else if let arguments = Self.swiftArgumentRegisters(of: function, enumCaseIndex: context.enumCaseIndex, classTypeIndex: context.classTypeIndex, fieldMaps: context.fieldMaps, isOpaqueExistential: isOpaqueExistential, isClassBoundExistential: isClassBoundExistential) {
            {
                let metadata = Self.genericMetadataRegisters(
                    of: function, enumCaseIndex: context.enumCaseIndex,
                    classTypeIndex: context.classTypeIndex, fieldMaps: context.fieldMaps)
                return .swiftFunction(scalarArguments: arguments.scalars, genericMetadata: metadata,
                                      genericWitnessTables: Self.genericWitnessTableRegisters(of: function, metadata: metadata),
                                      existentialTables: arguments.existentialTables)
            }()
        } else if !DisassembledFunction.signatureKnown(displayName: function.analysisDisplayName, objcSignature: nil),
                  let summary = context.registerSummaries[function.startAddress], summary.provenArgumentCount > 0 {
            // No signature (a stripped `sub_…`, a C symbol): the body's own
            // reads prove its integer arguments, x0 through the highest
            // register it reads before writing, the gaps below filled as the
            // positional AAPCS64 assignment requires. Unseeded, every value
            // built from them was `?`, and `_cs_viaHelper` passed `(?, ?)`.
            .swiftFunction(scalarArguments: Dictionary(uniqueKeysWithValues:
                (0 ..< summary.provenArgumentCount).map { ("x\($0)", $0) }))
        } else {
            nil
        }
        let fieldMap: FieldMap? = if let objcMethod, !objcMethod.isClassMethod {
            context.objcIndex.fieldMaps[objcMethod.className]
        } else if let className = objcMethod == nil ? Self.objcClassName(fromSymbol: function.symbol) : nil {
            // No binding, but the symbol names the owning class: its ivar
            // layout may still be indexed, so `self->_ivar` can be named.
            context.objcIndex.fieldMaps[className]
        } else if let valueSelf {
            valueSelf.fieldMap
        } else {
            classSelfTypeName.flatMap {
                Self.selfFieldMap(of: function, simpleName: $0, fieldMaps: context.fieldMaps)
            }
        }
        // An async funclet: layer what the async ABI fixes (x22, the awaited
        // result) over the ordinary convention, and bring the context slots the
        // chain pass proved.
        let asyncEntry = Self.asyncConvention(for: function, base: entry, index: context.asyncIndex)
        if Probe.isActive {
            let seeded = asyncEntry ?? entry
            Probe.inFunction(function.startAddress, function.displayName) {
                Probe.record(.entryConvention, at: function.startAddress, [
                    "convention": .label(seeded.map(Self.conventionName) ?? "none"),
                    "selfType": .name(selfTypeName ?? "none"),
                    "seeds": .object(Dictionary(uniqueKeysWithValues: ValueTracer.entrySeeds(seeded).map {
                        ($0.register, ProbeValue.abstractValue($0.value))
                    })),
                ])
            }
        }
        let chainSlots = context.asyncChainSlots[function.startAddress] ?? [:]
        let classArguments: [Int: (type: String, map: FieldMap)] = if case .swiftFunction(let scalarArguments, _, _, _)? = entry {
            Self.classArguments(of: function, scalarArguments: scalarArguments, index: context.classParameterFields)
        } else {
            [:]
        }
        let classArgumentFieldMaps = classArguments.mapValues(\.map)
        let callerProvenResult = objcMethod == nil && symbolEntry == nil && asyncEntry == nil
            && function.asyncFunclet == nil
            && !DisassembledFunction.signatureKnown(displayName: function.analysisDisplayName, objcSignature: nil)
            ? context.callerProvenResults[function.startAddress] : nil
        var enriched = enrichCallArguments(
            in: function, cfg: cfg, resolver: context.resolver, swiftTargets: context.swiftTargets,
            entry: asyncEntry ?? entry,
            fieldMap: fieldMap,
            objcFieldSyntax: objcMethod != nil || symbolEntry != nil,
            selfTypeName: selfTypeName, vtableIndex: context.vtableIndex,
            argumentFieldMaps: valueSelf?.argumentFieldMaps ?? [:],
            classArgumentFieldMaps: classArgumentFieldMaps,
            classArgumentTypes: classArguments.mapValues(\.type),
            enumCaseIndex: context.enumCaseIndex,
            payloadEnumIndex: context.payloadEnumIndex,
            argumentEnumTypes: Self.swiftEnumArgumentTypes(of: function, enumCaseIndex: context.enumCaseIndex),
            boolArguments: Self.swiftBoolArgumentIndices(of: function).union(
                objcMethod.flatMap { ObjCArgumentABI.parameterTypes(encoding: $0.typeEncoding, argumentCount: $0.argumentCount) }
                    .map { types in Set(types.indices.filter { types[$0] == "B" }) } ?? []),
            classTypeIndex: context.classTypeIndex,
            indirectResultUse: context.indirectResultUses[function.startAddress]
                ?? Self.indirectResultUse(of: function, cfg: cfg),
            typeFieldMaps: context.fieldMaps,
            calleeConventions: Self.calleeResultConventions(
                in: function, indirectResultUses: context.indirectResultUses,
                resolver: context.resolver, fieldMaps: context.fieldMaps,
                classTypeIndex: context.classTypeIndex
            ),
            asyncContextSlots: chainSlots,
            asyncSuspensions: Self.asyncSuspensionNotes(in: function, index: context.asyncIndex),
            objcIndex: context.objcIndex,
            registerSummaries: context.registerSummaries,
            selfMembers: context.selfMembers,
            callResultBanks: context.callResultBanks,
            inlinedPrefixes: inlined.prefixes,
            callerProvenResult: callerProvenResult
        )
        enriched.callerProvenResult = callerProvenResult != nil
        return enriched
    }

    /// Each `bl` or `b` to an outlined fragment the tracer can model whole,
    /// rewritten to what the fragment does there (`OutlinedFragment.plan`),
    /// and the fragment instructions the tracer runs first at each.
    ///
    /// A fragment is the function at the target when the binary names it
    /// `OUTLINED_FUNCTION_n`, or when it has no name and its body breaks the
    /// calling convention (`breaksCallingConvention`): a stripped binary
    /// keeps only the body. A named function is never inlined, however
    /// short: its call is the source's.
    private func inliningOutlinedFragments(
        in function: DisassembledFunction, context: PerFunctionContext
    ) -> (function: DisassembledFunction, prefixes: [UInt64: [Instruction]]) {
        guard !context.outlinedFragments.isEmpty else { return (function, [:]) }
        let own = Set(function.instructions.map(\.address))
        let resolver = context.resolver
        func isFragment(_ target: UInt64) -> Bool {
            guard let fragment = context.outlinedFragments[target] else { return false }
            return Self.mayInline(fragment, named: resolver.callTargetName(at: target))
        }
        var annotated: [UInt64: OutlinedFragment] = [:]
        var prefixes: [UInt64: [Instruction]] = [:]
        var changed = false
        let instructions = function.instructions.map { insn -> Instruction in
            guard insn.controlFlow == .call || insn.controlFlow == .branch,
                  let target = insn.branchTarget, !own.contains(target),
                  let fragment = context.outlinedFragments[target], isFragment(target)
            else { return insn }
            // Named as the caller's own passes name its instructions, so a
            // call the fragment makes reads like a call the caller makes.
            let named: OutlinedFragment
            if let cached = annotated[target] {
                named = cached
            } else {
                var pieces = DisassembledFunction(
                    symbol: "sub_\(String(target, radix: 16))", demangledName: nil, startAddress: target,
                    instructions: fragment.body + [fragment.terminator], source: .address)
                pieces = annotateReferences(in: pieces, resolver: resolver)
                pieces = annotateCallTargets(in: pieces, resolver: resolver)
                guard let rebuilt = OutlinedFragment(start: target, instructions: pieces.instructions) else { return insn }
                annotated[target] = rebuilt
                named = rebuilt
            }
            let name = resolver.callTargetName(at: target) ?? "sub_\(String(target, radix: 16))"
            switch fragment.plan(site: insn, reachedByCall: insn.controlFlow == .call, annotated: named,
                                 name: name, isFragment: isFragment) {
            case .declined(let reason):
                Probe.record(.outlinedFragmentDeclined, at: insn.address, [
                    "fragment": .int(Int(target)), "reason": .label(reason),
                ])
                return insn
            case .inlined(let plan):
                Probe.record(.outlinedFragmentInlined, at: insn.address, [
                    "fragment": .int(Int(target)), "kind": .label(plan.kind), "instructions": .int(plan.prefix.count + 1),
                ])
                prefixes[insn.address] = plan.prefix
                changed = true
                return plan.visible
            }
        }
        return changed ? (function.replacingInstructions(instructions), prefixes) : (function, [:])
    }

    /// LLVM's machine outliner names its fragments `OUTLINED_FUNCTION_<n>`.
    static let outlinedFragmentPrefix = "OUTLINED_FUNCTION_"

    /// Whether a call to the function `fragment` was cut from, named `name`
    /// (the resolver's name, nil when it has none), may be inlined.
    static func mayInline(_ fragment: OutlinedFragment, named name: String?) -> Bool {
        if name?.hasPrefix(outlinedFragmentPrefix) == true { return true }
        return (name == nil || name?.hasPrefix("sub_") == true) && fragment.breaksCallingConvention
    }

    /// The fragments a call may inline, once names are final: every short
    /// body is a candidate when it is decoded, but only these are ever read,
    /// and the rest held 22 MB (bodies, operands and table) through a
    /// GoodLinks `xrefs`.
    static func inlinableFragments(
        _ fragments: [UInt64: OutlinedFragment], names: [UInt64: String]
    ) -> [UInt64: OutlinedFragment] {
        fragments.filter { mayInline($0.value, named: names[$0.key]) }
    }

    // MARK: - Async funclets

    /// The register state the async ABI fixes at a funclet's entry, layered
    /// over `base` (the entry funclet's ordinary convention; ignored for a
    /// resume funclet, whose registers carry none of the parameters).
    ///
    /// - entry / continuation: x22 is the function's own context.
    /// - await-return: x22 is the awaited callee's context (its first word is
    ///   the own context), and the callee's direct result is in x0 or v0,
    ///   named `awaited<N>`, only when the callee's demangled signature proves a
    ///   single-register result. An unknown callee seeds no result.
    /// - unknown kind, or no recovered parent: nil, so nothing is claimed.
    static func asyncConvention(
        for function: DisassembledFunction, base: MethodEntryConvention?, index: AsyncFuncletIndex
    ) -> MethodEntryConvention? {
        guard let info = function.asyncFunclet, info.parent != nil else { return nil }
        if info.isEntry {
            return .asyncFunclet(base: base, seededRegisters: ["x22": .asyncContext])
        }
        switch info.kind {
        case .continuation:
            return .asyncFunclet(base: nil, seededRegisters: ["x22": .asyncContext])
        case .awaitReturn:
            var seeded: [String: AbstractValue] = ["x22": .asyncCalleeContext]
            if let register = awaitedResultRegister(into: function.startAddress, index: index) {
                seeded[register] = .awaitResult(info.ordinal)
            }
            return .asyncFunclet(base: nil, seededRegisters: seeded)
        case .unknown, nil:
            return nil
        }
    }

    /// The register (`x0` / `v0`) the awaited call that `resume` continues
    /// delivers its direct result in, or nil when the callee is unknown, void,
    /// or returns through several registers.
    static func awaitedResultRegister(into resume: UInt64, index: AsyncFuncletIndex) -> String? {
        guard let (_, suspension) = index.suspension(into: resume), !suspension.isExecutorHop,
              let callee = suspension.calleeName
        else { return nil }
        // A typed-throws callee delivers its thrown payload in the same
        // register on the error path (with x20 = 1), and both paths resume
        // here: x0 is the result or the error. Naming it the result made a
        // catch block read `onError((awaited1 + 1000))`. Plain `throws` (or
        // `throws(any Error)`) returns its error in x20 and keeps the name.
        if let thrown = DisassembledFunction.splitSignature(callee)?.thrownType,
           !["any Swift.Error", "Swift.Error", "Error", "any Error"].contains(thrown) {
            return nil
        }
        // A closure's name prints its source type, not its convention: one
        // passed where a generic function is expected is emitted at that
        // abstraction, so an async-let child `implicit closure #1 @Sendable ()
        // async -> Swift.Int in …` takes an indirect result buffer in x0
        // (`str x0, [x22, #0x10]` at its entry) and resumes its caller with
        // nothing of the Int in x0. The name's last arrow is also the
        // enclosing function's result, not the closure's.
        if callee.contains("closure #") { return nil }
        switch swiftReturnRegister(forDemangledName: callee) {
        case .integer?: return "x0"
        case .floating?: return "v0"
        case nil: return nil
        }
    }

    /// What to say at each suspension instruction of `function`: an executor
    /// hop, or an awaited call with the name its result gets (empty when the
    /// result is not provable, so the call renders as a bare `await`).
    static func asyncSuspensionNotes(
        in function: DisassembledFunction, index: AsyncFuncletIndex
    ) -> [UInt64: AsyncSuspensionNote] {
        guard function.asyncFunclet != nil else { return [:] }
        var notes: [UInt64: AsyncSuspensionNote] = [:]
        for insn in function.instructions {
            guard let suspension = index.suspensions[insn.address] else { continue }
            if suspension.isExecutorHop {
                notes[insn.address] = .executorHop
            } else {
                let ordinal = index.funclets[suspension.resume]?.ordinal
                let binding = awaitedResultRegister(into: suspension.resume, index: index) != nil
                    ? ordinal.map(awaitResultName) : nil
                notes[insn.address] = .awaitedCall(binding: binding)
            }
        }
        return notes
    }

    enum AsyncSuspensionNote {
        case executorHop
        case awaitedCall(binding: String?)
    }

    /// Resume funclet → slot offset → value definitely initialized before
    /// every entry suspension. A candidate requires a unique portable store
    /// originating in entry, definite matching transfer facts, and no possible
    /// chain mutation. Entry receives no seeds; its forward states preserve
    /// the temporal order of its own loads and stores. Later-funclet stores
    /// decline until their inter-funclet ordering can be independently proved.
    func asyncChainSlots(
        index: AsyncFuncletIndex, function: (UInt64) -> DisassembledFunction?,
        enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex
    ) -> [UInt64: [Int: AbstractValue]] {
        func isPortable(_ value: AbstractValue) -> Bool {
            switch value {
            case .argument, .awaitResult, .immediate: return true
            case .binary(_, let lhs, let rhs): return isPortable(lhs) && isPortable(rhs)
            case .unary(_, let operand): return isPortable(operand)
            default: return false
            }
        }
        var result: [UInt64: [Int: AbstractValue]] = [:]
        // In address order: each chain records probe events, and Dictionary
        // order changes with every process.
        for (entry, chain) in index.chains.sorted(by: { $0.key < $1.key }) {
            var stores: [Int: [AbstractValue]] = [:]
            var escapedFrom: Int?
            var entryName: String?
            var entryTransferFacts: [UInt64: [Int: AbstractValue]] = [:]
            var entrySuspensions: [UInt64] = []
            for address in chain {
                guard let funclet = function(address) else {
                    escapedFrom = Int.min
                    Probe.record(.contextEscapeUnknown, at: address, ["reason": .label("missing-funclet")])
                    continue
                }
                if address == entry { entryName = funclet.displayName }
                // The entry's parameters, under the same proof the main pass uses.
                let base: MethodEntryConvention? = Self.swiftScalarArgumentRegisters(
                    of: funclet, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex
                ).map { .swiftFunction(scalarArguments: $0) }
                let convention = Self.asyncConvention(for: funclet, base: base, index: index)
                guard convention != nil else {
                    escapedFrom = Int.min
                    Probe.inFunction(funclet.startAddress, funclet.displayName) {
                        Probe.record(.contextEscapeUnknown, at: address, ["reason": .label("unknown-context-convention")])
                    }
                    continue
                }
                var tracer = ValueTracer()
                tracer.callFactsCache = callFactsCache
                if address == entry {
                    entrySuspensions = funclet.instructions.compactMap {
                        index.suspensions[$0.address] != nil ? $0.address : nil
                    }
                    tracer.asyncSlotFactBranches = Set(entrySuspensions)
                }
                let cfg = FunctionCFG(funclet)
                let analysis = tracer.analyze(funclet, entry: convention, cfg: cfg)
                if analysis.asyncUnboundedMemoryWrites {
                    escapedFrom = Int.min
                    Probe.inFunction(funclet.startAddress, funclet.displayName) {
                        Probe.record(.contextEscapeUnknown, at: funclet.startAddress,
                                     ["reason": .label("unbounded-memory-write")])
                    }
                }
                if address == entry { entryTransferFacts = analysis.asyncSlotFactsAtBranches }
                let internalAddresses = Set(funclet.instructions.map(\.address))
                var terminalBranches = Set(analysis.indirectControlFlowTargets.compactMap { address, target -> UInt64? in
                    if target == .asyncResumeParent { return address }
                    if case .address(let destination) = target, !internalAddresses.contains(destination) { return address }
                    return nil
                })
                for insn in funclet.instructions where index.suspensions[insn.address] != nil {
                    terminalBranches.insert(insn.address)
                }
                if let offset = Probe.inFunction(funclet.startAddress, funclet.displayName, {
                    AsyncContextEscapes().lowestOffset(in: funclet, terminalBranches: terminalBranches, cfg: cfg)
                }) {
                    escapedFrom = min(escapedFrom ?? offset, offset)
                }
                for (slot, values) in analysis.asyncSlotStores {
                    stores[slot, default: []] += values
                }
            }
            let proven = stores.filter { slot, _ in escapedFrom.map { slot < $0 } ?? true }
                .reduce(into: [Int: AbstractValue]()) { proven, pair in
                    let (slot, values) = pair
                    guard values.count == 1, let value = values.first, isPortable(value),
                          !entrySuspensions.isEmpty,
                          entrySuspensions.allSatisfy({ entryTransferFacts[$0]?[slot] == value })
                    else { return }
                    proven[slot] = value
                }
            // Entry uses its own forward state. Only later funclets receive
            // facts proven at every transition out of entry.
            for resume in chain where resume != entry {
                if !proven.isEmpty { result[resume] = proven }
                Probe.inFunction(resume, entryName ?? "async chain") {
                    for (offset, value) in proven.sorted(by: { $0.key < $1.key }) {
                        Probe.record(.slotProven, ["offset": .int(offset), "value": .abstractValue(value)])
                    }
                }
            }
        }
        return result
    }

    /// The code sections of `machO` (`CodeSection.of`), in address order,
    /// computed once per image: streaming decodes each function separately.
    /// None for an image the decoder cannot read (`decodesCode`), so whatever
    /// reaches here without `requireDecodableCode` claims nothing.
    func codeSections(in machO: MachOFile) -> [CodeSection] {
        guard Self.decodesCode(of: machO) else { return [] }
        let key = "\(machO.url.path)#\(machO.headerStartOffset)#\(machO.headerStartOffsetInCache)"
        return codeSectionCache.value(for: key) {
            CodeSection.of(machO, functionStarts: functionStarts(of: machO))
        }
    }

    /// Decode every code section, or just the parts of them inside
    /// `[start, stop)`, in-process with Capstone, in address order.
    /// Restricting to a span is what makes `disasm --function` fast on a large
    /// binary — only the matched function's code is decoded, not the whole
    /// text section. Bytes between code sections (stubs, constants) are never
    /// decoded.
    private func decodeText(
        in machO: MachOFile, span: (start: UInt64, stop: UInt64)?, includeText: Bool = true
    ) -> [DecodedInstruction] {
        guard let engine = CapstoneEngine() else { return [] }
        var decoded: [DecodedInstruction] = []
        for section in codeSections(in: machO) {
            let lo = max(span?.start ?? section.range.lowerBound, section.range.lowerBound)
            let hi = min(span?.stop ?? section.range.upperBound, section.range.upperBound)
            guard hi > lo, let bytes = sectionBytes(address: lo, size: Int(hi - lo), in: machO) else { continue }
            decoded += engine.disassemble(bytes, address: lo, includeText: includeText)
        }
        return decoded
    }

    /// Decode `__text` (or `span`) into an ordered instruction stream carrying
    /// text, control-flow class, and branch target.
    private func capstoneInstructions(in machO: MachOFile, span: (start: UInt64, stop: UInt64)? = nil) -> [Instruction] {
        decodeText(in: machO, span: span).map(Self.instruction(decoded:))
    }

    static func instruction(decoded: DecodedInstruction) -> Instruction {
        Instruction(
            address: decoded.address,
            text: decoded.text,
            annotation: nil,
            controlFlow: decoded.controlFlow,
            branchTarget: decoded.branchTarget,
            detail: decoded.detail
        )
    }

    /// The code sections (`CodeSection`) read once, for a run that decodes
    /// them one span at a time.
    /// Each span re-read the section's bounds from the load commands and its
    /// bytes from the file, and opened its own Capstone engine: `sample` of a
    /// GoodLinks `--pseudo` run put 2,555 of 81,749 samples under
    /// `textSectionBounds` and 2,291 under `readElements`. Nil when the
    /// section's bytes do not all read, so a span decodes on its own as it
    /// did.
    final class TextSection {
        let pieces: [(address: UInt64, bytes: Data)]
        let engine: CapstoneEngine

        fileprivate init?(pieces: [(address: UInt64, bytes: Data?, size: Int)]) {
            var read: [(address: UInt64, bytes: Data)] = []
            for piece in pieces {
                guard let bytes = piece.bytes, bytes.count == piece.size else { return nil }
                read.append((piece.address, bytes))
            }
            guard let engine = CapstoneEngine() else { return nil }
            self.pieces = read
            self.engine = engine
        }

        private init(pieces: [(address: UInt64, bytes: Data)], engine: CapstoneEngine) {
            self.pieces = pieces
            self.engine = engine
        }

        /// The same bytes with an engine of its own: a Capstone handle is one
        /// thread's at a time.
        func withOwnEngine() -> TextSection? {
            CapstoneEngine().map { TextSection(pieces: pieces, engine: $0) }
        }

        /// The instructions of `[start, stop)`, clipped to the sections, as
        /// `capstoneInstructions(in:span:)` decodes them.
        func instructions(span: (start: UInt64, stop: UInt64)) -> [Instruction] {
            var decoded: [Instruction] = []
            for (address, bytes) in pieces {
                let lo = max(span.start, address)
                let hi = min(span.stop, address + UInt64(bytes.count))
                guard hi > lo else { continue }
                let first = bytes.startIndex + Int(lo - address)
                let slice = bytes[first ..< first + Int(hi - lo)]
                decoded += engine.disassemble(slice, address: lo).map(Disassembler.instruction(decoded:))
            }
            return decoded
        }
    }

    /// Every code section of `machO`, read once (see `TextSection`).
    func textSection(in machO: MachOFile) -> TextSection? {
        let sections = codeSections(in: machO)
        guard !sections.isEmpty else { return nil }
        // One mapping of the file serves every section of a standalone image.
        let mapped = machO.isLoadedFromDyldCache ? nil : try? Data(contentsOf: machO.url, options: .alwaysMapped)
        return TextSection(pieces: sections.map { section in
            let size = Int(section.range.upperBound - section.range.lowerBound)
            let address = section.range.lowerBound
            return (address, mapped.flatMap { Self.mappedSlice(of: $0, address: address, size: size, in: machO) }
                ?? sectionBytes(address: address, size: size, in: machO), size)
        })
    }

    /// A section's bytes as a slice of the mapped file, copying nothing: a
    /// whole-image run holds them throughout, and the copy (`readElements`
    /// into an array, then into `Data`) was the largest block at a GoodLinks
    /// `xrefs` peak, 20 MB, with a second 20 MB while it was made. Mapped
    /// file pages are clean, so they are not footprint. The slice keeps the
    /// file's indices. Nil when the range is not in the file.
    static func mappedSlice(of file: Data, address: UInt64, size: Int, in machO: MachOFile) -> Data? {
        guard let offset = machO.fileOffset(of: address) else { return nil }
        let start = machO.headerStartOffset + Int(offset)
        guard start >= 0, size >= 0, start <= file.count, size <= file.count - start else { return nil }
        return file[start ..< start + size]
    }

    /// Raw bytes of an arbitrary section span (`__text`, `__objc_stubs`, …).
    ///
    /// For a plain file, read through the image reader. For a dyld-cache image
    /// the code usually lives in a *different* subcache file than the image
    /// header, and MachOKit's image reader only reaches the header's subcache —
    /// so locate the subcache that maps the section's VM address and read that
    /// subcache file directly.
    func sectionBytes(address: UInt64, size: Int, in machO: MachOFile) -> Data? {
        // MachOKit keeps a full cache it finds but not the failure to find
        // one, so for a plain file every `fullCache` read re-opened the
        // file as a dyld cache: 7.4% of a GoodLinks `--pseudo` run.
        if machO.isLoadedFromDyldCache, let full = machO.fullCache,
           let fullOffset = full.fileOffset(of: address),
           let subcache = full.cache(forFileOffset: fullOffset),
           let url = full.url(forFileOffset: fullOffset),
           let localOffset = subcache.fileOffset(of: address),
           let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: localOffset)
                return try handle.readDrained(upToCount: size)
            } catch {
                return nil
            }
        }
        if let bytes: [UInt8] = try? machO.readElements(
            offset: machO.resolveOffset(at: address),
            numberOfElements: size
        ) {
            return Data(bytes)
        }
        return nil
    }

    /// Add names for call targets that leave a dyld-cache image.
    ///
    /// No-op for a standalone binary (objdump already names its stubs in-text).
    /// For a cache image this is most of the difference between calls being
    /// anonymous addresses and being named.
    private func crossImageNames(
        for functions: [DisassembledFunction],
        names: [UInt64: String],
        resolver: CacheSymbolResolver?
    ) -> [UInt64: String] {
        guard resolver != nil else { return names }
        var targets = Set<UInt64>()
        for function in functions {
            collectUnnamedCallTargets(in: function.instructions, names: names, into: &targets)
        }
        return resolveCrossImageNames(targets, into: names, resolver: resolver)
    }

    /// Accumulate call/branch targets not already named, so the streaming path can
    /// gather them one function at a time instead of holding the whole image's
    /// instructions. Split out of `crossImageNames`; the two callers together
    /// reproduce its exact behaviour.
    private func collectUnnamedCallTargets(
        in instructions: [Instruction], names: [UInt64: String], into targets: inout Set<UInt64>
    ) {
        for insn in instructions
        where insn.controlFlow == .call || insn.controlFlow == .branch {
            if let target = insn.branchTarget, names[target] == nil { targets.insert(target) }
        }
    }

    /// Resolve accumulated cross-image call targets to names.
    /// The known argument count of a call target, by the name a call to it
    /// renders: an in-image or stub name, else the dyld cache's, so the
    /// whole-image and streaming paths agree.
    // ABI controls exercise this policy directly: a recovered entry signature
    // can hide an incorrect name-based fallback in the rendered caller.
    func knownArity(
        ofCallTarget target: UInt64, names: [UInt64: String], cacheSymbols: CacheSymbolResolver?,
        arcFunctions: [UInt64: RuntimeFunctionReference], isFunction: (UInt64) -> Bool
    ) -> Int? {
        let name = names[target] ?? cacheSymbols?.name(forCallTarget: target).map {
            demangle($0) ?? Self.stripLeadingUnderscore($0)
        }
        guard let name else { return nil }
        if DisassembledFunction.isARCReferenceHelper(name),
           arcFunctions[target]?.permitsARCIdentity(named: name) != true,
           cacheSymbols?.arcIdentityContract(forCallTarget: target, named: name) != true { return nil }
        // An in-image function named like a C library function is bounded by
        // its own body instead.
        if isFunction(target), DisassembledFunction.knownArityNameMayHaveTwin(name) { return nil }
        return DisassembledFunction.knownCArity(of: name)
    }

    private func resolveCrossImageNames(
        _ targets: Set<UInt64>, into names: [UInt64: String], resolver: CacheSymbolResolver?
    ) -> [UInt64: String] {
        guard let resolver else { return names }
        var names = names
        for target in targets {
            if let name = resolver.name(forCallTarget: target) {
                names[target] = demangle(name) ?? Self.stripLeadingUnderscore(name)
            }
        }
        return names
    }

    /// C variadic functions whose variadic arguments a printf-style format
    /// describes: the fixed parameter count and the format's position. The
    /// `_chk` forms are what `snprintf` and `sprintf` lower to at -O0
    /// (`__snprintf_chk(str, maxlen, flag, slen, format, …)`,
    /// `__sprintf_chk(str, flag, slen, format, …)`).
    static let cFormatVariadics: [String: (fixed: Int, format: Int)] = [
        "printf": (1, 0), "fprintf": (2, 1), "dprintf": (2, 1), "sprintf": (2, 1),
        "snprintf": (3, 2), "asprintf": (2, 1), "syslog": (2, 1),
        "NSLog": (1, 0), "CFStringCreateWithFormat": (3, 2),
        "__snprintf_chk": (5, 4), "__sprintf_chk": (4, 3),
    ]

    /// The type each variadic slot of a format call renders as:
    /// `Swift.Double` for a floating conversion whose slot one eight-byte
    /// store wrote with a finite normal or zero constant, so `%f` of 1.5
    /// reads `1.5`, not `0x3ff8000000000000`. Any other slot is untyped: an
    /// integer conversion, a narrower store, an unknown value, and a NaN, an
    /// infinity or a subnormal, whose shortest decimal does not say which
    /// bits were passed. Nil when no slot is a double, so the call renders
    /// as before.
    static func formatSlotTypes(
        _ kinds: [DisassembledFunction.MessageSend.FormatArgumentKind],
        values: [AbstractValue], storedBytes: [Int]
    ) -> [String]? {
        let types = kinds.enumerated().map { index, kind -> String in
            guard kind == .floating, index < values.count, index < storedBytes.count,
                  storedBytes[index] == 8, case .immediate(let bits) = values[index]
            else { return "" }
            let value = Double(bitPattern: bits)
            return value.isNormal || value.isZero ? "Swift.Double" : ""
        }
        return types.contains("Swift.Double") ? types : nil
    }

    /// Each symbolized protocol witness table (`…WP`), extended to the next
    /// symbol's address, with the conformance its demangled name states.
    private func witnessTables(in machO: MachOFile) -> [(range: Range<UInt64>, conformance: String)] {
        let prefix = "protocol witness table for "
        // `compactMap`: an N_ABS symbol is a constant, and one with bit 63 set
        // (`_swiftImmortalRefCount` in libswiftCore) reads as a negative offset.
        let starts = Set(machO.symbols.compactMap { UInt64(exactly: $0.offset) }).sorted()
        var tables: [(range: Range<UInt64>, conformance: String)] = []
        for symbol in machO.symbols where symbol.name.hasSuffix("WP") {
            guard let start = UInt64(exactly: symbol.offset), let name = demangle(symbol.name),
                  name.hasPrefix(prefix)
            else { continue }
            var low = 0, high = starts.count
            while low < high {
                let mid = (low + high) / 2
                if starts[mid] <= start { low = mid + 1 } else { high = mid }
            }
            guard low < starts.count else { continue }
            tables.append((start ..< starts[low], String(name.dropFirst(prefix.count))))
        }
        return tables.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Every protocol descriptor (`…Mp`) and method descriptor (`…Tq`)
    /// symbol the image defines, demangled, by address: what names a
    /// protocol requirement a witness table slot holds. An address with two
    /// such symbols keeps both, and names neither.
    private func protocolDescriptorSymbols(in machO: MachOFile) -> [UInt64: [String]] {
        var symbols: [UInt64: [String]] = [:]
        for symbol in machO.symbols where symbol.name.hasSuffix("Mp") || symbol.name.hasSuffix("Tq") {
            guard symbol.offset > 0, let name = demangle(symbol.name) else { continue }
            symbols[UInt64(symbol.offset), default: []].append(name)
        }
        return symbols
    }

    /// The name a reference to a folded address takes: `sub_<addr>`, as its
    /// heading, unless every candidate demangles to one name (and so one
    /// signature), which then stands. Nil leaves the symbol's own name.
    static func foldedTargetName(
        at address: UInt64, candidates: [String], demangle: (String) -> String?
    ) -> String? {
        let distinct = Set(candidates.map { demangle($0) ?? stripLeadingUnderscore($0) })
        return distinct.count > 1 ? "sub_\(String(address, radix: 16))" : nil
    }

    private static func stripLeadingUnderscore(_ symbol: String) -> String {
        symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
    }

    /// `stub address → objc_msgSend$selector` for this image's selector stubs.
    func objcStubNames(in machO: MachOFile) -> [UInt64: String] {
        let selectors = ObjCSelectors.selectorTable(in: machO).bySelref
        guard !selectors.isEmpty, let engine = CapstoneEngine() else { return [:] }
        return ObjCSelectors.stubNames(in: machO, selectors: selectors) { address, size in
            guard let bytes = sectionBytes(address: address, size: size, in: machO) else { return [] }
            return engine.disassemble(bytes, address: address).map { decoded in
                Instruction(
                    address: decoded.address, text: decoded.text, annotation: nil,
                    controlFlow: decoded.controlFlow, branchTarget: decoded.branchTarget,
                    detail: decoded.detail
                )
            }
        }
    }

    /// Classic `__stubs` address → imported symbol. These symbols are not
    /// function definitions and therefore never appear in `symbolLabels`, but
    /// naming them is essential for recognizing runtime tail calls such as
    /// `objc_autoreleaseReturnValue` and `objc_setProperty_nonatomic_copy`.
    private func symbolStubNames(in machO: MachOFile) -> [UInt64: String] {
        symbolStubSymbols(in: machO).mapValues { raw in demangle(raw) ?? Self.stripLeadingUnderscore(raw) }
    }

    /// Symbol stubs whose import is a Swift function. objdump's listing names
    /// the import behind a stub (`symbol stub for: _$s…`), which is how a call
    /// was known to follow the Swift convention; Capstone's text has no such
    /// comment. On every in-process path, a call to an imported Swift method
    /// lost its `self:` (`Hasher._combine(self: local_68)` became
    /// `_combine()`), and a filtered run disagreed with the full listing.
    private func swiftStubAddresses(in machO: MachOFile) -> Set<UInt64> {
        Set(symbolStubSymbols(in: machO).compactMap { Self.isSwiftMangled($0.value) ? $0.key : nil })
    }

    /// Stub address → the raw symbol of the import it jumps to.
    private func symbolStubSymbols(in machO: MachOFile) -> [UInt64: String] {
        symbolStubReferences(in: machO).mapValues(\.name)
    }

    /// A name alone does not distinguish a local definition from an import.
    /// Keep the raw nlist record until a consumer has checked that origin.
    private func symbolStubReferences(in machO: MachOFile) -> [UInt64: MachOFile.Symbol] {
        guard let table = machO.indirectSymbols else { return [:] }
        let indirect = Array(table)
        let symbols = Array(machO.symbols)
        var symbolsByStub: [UInt64: MachOFile.Symbol] = [:]

        for section in machO.sections where section.flags.type == .symbol_stubs {
            guard let first = section.indirectSymbolIndex,
                  let count = section.numberOfIndirectSymbols,
                  count > 0, first >= 0, first + count <= indirect.count
            else { continue }
            // The stride from the stubs themselves: Go's linker writes 6 as
            // its 12-byte stubs' size, and dividing by that count named every
            // stub from the eleventh on after another (`clock_gettime`'s stub
            // read `fcntl`). Only an unrecognised shape keeps the header's.
            let stubSize = Self.stubStride(at: UInt64(section.address), in: machO, bytes: sectionBytes)
                ?? section.size / count
            guard stubSize > 0 else { continue }
            let stubs = min(count, section.size / stubSize)

            for slot in 0..<stubs {
                guard let symbolIndex = indirect[first + slot].index,
                      symbols.indices.contains(symbolIndex)
                else { continue }
                let symbol = symbols[symbolIndex]
                guard !symbol.name.isEmpty else { continue }
                let address = UInt64(section.address + slot * stubSize)
                symbolsByStub[address] = symbol
            }
        }
        return symbolsByStub
    }

    /// The size of an arm64 import stub, read from the first one: `adrp;
    /// ldr; br` is 12 bytes, arm64e's `adrp; add; ldr; braa` 16. Nil for any
    /// other shape.
    static func stubStride(
        at address: UInt64, in machO: MachOFile, bytes: (UInt64, Int, MachOFile) -> Data?
    ) -> Int? {
        guard let data = bytes(address, 16, machO), let engine = CapstoneEngine() else { return nil }
        let ids = engine.disassemble(data, address: address).compactMap { $0.detail?.id }
        guard ids.count >= 3, ids[0] == AARCH64_INS_ADRP else { return nil }
        if ids[1] == AARCH64_INS_LDR, ids[2] == AARCH64_INS_BR { return 12 }
        if ids.count == 4, ids[1] == AARCH64_INS_ADD, ids[2] == AARCH64_INS_LDR,
           ids[3] == AARCH64_INS_BRAA || ids[3] == AARCH64_INS_BRAAZ { return 16 }
        return nil
    }

    struct ImportedFunctionReference: Sendable, Equatable {
        let rawSymbol: String
        let libraryName: String

        /// Compiler/native ABI reference: one formal String followed by the
        /// two ordinary receiver words; no context self in x20.
        var isStringHasPrefix: Bool {
            Disassembler.stripLeadingUnderscore(rawSymbol) == "$sSS9hasPrefixySbSSF"
                && ["/usr/lib/swift/libswiftCore.dylib", "@rpath/libswiftCore.dylib"].contains(libraryName)
        }
    }

    private func importedStubFunctions(in machO: MachOFile) -> [UInt64: ImportedFunctionReference] {
        guard !machO.isLoadedFromDyldCache else { return [:] }
        var imported: [UInt64: ImportedFunctionReference] = [:]
        for (address, symbol) in symbolStubReferences(in: machO) {
            guard let flags = symbol.nlist.flags, flags.stab == nil, flags.contains(.ext),
                  flags.type == .undf, symbol.offset == 0,
                  let description = symbol.nlist.symbolDescription, description.libraryOrdinalType == nil,
                  let library = Self.externalLibraryName(ordinal: Int(description.libraryOrdinal), in: machO)
            else { continue }
            imported[address] = ImportedFunctionReference(rawSymbol: symbol.name, libraryName: library)
        }
        return imported
    }

    /// Positive ordinary two-level ordinals only: self, flat lookup, weak
    /// lookup and cache-relative ordinals do not identify an external provider.
    private static func externalLibraryName(ordinal: Int, in machO: MachOFile) -> String? {
        guard !machO.isLoadedFromDyldCache, machO.header.flags.contains(.twolevel),
              !machO.header.flags.contains(.force_flat), ordinal > 0 else { return nil }
        let dependencies = machO.dependencies
        guard dependencies.indices.contains(ordinal - 1) else { return nil }
        let dependency = dependencies[ordinal - 1]
        if case .weakLoad = dependency.type { return nil }
        guard !dependency.useFlags.contains(.weak_link) else { return nil }
        return dependency.dylib.name
    }

    /// Exact ARC imports, with their two-level providers retained. Local
    /// definitions use their bodies; an install name does not prove behavior.
    private func arcFunctionReferences(in machO: MachOFile) -> [UInt64: RuntimeFunctionReference] {
        guard !machO.isLoadedFromDyldCache else { return [:] }
        let candidates = symbolStubReferences(in: machO).filter {
            DisassembledFunction.isARCReferenceHelper(Self.stripLeadingUnderscore($0.value.name))
        }
        guard !candidates.isEmpty, let engine = CapstoneEngine() else { return [:] }
        let bindings = ChainedFixupTable()
        let sections = machO.sections.filter { $0.flags.type == .symbol_stubs }
        var references: [UInt64: RuntimeFunctionReference] = [:]
        for (address, symbol) in candidates {
            guard let flags = symbol.nlist.flags, flags.stab == nil, flags.contains(.ext),
                  flags.type == .undf, symbol.offset == 0,
                  let description = symbol.nlist.symbolDescription, description.libraryOrdinalType == nil,
                  description.isDisjoint(with: [.weak_ref, .ref_to_weak]),
                  let library = Self.externalLibraryName(ordinal: Int(description.libraryOrdinal), in: machO)
            else { continue }
            let reference = RuntimeFunctionReference(rawSymbol: symbol.name, libraryName: library)
            guard let section = sections.first(where: {
                UInt64($0.address) <= address && address - UInt64($0.address) < UInt64($0.size)
            }), let count = section.numberOfIndirectSymbols, count > 0,
                  [12, 16].contains(section.size / count),
                  let bytes = sectionBytes(address: address, size: section.size / count, in: machO)
            else { continue }
            let instructions = engine.disassemble(bytes, address: address).map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }
            guard let slot = RuntimeFunctionReference.pointerSlot(in: instructions, startingAt: address),
                  let offset = machO.fileOffset(of: slot),
                  bindings.arcFunction(at: UInt64(offset), in: machO) == reference
            else { continue }
            references[address] = reference
        }
        return references
    }

    /// The address a symbol defined in a section names. An absolute symbol
    /// (`N_ABS`) is a constant, not an address: pixman's NEON assembly sets
    /// `mask_bpp_shift` to -1, whose conversion trapped every disassembly of
    /// Emacs's and KiCad's libpixman, and one whose value happens to equal a
    /// code address would name a function it has nothing to do with.
    static func sectionAddress(of symbol: MachOFile.Symbol) -> UInt64? {
        guard symbol.nlist.flags?.type == .sect else { return nil }
        return UInt64(exactly: symbol.offset)
    }

    /// Function labels from the symbol table: `__text`-range defined symbols,
    /// keyed by VM address. Present even in dyld-cache images (exports), and a
    /// no-op when the symbol table is stripped.
    private func symbolLabels(in machO: MachOFile) -> [UInt64: String] {
        // Restrict to the code sections so a defined-symbol's offset that maps
        // outside code (a mis-typed symbol) can't mislabel a function.
        let sections = codeSections(in: machO)
        guard !sections.isEmpty else { return [:] }

        // MachOKit's `Symbol.offset` is the nlist `n_value` — for a defined
        // symbol that's its (unslid) VM address, the same space as instruction
        // addresses and LC_FUNCTION_STARTS. (Undefined symbols have n_value 0,
        // which the __text-range filter drops.)
        var labels: [UInt64: String] = [:]
        for symbol in machO.symbols where !symbol.name.isEmpty {
            guard let address = Self.sectionAddress(of: symbol) else { continue }
            if CodeSection.containing(address, in: sections) != nil, labels[address] == nil {
                labels[address] = symbol.name
            }
        }
        // Either spelling of a function and its own witness can come first.
        for (address, symbols) in symbolsSharingAddresses(in: machO, sections: sections) {
            if let function = Self.functionBehindOwnWitnesses(symbols, demangle: { self.demangle($0) }) {
                labels[address] = function
            }
        }
        goLabels(in: machO, adding: &labels)
        return labels
    }

    /// The one function `symbols` describe, when every other symbol is that
    /// function's own witness: `One.hash(into:)` and `protocol witness for
    /// Hashable.hash(into:) in conformance One` share a body because the
    /// witness is the function, with nothing to adapt. That is one function
    /// described twice, not a fold, as a class method and its own witness
    /// are in `MetadataSymbolizer`. The witness has to name the same member
    /// with the same signature: `ImplS.y()` folded with the witness for
    /// `Impl2.x()` is two functions.
    static func functionBehindOwnWitnesses(_ symbols: [String], demangle: (String) -> String?) -> String? {
        let witnessSuffix = "TW"
        let functions = symbols.filter { !$0.hasSuffix(witnessSuffix) }
        guard functions.count == 1, functions.count < symbols.count, let function = demangle(functions[0]) else { return nil }
        let prefix = "protocol witness for ", conformanceMarker = " in conformance "
        for symbol in symbols where symbol.hasSuffix(witnessSuffix) {
            guard let witness = demangle(symbol), witness.hasPrefix(prefix),
                  let marker = witness.range(of: conformanceMarker),
                  let separator = witness.range(of: " : ", range: marker.upperBound ..< witness.endIndex),
                  let module = witness.range(of: " in ", range: separator.upperBound ..< witness.endIndex)
            else { return nil }
            var requirement = witness[witness.index(witness.startIndex, offsetBy: prefix.count) ..< marker.lowerBound]
            let isStatic = requirement.hasPrefix("static ")
            if isStatic { requirement = requirement.dropFirst("static ".count) }
            let proto = witness[separator.upperBound ..< module.lowerBound] + "."
            guard requirement.hasPrefix(proto) else { return nil }
            let member = requirement.dropFirst(proto.count)
            let type = witness[marker.upperBound ..< separator.lowerBound]
            guard function == (isStatic ? "static " : "") + type + "." + member else { return nil }
        }
        return functions[0]
    }

    /// Addresses in `__text` that two or more *distinct* symbols name.
    ///
    /// The release linker folds byte-identical function bodies onto one address
    /// (`ld -icf`, on by default for Mach-O release builds): outlined value
    /// witnesses, generic specializations, reabstraction thunks, and the many
    /// trivial getters/destructors that compile to a bare `ret` all collapse
    /// together under their separate mangled names. Nothing in a mangled name
    /// records the merge, so the demangler prints a confident, specific name for
    /// each — every one correct for at most one of the folded declarations.
    /// Naming the address after whichever symbol the table happens to list first
    /// (what `symbolLabels` does) silently misattributes the rest, so callers use
    /// this to decline instead. Value is the distinct names, sorted for
    /// determinism. Measured at 17% of `__text` symbols in one small `-O` fixture.
    /// Metadata that names one address once per owner is a fold the symbol
    /// table cannot show in a stripped binary. A symbol label, where there is
    /// one, already decided the address, so only unlabeled ones are added.
    /// The bodies of helpers IRGen emits privately into every image
    /// (lib/IRGen/MetadataRequest.cpp, GenExistential.cpp), as
    /// `normalizedBody` prints them: a direct branch's target relative to
    /// the function's start, and a call or tail branch through a stub as
    /// the stub's name. A stripped binary leaves them unnamed, and they are
    /// among its most-called functions. The boxed-existential helpers take
    /// the container's metadata from +0x18 whatever its witness-table count,
    /// so one body serves `…_existential_0`, `_1` and the rest, and the name
    /// leaves the count out. GoodLinks calls
    /// `__swift_instantiateConcreteTypeFromMangledNameV2` from 14,770 places
    /// and the boxed-existential projection from 2,077. Taken
    /// from the symbols of the fixtures, -O and -Onone; bodies shorter than
    /// eight instructions (the `memcpy` value witnesses, a lone `ret`) are
    /// left out, since many functions share them.
    static let helperShapes: [(name: String, body: [String])] = [
        // The pre-V2 helpers, which an image built by an older toolchain
        // carries (the swift-syntax dylibs in Xcode 27's toolchain: 818 of
        // their 5,434 unnamed direct calls): a negative cached word is a
        // relative mangled-name reference, resolved and cached.
        ("__swift_instantiateConcreteTypeFromMangledName", [
            "mov x8, x0",
            "ldr x0, [x0]",
            "tbnz x0, #0x3f, +0x10",
            "ret",
            "stp x20, x19, [sp, #-0x20]!",
            "stp x29, x30, [sp, #0x10]",
            "add x29, sp, #0x10",
            "neg x1, x0, asr #32",
            "add x0, x8, w0, sxtw",
            "mov x19, x8",
            "mov x2, #0",
            "mov x3, #0",
            "bl <swift_getTypeByMangledNameInContext2>",
            "str x0, [x19]",
            "ldp x29, x30, [sp, #0x10]",
            "ldp x20, x19, [sp], #0x20",
            "ret",
        ]),
        ("__swift_instantiateConcreteTypeFromMangledNameAbstract", [
            "mov x8, x0",
            "ldr x0, [x0]",
            "tbnz x0, #0x3f, +0x10",
            "ret",
            "stp x20, x19, [sp, #-0x20]!",
            "stp x29, x30, [sp, #0x10]",
            "add x29, sp, #0x10",
            "neg x2, x0, asr #32",
            "add x1, x8, w0, sxtw",
            "mov x19, x8",
            "mov w0, #0xff",
            "mov x3, #0",
            "mov x4, #0",
            "bl <swift_getTypeByMangledNameInContextInMetadataState2>",
            "str x0, [x19]",
            "ldp x29, x30, [sp, #0x10]",
            "ldp x20, x19, [sp], #0x20",
            "ret",
        ]),
        ("__swift_allocate_boxed_opaque_existential", [
            "ldr x8, [x0, #0x18]",
            "ldur x9, [x8, #-8]",
            "ldrb w9, [x9, #0x52]",
            "tbz w9, #1, +0x38",
            "stp x20, x19, [sp, #-0x20]!",
            "stp x29, x30, [sp, #0x10]",
            "add x29, sp, #0x10",
            "mov x19, x0",
            "mov x0, x8",
            "bl <swift_allocBox>",
            "str x0, [x19]",
            "mov x0, x1",
            "ldp x29, x30, [sp, #0x10]",
            "ldp x20, x19, [sp], #0x20",
            "ret",
        ]),
        ("__swift_destroy_boxed_opaque_existential", [
            "ldr x1, [x0, #0x18]",
            "ldur x8, [x1, #-8]",
            "ldrb w9, [x8, #0x52]",
            "tbnz w9, #1, +0x18",
            "ldr x2, [x8, #8]",
            "br x2",
            "ldr x0, [x0]",
            "b <swift_release>",
        ]),
        ("__swift_destroy_boxed_opaque_existential", [
            "sub sp, sp, #0x20",
            "stp x29, x30, [sp, #0x10]",
            "add x29, sp, #0x10",
            "str x0, [sp]",
            "ldr x8, [x0, #0x18]",
            "str x8, [sp, #8]",
            "ldur x8, [x8, #-8]",
            "ldr w8, [x8, #0x50]",
            "tbnz w8, #0x11, +0x48",
            "b +0x28",
            "ldr x1, [sp, #8]",
            "ldr x0, [sp]",
            "ldur x8, [x1, #-8]",
            "ldr x8, [x8, #8]",
            "blr x8",
            "ldp x29, x30, [sp, #0x10]",
            "add sp, sp, #0x20",
            "ret",
            "ldr x8, [sp]",
            "ldr x0, [x8]",
            "bl <swift_release>",
            "ldp x29, x30, [sp, #0x10]",
            "add sp, sp, #0x20",
            "ret",
        ]),
        ("__swift_instantiateConcreteTypeFromMangledNameV2", [
            "stp x20, x19, [sp, #-0x20]!",
            "stp x29, x30, [sp, #0x10]",
            "add x29, sp, #0x10",
            "mov x19, x0",
            "ldr x0, [x0]",
            "and x8, x0, #1",
            "cmp x0, #0",
            "ccmp x8, #0, #0, ne",
            "b.eq +0x44",
            "ldr x9, [x1]",
            "asr x8, x9, #32",
            "add x0, x1, w9, sxtw",
            "mov x1, x8",
            "mov x2, #0",
            "mov x3, #0",
            "bl <swift_getTypeByMangledNameInContext2>",
            "str x0, [x19]",
            "ldp x29, x30, [sp, #0x10]",
            "ldp x20, x19, [sp], #0x20",
            "ret",
        ]),
        ("__swift_instantiateConcreteTypeFromMangledNameV2", [
            "stp x20, x19, [sp, #-0x20]!",
            "stp x29, x30, [sp, #0x10]",
            "add x29, sp, #0x10",
            "mov x19, x0",
            "ldr x0, [x0]",
            "and x8, x0, #1",
            "cmp x0, #0",
            "ccmp x8, #0, #0, ne",
            "b.eq +0x44",
            "ldr x9, [x1]",
            "asr x8, x9, #32",
            "add x0, x1, w9, sxtw",
            "mov x1, x8",
            "mov x2, #0",
            "mov x3, #0",
            "bl <swift_getTypeByMangledNameInContext>",
            "str x0, [x19]",
            "ldp x29, x30, [sp, #0x10]",
            "ldp x20, x19, [sp], #0x20",
            "ret",
        ]),
        ("__swift_instantiateConcreteTypeFromMangledNameV2", [
            "stp x20, x19, [sp, #-0x20]!",
            "stp x29, x30, [sp, #0x10]",
            "add x29, sp, #0x10",
            "mov x19, x0",
            "ldr x0, [x0]",
            "cbz x0, +0x1c",
            "tbz w0, #0, +0x3c",
            "ldr x9, [x1]",
            "asr x8, x9, #32",
            "add x0, x1, w9, sxtw",
            "mov x1, x8",
            "mov x2, #0",
            "mov x3, #0",
            "bl <swift_getTypeByMangledNameInContext2>",
            "str x0, [x19]",
            "ldp x29, x30, [sp, #0x10]",
            "ldp x20, x19, [sp], #0x20",
            "ret",
        ]),
        ("__swift_instantiateConcreteTypeFromMangledNameV2", [
            "stp x20, x19, [sp, #-0x20]!",
            "stp x29, x30, [sp, #0x10]",
            "add x29, sp, #0x10",
            "mov x19, x0",
            "ldr x0, [x0]",
            "cbz x0, +0x1c",
            "tbz w0, #0, +0x3c",
            "ldr x9, [x1]",
            "asr x8, x9, #32",
            "add x0, x1, w9, sxtw",
            "mov x1, x8",
            "mov x2, #0",
            "mov x3, #0",
            "bl <swift_getTypeByMangledNameInContext>",
            "str x0, [x19]",
            "ldp x29, x30, [sp, #0x10]",
            "ldp x20, x19, [sp], #0x20",
            "ret",
        ]),
        ("__swift_instantiateGenericMetadata", [
            "sub sp, sp, #0x30",
            "stp x29, x30, [sp, #0x20]",
            "add x29, sp, #0x20",
            "stp x1, x2, [sp, #8]",
            "str x3, [sp, #0x18]",
            "add x1, sp, #8",
            "mov x2, x4",
            "bl <swift_getGenericMetadata>",
            "ldp x29, x30, [sp, #0x20]",
            "add sp, sp, #0x30",
            "ret",
        ]),
        ("__swift_instantiateGenericMetadata", [
            "sub sp, sp, #0x30",
            "stp x29, x30, [sp, #0x20]",
            "add x29, sp, #0x20",
            "mov x9, x1",
            "mov x8, x2",
            "mov x2, x4",
            "add x1, sp, #8",
            "str x9, [sp, #8]",
            "str x8, [sp, #0x10]",
            "str x3, [sp, #0x18]",
            "bl <swift_getGenericMetadata>",
            "ldp x29, x30, [sp, #0x20]",
            "add sp, sp, #0x30",
            "ret",
        ]),
        ("__swift_project_boxed_opaque_existential", [
            "ldur x8, [x1, #-8]",
            "ldr w8, [x8, #0x50]",
            "tbz w8, #0x11, +0x20",
            "ldr x9, [x0]",
            "and x8, x8, #0xff",
            "add x10, x8, #0x10",
            "bic x8, x10, x8",
            "add x0, x9, x8",
            "ret",
        ]),
        ("__swift_project_boxed_opaque_existential", [
            "sub sp, sp, #0x10",
            "str x0, [sp]",
            "ldur x8, [x1, #-8]",
            "ldr w8, [x8, #0x50]",
            "str x8, [sp, #8]",
            "tbnz w8, #0x11, +0x28",
            "b +0x1c",
            "ldr x0, [sp]",
            "add sp, sp, #0x10",
            "ret",
            "ldr x9, [sp, #8]",
            "ldr x8, [sp]",
            "ldr x8, [x8]",
            "and x10, x9, #0xff",
            "add x9, x10, #0x10",
            "bic x9, x9, x10",
            "add x0, x8, x9",
            "add sp, sp, #0x10",
            "ret",
        ]),
    ]
    static let mangledNameMetadataHelperName = "__swift_instantiateConcreteTypeFromMangledNameV2"
    static let helperShapeNames = Set(helperShapes.map(\.name))

    /// A body as `helperShapes` spells it.
    static func normalizedBody(_ instructions: [Instruction], start: UInt64, stubs: [UInt64: String]) -> [String] {
        instructions.map { insn in
            let fields = insn.text.split(whereSeparator: \.isWhitespace)
            let mnemonic = fields.first.map(String.init) ?? ""
            if let target = insn.branchTarget {
                if let stub = stubs[target], insn.controlFlow == .call || insn.controlFlow == .branch {
                    return "\(mnemonic) <\(stub)>"
                }
                if insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch {
                    var operands = fields.dropFirst().joined(separator: " ").components(separatedBy: ", ")
                    operands[operands.count - 1] = "+0x" + String(target &- start, radix: 16)
                    return mnemonic + " " + operands.joined(separator: ", ")
                }
            }
            return fields.joined(separator: " ")
        }
    }

    /// Unnamed in-image functions whose whole body is one of `helperShapes`,
    /// by start address. Only spans of a shape's length are decoded.
    func recognizedHelperNames(
        in machO: MachOFile, boundaries: [UInt64], labels: [UInt64: String]
    ) -> [UInt64: String] {
        let byLength = Dictionary(grouping: Self.helperShapes, by: { UInt64($0.body.count * 4) })
        let stubs = symbolStubNames(in: machO)
        let sections = codeSections(in: machO)
        var names: [UInt64: String] = [:]
        for (index, start) in boundaries.enumerated() where labels[start] == nil {
            guard let section = CodeSection.containing(start, in: sections) else { continue }
            let stop = min(index + 1 < boundaries.count ? boundaries[index + 1] : section.range.upperBound,
                           section.range.upperBound)
            // A function may be padded to the next boundary.
            for (length, shapes) in byLength where stop - start >= length && stop - start < length + 16 {
                let body = Self.normalizedBody(
                    capstoneInstructions(in: machO, span: (start, start + length)), start: start, stubs: stubs)
                if let shape = shapes.first(where: { $0.body == body }) { names[start] = shape.name }
            }
        }
        return names
    }

    static func mergeMetadataFolds(
        _ folds: [UInt64: [String]], into folded: inout [UInt64: [String]], labels: [UInt64: String]
    ) {
        for (address, candidates) in folds where labels[address] == nil && folded[address] == nil {
            folded[address] = candidates
        }
    }

    private func foldedSymbolAddresses(in machO: MachOFile) -> [UInt64: [String]] {
        let sections = codeSections(in: machO)
        guard !sections.isEmpty else { return [:] }
        return symbolsSharingAddresses(in: machO, sections: sections).filter {
            Self.functionBehindOwnWitnesses($0.value, demangle: { self.demangle($0) }) == nil
        }
    }

    /// Every code address two or more distinct symbols name, sorted.
    private func symbolsSharingAddresses(in machO: MachOFile, sections: [CodeSection]) -> [UInt64: [String]] {
        var namesByAddress: [UInt64: Set<String>] = [:]
        for symbol in machO.symbols where !symbol.name.isEmpty {
            guard let address = Self.sectionAddress(of: symbol),
                  CodeSection.containing(address, in: sections) != nil else { continue }
            namesByAddress[address, default: []].insert(symbol.name)
        }
        return namesByAddress
            .filter { $0.value.count >= 2 }
            .mapValues { $0.sorted() }
    }

    /// Named addresses a stripped image can no longer show are not folded.
    ///
    /// `foldedSymbolAddresses` sees a fold only while two symbols survive,
    /// and `MetadataSymbolizer` only while two owners have records. Strip
    /// takes the rest: `sf_O.s.exe` called `sf.K.method()` at a body that is
    /// also a closure-propagated specialization of `closureUser`, because
    /// `K.other()` was the one name left there. Strip shows as a function
    /// start with no symbol and no local symbol in code. Either alone says
    /// nothing: an unstripped image can hold an unlabeled start, and a
    /// dylib of exports never had a local. An image that keeps its locals
    /// keeps every partner, so nothing is suspected there.
    ///
    /// The result maps an address to the name it would have been credited
    /// with. Headings keep that name, true of the body, and a reference
    /// declines as it does at a proven fold. A consumer that knows the owner
    /// it came through (a vtable slot) still picks it from the candidates.
    private func foldSuspects(
        in machO: MachOFile, labels: [UInt64: String], metadataNames: [UInt64: String],
        folded: [UInt64: [String]], objcIndex: ObjCMetadataIndex
    ) -> [UInt64: [String]] {
        let sections = codeSections(in: machO)
        guard functionStarts(of: machO).contains(where: { labels[$0] == nil }),
              !machO.symbols.contains(where: { symbol in
                  symbol.nlist.flags?.contains(.ext) == false && !symbol.name.isEmpty
                      && Self.sectionAddress(of: symbol).map { CodeSection.containing($0, in: sections) != nil } == true
              })
        else { return [:] }
        var claims = labels
        for (address, name) in metadataNames where labels[address] == nil && !Self.helperShapeNames.contains(name) {
            claims[address] = name
        }
        var suspects: [UInt64: [String]] = [:]
        // Reads code words only, by address, through `sectionBytes`: no
        // metadata and no relative pointer. Additive to the reads being
        // rerouted in `FileBackedRanges` and the metadata indexes.
        var window: (start: UInt64, bytes: Data) = (0, Data())
        for address in claims.keys.sorted() where folded[address] == nil && objcIndex.binding(for: address) == nil {
            if address < window.start || address + 4 > window.start + UInt64(window.bytes.count)
                || (address + UInt64(TrivialBody.wordCount * 4) > window.start + UInt64(window.bytes.count)
                    && window.bytes.count == Self.codeWindowSize) {
                // A read past the end of the file fails whole, so stop at the section's end.
                guard let end = CodeSection.containing(address, in: sections)?.range.upperBound else { continue }
                let length = min(UInt64(Self.codeWindowSize), end - address)
                window = (address, sectionBytes(address: address, size: Int(length), in: machO) ?? Data())
            }
            let offset = Int(address - window.start)
            let available = min(TrivialBody.wordCount, (window.bytes.count - offset) / 4)
            let words = window.bytes.withUnsafeBytes { bytes in
                (0 ..< max(available, 0)).map {
                    UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + $0 * 4, as: UInt32.self))
                }
            }
            if TrivialBody.matches(words), let name = claims[address] { suspects[address] = [name] }
        }
        return suspects
    }

    /// `foldSuspects` reads code in windows of this size: a few reads for a
    /// whole image, without holding its `__text`.
    private static let codeWindowSize = 1 << 20

    // MARK: - Segmentation

    private func segment(
        _ instructions: [Instruction],
        boundaries: Set<UInt64>,
        labelByAddress: [UInt64: String],
        foldedByAddress: [UInt64: [String]],
        metadataNames: [UInt64: String],
        objcIndex: ObjCMetadataIndex,
        in machO: MachOFile,
        emitsUndecodedSpans: Bool = false,
        sortedBoundaries: [UInt64]? = nil,
        dataSpans: [UInt64: (end: UInt64, name: String)] = [:]
    ) -> [DisassembledFunction] {
        var functions: [DisassembledFunction] = []
        var current: [Instruction] = []
        // A span a function table lists but whose bytes are data (Go's
        // build ID) keeps its name and boundary and loses its "instructions";
        // the two symbols at its address (`go:buildid`, `runtime.text`, a
        // marker) are no identical-code fold.
        let instructions = dataSpans.isEmpty ? instructions : instructions.filter { insn in
            !dataSpans.contains { insn.address >= $0.key && insn.address < $0.value.end }
        }
        var labelByAddress = labelByAddress, foldedByAddress = foldedByAddress
        for (start, span) in dataSpans {
            foldedByAddress[start] = nil
            labelByAddress[start] = "_" + span.name
        }
        // Decoded one span at a time, a data span is a span with nothing.
        if instructions.isEmpty, let only = dataSpans.keys.first, dataSpans.count == 1 {
            return [makeFunction(start: only, instructions: [], labelByAddress: labelByAddress,
                                 foldedByAddress: foldedByAddress, metadataNames: metadataNames,
                                 objcIndex: objcIndex, in: machO)]
        }
        var start: UInt64 = instructions.first?.address ?? 0

        func flush() {
            guard !current.isEmpty else { return }
            functions.append(makeFunction(start: start, instructions: current,
                                           labelByAddress: labelByAddress,
                                           foldedByAddress: foldedByAddress,
                                           metadataNames: metadataNames,
                                           objcIndex: objcIndex, in: machO))
            current = []
        }

        // A boundary cuts a function wherever it falls, on an instruction or
        // between two: a start whose first word does not decode (a table in
        // `__text` that LC_FUNCTION_STARTS marks) still begins its function
        // there. Cut only at decoded addresses, AGX's table at 0x24ae3fc70
        // ran on from the function before it, and a filtered run named it
        // `sub_24ae3fc74`. The function holding an instruction starts at the
        // last boundary at or below it.
        let sorted = sortedBoundaries ?? boundaries.sorted()
        var next = 0
        // A caller decoding one span at a time passes the boundaries
        // sorted once, and the walk starts at the last boundary at or below
        // the first instruction: the earlier ones are crossed with no
        // instruction between them, which only a whole decode reports.
        if sortedBoundaries != nil, !emitsUndecodedSpans, let first = instructions.first?.address {
            var low = 0, high = sorted.count
            while low < high {
                let mid = (low + high) / 2
                if sorted[mid] <= first { low = mid + 1 } else { high = mid }
            }
            next = max(low - 1, 0)
        }
        for insn in instructions {
            var crossed: UInt64?
            while next < sorted.count, sorted[next] <= insn.address {
                // A boundary passed with no instruction of its own before
                // the next one marks a span that is not code. Only a whole
                // decode knows that; a filtered one skips other functions.
                if let passed = crossed, emitsUndecodedSpans || dataSpans[passed] != nil {
                    flush()
                    functions.append(makeFunction(start: passed, instructions: [],
                                                  labelByAddress: labelByAddress,
                                                  foldedByAddress: foldedByAddress,
                                                  metadataNames: metadataNames,
                                                  objcIndex: objcIndex, in: machO))
                }
                crossed = sorted[next]
                next += 1
            }
            if let crossed {
                flush()
                start = crossed
            } else if current.isEmpty {
                start = insn.address
            }
            current.append(insn)
        }
        flush()
        return functions
    }

    private func makeFunction(
        start: UInt64,
        instructions: [Instruction],
        labelByAddress: [UInt64: String],
        foldedByAddress: [UInt64: [String]],
        metadataNames: [UInt64: String],
        objcIndex: ObjCMetadataIndex,
        in machO: MachOFile
    ) -> DisassembledFunction {
        let subName = "sub_\(String(start, radix: 16))"
        let objcMethod = objcIndex.binding(for: start)
        // Identical code folding: the symbol table lists several distinct symbols
        // at this address, so attributing any one of them misnames the rest.
        // Decline — render `sub_<addr>` and carry the candidates. A bound ObjC IMP
        // (below) is runtime-authoritative for a real source identity, so it still
        // wins over the fold.
        if objcMethod == nil, let folded = foldedByAddress[start] {
            return DisassembledFunction(
                symbol: subName,
                demangledName: nil,
                startAddress: start,
                instructions: instructions,
                source: .foldedSymbols,
                foldedCandidates: folded
            )
        }
        if let rawLabel = labelByAddress[start] {
            return DisassembledFunction(
                symbol: rawLabel,
                // Runtime metadata is authoritative about an ObjC thunk's
                // source-level identity; keep the raw Swift/C symbol below it.
                demangledName: objcMethod?.displayName ?? demangle(rawLabel).map { demangleCache.presentation(of: $0) },
                startAddress: start,
                instructions: instructions,
                source: .symbol,
                objcMethod: objcMethod,
                semanticName: objcMethod == nil ? demangle(rawLabel) : nil
            )
        }
        if let objcMethod {
            return DisassembledFunction(
                symbol: subName,
                demangledName: objcMethod.displayName,
                startAddress: start,
                instructions: instructions,
                source: .objcMetadata,
                objcMethod: objcMethod
            )
        }
        if let metaName = metadataNames[start] {
            let isHelper = Self.helperShapeNames.contains(metaName)
            return DisassembledFunction(
                symbol: subName,
                demangledName: isHelper ? metaName : demangleCache.presentation(of: metaName),
                startAddress: start,
                instructions: instructions,
                source: isHelper ? .helperShape : .metadata,
                semanticName: metaName
            )
        }
        return DisassembledFunction(
            symbol: subName,
            demangledName: nil,
            startAddress: start,
            instructions: instructions,
            source: .address,
            boundary: recordedStarts(of: machO).contains(start) ? .functionStarts : .decodeStart
        )
    }

    /// The addresses LC_FUNCTION_STARTS lists. A Go image's table is not
    /// among them: its entries all have names, so none reaches this question.
    private func recordedStarts(of machO: MachOFile) -> Set<UInt64> {
        let key = "\(machO.url.path)#\(machO.headerStartOffset)#\(machO.headerStartOffsetInCache)"
        return boundaryCache.value(for: key) {
            Set((machO.functionStarts.map(Array.init) ?? []).map { UInt64($0.offset) })
        }
    }

    /// Says so on stderr when nothing can be trusted to
    /// separate this image's functions: no LC_FUNCTION_STARTS, no Go table,
    /// and code its symbols leave unmarked. `clang -Wl,-no_function_starts`
    /// then `strip` gave one function where the source has three, silently.
    func warnOfUnreliableBoundaries(in machO: MachOFile) {
        guard let warning = boundaryWarning(in: machO) else { return }
        FileHandle.standardError.write(Data(warning.utf8))
    }

    /// The warning `warnOfUnreliableBoundaries` prints, or nil. A table
    /// whose entries all lie outside the code marks nothing: a damaged
    /// LC_FUNCTION_STARTS (one entry far past the image) left a stripped
    /// executable decoding as one function, with no warning, because the
    /// table was not empty.
    func boundaryWarning(in machO: MachOFile) -> String? {
        let starts = functionStarts(of: machO)
        let sections = codeSections(in: machO)
        guard !starts.contains(where: { start in sections.contains { $0.range.contains(start) } }),
              let unmarked = unmarkedEntry(in: machO)
        else { return nil }
        let table = starts.isEmpty
            ? "no LC_FUNCTION_STARTS"
            : "LC_FUNCTION_STARTS lists no address inside the code"
        return """
            warning: \(table), and symbols do not mark every function: code at \
            0x\(String(unmarked, radix: 16)) is a call target or follows a return, with no boundary. \
            Functions may be merged, so read each body as possibly several.

            """
    }

    /// The first address with evidence of a function no boundary marks, or
    /// nil. Evidence, not a boundary: a direct call's target, or code after a
    /// return that nothing branches to, which a jump table can also reach.
    /// Decoded in pieces, and a call target ends the scan, so a stripped
    /// image costs little and Electron's 140 MB of `__text` is never held.
    func unmarkedEntry(in machO: MachOFile) -> UInt64? {
        guard let engine = CapstoneEngine() else { return nil }
        let sections = codeSections(in: machO)
        var boundaries = Set(symbolLabels(in: machO).keys)
        boundaries.formUnion(ObjCMetadataIndex.build(in: machO).addresses)
        boundaries.formUnion(sections.map(\.range.lowerBound))
        var scan = UnmarkedEntryScan(boundaries: boundaries, sections: sections)
        let piece: UInt64 = 1 << 20
        for section in sections {
            var low = section.range.lowerBound
            while low < section.range.upperBound {
                let high = min(low + piece, section.range.upperBound)
                defer { low = high }
                guard let bytes = sectionBytes(address: low, size: Int(high - low), in: machO) else { continue }
                if let target = scan.read(engine.disassemble(bytes, address: low)) { return target }
            }
        }
        return scan.finish()
    }

    // MARK: - Data sources

    /// How many function boundaries the binary itself declares, from
    /// `LC_FUNCTION_STARTS`.
    ///
    /// This is the independent oracle for recovery *completeness*: the linker
    /// emits it, it survives stripping, and it is computed without decoding a
    /// single instruction — so it cannot be wrong for the same reason a decoder
    /// is wrong. Recovering far fewer functions than this is evidence of silent
    /// truncation, which is the failure mode that reads exactly like a valid
    /// answer. Callers should compare and say so.
    ///
    /// Zero means the load command is absent (some cache images), not that the
    /// binary has no functions — an absent oracle proves nothing either way.
    public func declaredFunctionCount(in machO: MachOFile) -> Int {
        functionStarts(of: machO).count
    }

    /// LC_FUNCTION_STARTS as dyld reads it: deltas from `__TEXT`'s address,
    /// ending at the first zero. MachOKit's iterator reads past it, through
    /// the zero padding, each zero another start at the previous address. In
    /// an image that lists starts that only repeats the last one, but an
    /// image with none (`nocode.c`: no code, an 8-byte list of zeros)
    /// came back with one start at `__TEXT`'s base, which is the Mach-O
    /// header: a whole decode found no instruction where that start promised
    /// a function and threw `parsedNothing`, "a parser defect, not an empty
    /// binary", for a binary that is empty.
    static func linkerFunctionStarts(of machO: MachOFile) -> [UInt64] {
        guard let starts = machO.functionStarts else { return [] }
        var previous = machO.segments.first { $0.segmentName == "__TEXT" }.map { UInt64($0.virtualMemoryAddress) }
        var addresses: [UInt64] = []
        for entry in starts {
            let address = UInt64(entry.offset)
            if address == previous { break }
            addresses.append(address)
            previous = address
        }
        return addresses
    }

    /// VM addresses of every function start from LC_FUNCTION_STARTS, **deduped**.
    ///
    /// The load command is a ULEB128 list of *deltas*, zero-padded to alignment.
    /// Each padding byte decodes as a delta of zero, which reads as "another
    /// function at the same address as the last one", so the raw list ends in a
    /// run of repeats. Measured on the fixtures: 453 raw vs 449 distinct, 182 vs
    /// 176, 172 vs 171 — and the distinct count matches `dyld_info
    /// -function_starts` exactly in every case.
    ///
    /// This matters because the count is used as the **oracle** for recovery
    /// completeness (`declaredFunctionCount`), so an inflated denominator makes
    /// the coverage warning compare against a number the binary does not
    /// actually declare and prints a wrong figure in the `parsedNothing`
    /// diagnostic. The boundary callers were always unaffected — they wrap this
    /// in a `Set` — so deduping here changes counts only.
    ///
    /// A Go image adds its runtime's function table (`GoFunctionTable`),
    /// which its internal linker writes in place of LC_FUNCTION_STARTS.
    func functionStarts(of machO: MachOFile) -> [UInt64] {
        var seen: Set<UInt64> = []
        var starts = Self.linkerFunctionStarts(of: machO).filter { seen.insert($0).inserted }
        for entry in goFunctions(in: machO)?.entries ?? [] where seen.insert(entry.address).inserted {
            starts.append(entry.address)
        }
        return starts
    }

    /// The image's Go function table, read once per run.
    func goFunctions(in machO: MachOFile) -> GoFunctionTable? {
        let key = "\(machO.url.path)#\(machO.headerStartOffset)#\(machO.headerStartOffsetInCache)"
        return goFunctionCache.value(for: key) {
            GoFunctionTable.read(machO) { self.sectionBytes(address: $0, size: $1, in: machO) }
        }
    }

    /// Names from the Go function table, spelled as the symbol table of an
    /// unstripped Go image spells them (`_main.scale`), for addresses no
    /// symbol names.
    private func goLabels(in machO: MachOFile, adding labels: inout [UInt64: String]) {
        for entry in goFunctions(in: machO)?.entries ?? [] where labels[entry.address] == nil {
            labels[entry.address] = "_" + entry.name
        }
    }

    /// objdump's instruction stream and symbol labels. Its text (gigabytes on a
    /// large app) is released on return, before the Capstone decode.
    ///
    /// An empty parse is cross-checked against independent binary evidence
    /// before it is believed. `LC_FUNCTION_STARTS` is emitted by the linker and
    /// survives stripping, so it is an oracle the disassembler cannot talk
    /// itself out of. Returning [] here unconditionally is what let a
    /// leading-whitespace parse bug masquerade as "no functions" on every
    /// low-based dylib.
    /// The first line in which llvm-objdump says the input itself is wrong:
    /// a range or bounds complaint, or an error or warning line. Nil when it
    /// said nothing of the kind.
    static func objdumpComplaint(stdout: String, stderr: String) -> String? {
        let lines = (stderr + "\n" + stdout).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { line in
            let lower = line.lowercased()
            return lower.contains("outside valid range") || lower.contains("truncated") || lower.contains("malformed")
                || lower.hasPrefix("error") || lower.hasPrefix("warning") || lower.contains(": error:")
                || lower.contains(": warning:")
        }
    }

    private func objdumpInstructions(
        _ args: [String], machO: MachOFile
    ) throws -> (instructions: [Instruction], labels: [UInt64: String]) {
        let result = try Shell.xcrun("llvm-objdump", args)
        guard result.status == 0 else {
            throw DisassembleError.toolFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        var (parsed, labelByAddress) = parseObjdump(result.stdout)
        // Sections named with `--section` follow `__text` in the listing.
        if zip(parsed, parsed.dropFirst()).contains(where: { $0.address >= $1.address }) {
            parsed.sort { $0.address < $1.address }
        }
        if parsed.isEmpty {
            let knownStarts = functionStarts(of: machO).count
            guard knownStarts == 0 else {
                throw DisassembleError.parsedNothing(
                    lines: result.stdout.split(separator: "\n").count,
                    knownStarts: knownStarts,
                    toolReport: Self.objdumpComplaint(stdout: result.stdout, stderr: result.stderr)
                )
            }
        }
        return (parsed, labelByAddress)
    }

    /// Attach Capstone's control-flow class, branch target and detail to each
    /// objdump instruction at an address Capstone decoded.
    ///
    /// Capstone's output is strictly ascending, so a binary search finds each
    /// address; an address-keyed dictionary over the whole image held a
    /// second copy of every decoded instruction (Fiery Feeds: 3.2 GB before
    /// the decode, past 7.8 GB two seconds into it). The text is objdump's,
    /// so Capstone's is not built.
    private func attachCapstoneControlFlow(to instructions: inout [Instruction], in machO: MachOFile) {
        let decoded = decodeText(in: machO, span: nil, includeText: false)
        for index in instructions.indices {
            let insn = instructions[index]
            var low = 0, high = decoded.count
            while low < high {
                let mid = (low + high) / 2
                if decoded[mid].address < insn.address { low = mid + 1 } else { high = mid }
            }
            guard low < decoded.count, decoded[low].address == insn.address else {
                Probe.record(.decodeUnmatched, at: insn.address, ["text": .name(insn.text)])
                continue
            }
            let match = decoded[low]
            instructions[index] = Instruction(
                address: insn.address, text: insn.text, annotation: insn.annotation,
                controlFlow: match.controlFlow, branchTarget: match.branchTarget,
                detail: match.detail
            )
        }
    }

    /// The `[start, stop)` ranges of every function whose raw symbol or demangled
    /// name contains `filter` — computed *without* disassembling (from
    /// `LC_FUNCTION_STARTS`, the symbol table, and Swift-metadata names).
    /// Adjacent matches (gap < 64 KB) are coalesced so a cluster is one decode.
    /// A filtered disasm decodes only these ranges instead of all of `__text`.
    /// The `[start, stop)` spans of the functions `instructions` call directly
    /// (by `bl`, or a tail `b`, to a known function boundary) that `covered` does not already
    /// include. One level only: the callee facts a caller's analysis needs are
    /// about the callee's own body, not the callee's callees.
    private func calleeRanges(
        of instructions: [Instruction],
        excluding covered: [(start: UInt64, stop: UInt64)],
        in machO: MachOFile,
        objcIndex: ObjCMetadataIndex
    ) -> [(start: UInt64, stop: UInt64)] {
        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(symbolLabels(in: machO).keys)
        boundarySet.formUnion(objcIndex.addresses)
        let boundaries = boundarySet.sorted()
        let sections = codeSections(in: machO)
        var targets = Set<UInt64>()
        // A tail branch to a function start is a call too: its callee's body
        // bounds the arguments it renders (`b bump` after `printf`).
        for insn in instructions where insn.controlFlow == .call || insn.controlFlow == .branch {
            guard let target = insn.branchTarget, boundarySet.contains(target),
                  CodeSection.containing(target, in: sections) != nil,
                  !covered.contains(where: { $0.start <= target && target < $0.stop })
            else { continue }
            targets.insert(target)
        }
        return targets.sorted().map { start in
            let end = CodeSection.containing(start, in: sections)!.range.upperBound
            let next = boundaries.firstIndex(of: start).map { $0 + 1 }
            let stop = min(next.flatMap { $0 < boundaries.count ? boundaries[$0] : nil } ?? end, end)
            return (start, stop)
        }
    }

    private func matchedRanges(
        filter: String,
        in machO: MachOFile,
        objcIndex: ObjCMetadataIndex
    ) async -> [(start: UInt64, stop: UInt64)] {
        let needle = filter.lowercased()
        let labels = symbolLabels(in: machO)
        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(labels.keys)
        boundarySet.formUnion(objcIndex.addresses)
        let boundaries = boundarySet.sorted()
        guard !boundaries.isEmpty else { return [] }

        // Metadata names, on the same gate `assemble` uses, so a match against a
        // metadata-named (stripped) function still finds its range.
        let unlabeled = boundarySet.subtracting(labels.keys)
        var metadataNames: [UInt64: String] = [:]
        if Double(unlabeled.count) > Double(max(boundarySet.count, 1)) * 0.25 {
            metadataNames = MetadataSymbolizer().functionNames(in: machO).unique
        }
        metadataNames.merge(recognizedHelperNames(in: machO, boundaries: boundaries, labels: labels)) { a, _ in a }

        let sections = codeSections(in: machO)

        // Async funclet chains, decoded from the funclets' own spans only. A
        // nameless resume funclet is matched by the title it will be given
        // (`resume #N of <parent>`), and a matched async function brings its
        // whole chain: the resume funclets are the rest of its body.
        let stubNames = symbolStubNames(in: machO)
        func nameOf(_ address: UInt64) -> String? {
            labels[address].flatMap { self.demangle($0) } ?? metadataNames[address] ?? stubNames[address]
        }
        let asyncIndex = asyncFuncletIndex(
            in: machO, boundaries: boundarySet,
            instructions: { self.decodeFunction(at: $0, boundaries: boundaries, in: machO) },
            nameOf: nameOf
        )

        let folded = foldedSymbolAddresses(in: machO)
        // Matching demangles every label and folded symbol, one at a time: 57%
        // of a 47 s filtered query on a 3.7M-instruction app. Demangling is a
        // pure function of the symbol and the cache is thread-safe, so the
        // cache is filled across the cores first; the match below reads it.
        let symbols = Array(Set(labels.values).union(folded.values.joined()))
        Parallel.forEach(symbols) { _ = self.demangle($0) }
        func matches(_ start: UInt64) -> Bool {
            let symbol = labels[start] ?? "sub_\(String(start, radix: 16))"
            if symbol.lowercased().contains(needle) { return true }
            if (folded[start] ?? []).contains(where: { candidate in
                candidate.lowercased().contains(needle)
                    || (demangle(candidate).map { matchesName($0, needle: needle) } ?? false)
            }) {
                return true
            }
            if let objc = objcIndex.binding(for: start),
               objc.displayName.lowercased().contains(needle)
                || objc.signature.lowercased().contains(needle)
                || objc.typeEncoding.lowercased().contains(needle) {
                return true
            }
            let demangled = labels[start].flatMap { demangle($0) } ?? metadataNames[start]
            if demangled.map({ matchesName($0, needle: needle) }) == true { return true }
            if labels[start] == nil, metadataNames[start] == nil,
               let info = asyncIndex.info(for: start, parentName: nameOf),
               !info.isEntry, let parentName = info.parentName {
                return "resume #\(info.ordinal) of \(parentName)".lowercased().contains(needle)
            }
            return false
        }

        var selected: Set<UInt64>
        if let address = Self.filterAddress(needle) {
            // The function whose span holds the address.
            guard let index = boundaries.lastIndex(where: { $0 <= address }),
                  let end = CodeSection.containing(boundaries[index], in: sections)?.range.upperBound,
                  address < min(index + 1 < boundaries.count ? boundaries[index + 1] : end, end)
            else { return [] }
            selected = [boundaries[index]]
        } else {
            selected = Set(boundaries.filter(matches))
        }
        guard !selected.isEmpty else { return [] }
        for start in selected {
            if let chain = asyncIndex.chains[start] { selected.formUnion(chain) }
        }

        var ranges: [(start: UInt64, stop: UInt64)] = []
        for (index, start) in boundaries.enumerated() where selected.contains(start) {
            guard let end = CodeSection.containing(start, in: sections)?.range.upperBound else { continue }
            let stop = min(index + 1 < boundaries.count ? boundaries[index + 1] : end, end)
            if let last = ranges.last, start <= last.stop + 0x10000 {
                ranges[ranges.count - 1].stop = max(last.stop, stop)
            } else {
                ranges.append((start, stop))
            }
        }
        return ranges
    }

    // MARK: - Operand reference resolution

    /// Known target addresses → display names: every recovered function start,
    /// imported/ObjC selector stubs, and Swift type descriptors. Used to resolve
    /// adrp/add operand targets and to name direct call/tail-call targets.
    private func referenceIndex(
        functions: [DisassembledFunction],
        labelByAddress: [UInt64: String],
        metadataNames: [UInt64: String],
        objcIndex: ObjCMetadataIndex,
        foldedByAddress: [UInt64: [String]],
        foldSuspects: [UInt64: [String]],
        in machO: MachOFile
    ) -> [UInt64: String] {
        var names: [UInt64: String] = [:]
        // Keep the whole image's lightweight symbol/metadata index even when a
        // filtered disassembly decoded only one function. Its direct and
        // indirect calls can still target any other known function.
        //
        // A folded address is named as its heading is, `sub_<addr>`: every
        // symbol there is correct for at most one of the folded functions, and
        // a call names its callee from here and lays out its arguments from
        // that callee's signature. `callPair()`, which is
        // `pairPlus((3, 2.5), 4)`, rendered as a call to whichever symbol the
        // table listed, and `b.plus(6)` lost `self` to `pairPlus`'s layout.
        // The address stays a named target, so every call graph edge survives.
        // A consumer that knows the owner it reached the address through
        // picks from `foldedCandidates` instead: a vtable dispatch on self
        // (`name(at:ownedBy:)`) or a load from a conformance's witness
        // table (`witnessName(at:loadedFrom:)`). Candidates that all
        // demangle to one name name the same function, so that name stands;
        // so does a bound ObjC IMP, as in `makeFunction`.
        for (address, symbol) in labelByAddress {
            names[address] = objcIndex.binding(for: address)?.displayName
                ?? demangle(symbol)
                ?? Self.stripLeadingUnderscore(symbol)
        }
        for (address, name) in metadataNames where names[address] == nil {
            names[address] = name
        }
        for (address, candidates) in foldedByAddress where objcIndex.binding(for: address) == nil {
            if let name = Self.foldedTargetName(at: address, candidates: candidates, demangle: { self.demangle($0) }) {
                names[address] = name
            }
        }
        // A body short enough to be shared keeps its heading, which is true
        // of the body, but a reference does not know which function it meant.
        for address in foldSuspects.keys {
            names[address] = "sub_\(String(address, radix: 16))"
        }
        for address in objcIndex.addresses where names[address] == nil {
            names[address] = objcIndex.binding(for: address)?.displayName
        }
        for function in functions where names[function.startAddress] == nil {
            names[function.startAddress] = function.analysisDisplayName
        }
        for (address, name) in symbolStubNames(in: machO) where names[address] == nil {
            names[address] = name
        }
        // Selector stubs live in __objc_stubs, outside __text, so they are never
        // recovered as functions — without this every message send is a call to
        // an unnamed address.
        for (address, name) in objcStubNames(in: machO) where names[address] == nil {
            names[address] = name
        }
        for type in UnrecordedTypes.all(in: machO) {
            let offset: Int
            let name: String?
            switch type {
            case .enum(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            case .struct(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            case .class(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            }
            if let name, let address = machO.imageAddress(ofOffset: offset) {
                names[address] = "type descriptor for \(name)"
            }
        }
        return names
    }

    /// Walk a function's instructions tracking `adrp` page registers, and when a
    /// following `add`/`ldr` forms a concrete target, annotate it (if objdump
    /// left it bare) with a resolved name.
    private func annotateReferences(
        in function: DisassembledFunction,
        resolver: ReferenceResolver
    ) -> DisassembledFunction {
        var pageByRegister: [String: UInt64] = [:]
        var updated: [Instruction] = []
        updated.reserveCapacity(function.instructions.count)

        for insn in function.instructions {
            if let (register, page) = parseAdrp(insn.text) {
                pageByRegister[register] = page
                updated.append(insn)
                continue
            }

            // Only annotate operands objdump left without a comment of its own.
            if insn.annotation == nil, !insn.text.contains(";"),
               let (base, immediate) = parsePageOffset(insn.text),
               let page = pageByRegister[base],
               let name = resolver.reference(at: page &+ immediate) {
                updated.append(Instruction(
                    address: insn.address, text: insn.text, annotation: name,
                    controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                    detail: insn.detail
                ))
            } else {
                updated.append(insn)
            }

            // The written (first-operand) register no longer holds an adrp page.
            // Clearing it keeps a stale page from being reused on a later op
            // (conservative: at worst we miss an annotation, never invent one).
            if let written = firstRegister(insn.text) {
                pageByRegister[written] = nil
            }
        }

        return function.replacingInstructionPayload(updated)
    }

    /// Annotate direct call/branch instructions with their resolved target
    /// name (`→ Type.method`). objdump already names file-mode calls in the
    /// instruction text (via stubs); this fills the in-process (Capstone) path,
    /// where the operand is a bare `#0x…` address — so calls to another function
    /// in the same image read by name and flow into `--pseudo`.
    /// A `b` to the function's own entry is the edge of a loop the CFG
    /// already draws, not a call: Go's stack-growth prologue (`cmp sp, x16;
    /// b.ls` to `bl runtime.morestack_noctxt; b main.main`) rendered as
    /// `while (sp <=ᵁ x16) { runtime.morestack_noctxt(); main.main() }`,
    /// the loop and a call for one branch. The branch keeps its target and
    /// loses only the callee.
    static func droppingSelfBranchCallees(_ function: DisassembledFunction) -> DisassembledFunction {
        guard function.instructions.contains(where: {
            $0.controlFlow == .branch && $0.branchTarget == function.startAddress && $0.callee != nil
        }) else { return function }
        return function.replacingInstructionPayload(function.instructions.map { insn in
            guard insn.controlFlow == .branch, insn.branchTarget == function.startAddress, insn.callee != nil
            else { return insn }
            return Instruction(
                address: insn.address, text: insn.text, annotation: insn.annotation,
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                callArguments: insn.callArguments, callSelf: insn.callSelf,
                resultConsumed: insn.resultConsumed, sourceType: insn.sourceType,
                detail: insn.detail, callee: .kept(nil), facts: insn.facts
            )
        })
    }

    private func annotateCallTargets(
        in function: DisassembledFunction,
        resolver: ReferenceResolver
    ) -> DisassembledFunction {
        let branchFlows: Set<ControlFlow> = [.call, .branch, .conditionalBranch]
        let instructions = function.instructions.map { insn -> Instruction in
            // objdump names a folded target after one of its symbols, in the
            // text and the annotation it demangled from it. The address takes
            // its heading's name on both front-ends.
            if let flow = insn.controlFlow, branchFlows.contains(flow),
               let target = insn.branchTarget, let name = resolver.declinedFoldName(at: target) {
                var text = insn.text
                for symbol in resolver.foldedCandidates[target] ?? [] {
                    text = text.replacingOccurrences(of: symbol, with: "0x\(String(target, radix: 16))")
                }
                return Instruction(
                    address: insn.address, text: text, annotation: "→ \(name)",
                    controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                    callArguments: insn.callArguments, detail: insn.detail,
                    callee: .kept(name)
                )
            }
            // objdump numbers a stub section by its header's stub size, which
            // Go's linker writes as 6 for 12-byte stubs, so its `symbol stub
            // for:` named `clock_gettime`'s stub `_fcntl`. The stub table
            // reads the stride from the stubs (`stubStride`); where the two
            // disagree on a C import, the table's name stands, in the text
            // too, so no later parse of it reads objdump's.
            if let flow = insn.controlFlow, branchFlows.contains(flow), let target = insn.branchTarget,
               let range = insn.text.range(of: "symbol stub for: "),
               let name = resolver.callTargetName(at: target) {
                let raw = String(insn.text[range.upperBound...].prefix { !$0.isWhitespace && $0 != ";" })
                let bare = raw.hasPrefix("_") ? String(raw.dropFirst()) : raw
                if !Self.isSwiftMangled(raw), !name.isEmpty, bare != name {
                    return Instruction(
                        address: insn.address, text: insn.text.replacingOccurrences(of: raw, with: "_" + name),
                        annotation: insn.annotation, controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                        callArguments: insn.callArguments, detail: insn.detail, callee: .kept(name)
                    )
                }
            }
            // Only name calls not already annotated — objdump's file-mode calls
            // carry their name in-text; this fills the bare-address in-process path.
            guard insn.annotation == nil,
                  let flow = insn.controlFlow, branchFlows.contains(flow),
                  let target = insn.branchTarget,
                  let name = resolver.callTargetName(at: target)
            else { return insn }
            let annotation = "→ \(name)"
            // The fact is the name this pass resolved, shared rather than
            // copied, whenever the annotation reads back as it.
            let parsed = DisassembledFunction.parsedCalleeName(text: insn.text, annotation: annotation)
            return Instruction(
                address: insn.address, text: insn.text, annotation: annotation,
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                callArguments: insn.callArguments, detail: insn.detail,
                callee: .kept(parsed == name ? name : parsed)
            )
        }
        let qualified = instructions.map { insn -> Instruction in
            guard let flow = insn.controlFlow, branchFlows.contains(flow),
                  let callee = DisassembledFunction.calleeName(of: insn),
                  DisassembledFunction.isARCReferenceHelper(callee) else { return insn }
            var facts = insn.facts
            facts.arcIdentityContract = insn.branchTarget.map {
                resolver.arcIdentityContract(at: $0, named: callee)
            } ?? false
            return Instruction(address: insn.address, text: insn.text, annotation: insn.annotation,
                               controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                               callArguments: insn.callArguments, callSelf: insn.callSelf,
                               resultConsumed: insn.resultConsumed, sourceType: insn.sourceType,
                               detail: insn.detail, calleeDisplayName: insn.calleeDisplayName,
                               callee: .kept(insn.callee), facts: facts)
        }
        // A span with no instruction (a Go data span) is no body to share.
        let suspect = function.source == .foldedSymbols || function.instructions.isEmpty
            || resolver.declinedFoldName(at: function.startAddress) == nil
            ? nil : resolver.foldedCandidates[function.startAddress]
        if let suspect { return function.replacingInstructions(qualified, foldedCandidates: suspect) }
        return function.replacingInstructionPayload(qualified)
    }

    /// Resolve register-indirect calls only when value tracking proves the
    /// register came from a concrete address or pointer slot and that target is
    /// a known function. This covers concrete vtable/witness-table dispatch and
    /// GOT-loaded function pointers while leaving genuinely dynamic generic or
    /// block dispatch unresolved.
    private func annotateIndirectControlFlowTargets(
        in function: DisassembledFunction,
        targets: [UInt64: AbstractValue],
        resolver: ReferenceResolver,
        selfTypeName: String? = nil,
        vtableIndex: VTableIndex = VTableIndex(),
        callArguments: [UInt64: [AbstractValue]] = [:],
        selfFieldClass: (Int) -> String? = { _ in nil },
        argumentClass: (Int) -> String? = { _ in nil },
        argumentFieldClass: (Int, Int) -> String? = { _, _ in nil },
        argumentType: (Int) -> String? = { _ in nil }
    ) -> (function: DisassembledFunction, changesCFG: Bool) {
        /// Resolve a `blr` target to a (name, address). A class vtable dispatch is
        /// resolved through the class's metadata layout; anything else through the
        /// generic indirect-target resolver.
        // A generic function's protocol requirements, read once, only when a
        // call goes through one of its witness tables.
        let genericRequirements = targets.values.contains(where: {
            if case .loadedFrom(.genericWitnessTable, _) = $0 { true } else { false }
        }) ? Self.genericProtocolRequirements(of: function) : nil
        func resolve(_ value: AbstractValue, site: UInt64) -> (address: UInt64?, name: String, isSelfDispatch: Bool)? {
            if case .selfVTableMethod(let offset) = value,
               let selfTypeName,
               let address = vtableIndex.methodAddress(type: selfTypeName, offset: offset),
               let name = resolver.name(at: address, ownedBy: selfTypeName) {
                return (address, Self.namingItsProperty(name, ownedBy: selfTypeName), true)
            }
            if let dispatch = fieldVTableMethod(value) { return (dispatch.address, dispatch.name, false) }
            if let witness = existentialWitnessCall(value, site: site) { return (nil, witness, false) }
            if let witness = valueWitnessCall(value, site: site) { return (nil, witness, false) }
            if let witness = protocolWitnessCall(value, site: site) { return (nil, witness.name, false) }
            return resolver.indirectCallTarget(for: value).map { ($0.address, $0.name, false) }
        }
        /// A class method called on an object held in a stored field of
        /// `self`: `ldr x20, [x20, #k]; ldr x8, [x20]; ldr x8, [x8, #slot];
        /// blr x8`. The object is an instance of the field's declared class
        /// or a subclass, and a subclass keeps the slot for the method it
        /// overrides, so the slot names the declared class's method there.
        /// Only a slot the class's own vtable lists, and only when that
        /// implementation's demangled owner is the field's declared type:
        /// `VTableIndex` is keyed by simple name, and another module's class
        /// of the same name must not match.
        /// A call through word `k` of an opaque existential argument's
        /// witness table: `ldp x19, x21, [x0, #0x18]` (its metadata and
        /// table), `ldr x8, [x21, #k]`, the projected value in x20, and the
        /// metadata and table passed last. The parameter's printed type must
        /// be a protocol this image declares with an opaque existential, and
        /// the call must hand on that same metadata and table, as a witness
        /// takes them. Named `<requirement> witness for argN` from the
        /// protocol's descriptor.
        func existentialWitnessCall(_ value: AbstractValue, site: UInt64) -> String? {
            if let name = classBoundExistentialWitnessCall(value, site: site) { return name }
            guard case .loadedFrom(.loadedFrom(.argument(let argument), offset: 0x20), let offset) = value,
                  offset >= 8, offset % 8 == 0,
                  let type = argumentType(argument),
                  let descriptor = resolver.opaqueExistentialDescriptor(named: type),
                  let arguments = callArguments[site], arguments.count >= 2,
                  arguments[arguments.count - 1] == .loadedFrom(.argument(argument), offset: 0x20),
                  arguments[arguments.count - 2] == .loadedFrom(.argument(argument), offset: 0x18)
            else { return nil }
            if let requirement = resolver.protocolRequirement(descriptor: descriptor, word: offset / 8) {
                return "\(requirement.name) witness for arg\(argument)"
            }
            if let shape = resolver.protocolRequirementShape(descriptor: descriptor, word: offset / 8) {
                return "\(shape.protocolName) requirement \(shape.index) (\(shape.kind)) witness for arg\(argument)"
            }
            return nil
        }
        /// A call through word `k` of a class-bound existential argument's
        /// witness table (`any Named`, the object in xN and the table in
        /// xN+1): the call must pass `swift_getObjectType(object)` and that
        /// table last, as a witness on a class-bound existential takes them.
        func classBoundExistentialWitnessCall(_ value: AbstractValue, site: UInt64) -> String? {
            guard case .loadedFrom(.existentialWitnessTable(let argument), let offset) = value,
                  offset >= 8, offset % 8 == 0,
                  let type = argumentType(argument),
                  let descriptor = resolver.classBoundExistentialDescriptor(named: type),
                  let arguments = callArguments[site], arguments.count >= 2,
                  arguments[arguments.count - 1] == .existentialWitnessTable(argument: argument),
                  case .callResult(let typeSite) = arguments[arguments.count - 2],
                  let typeCall = function.instructions.first(where: { $0.address == typeSite }),
                  DisassembledFunction.calleeName(of: typeCall) == "swift_getObjectType",
                  callArguments[typeSite]?.first == .argument(argument)
            else { return nil }
            if let requirement = resolver.protocolRequirement(descriptor: descriptor, word: offset / 8) {
                return "\(requirement.name) witness for arg\(argument)"
            }
            if let shape = resolver.protocolRequirementShape(descriptor: descriptor, word: offset / 8) {
                return "\(shape.protocolName) requirement \(shape.index) (\(shape.kind)) witness for arg\(argument)"
            }
            return nil
        }
        /// A call's result has its callee's declared result type: x0 of a
        /// call whose demangled signature returns a plain class (or an
        /// Optional of one, which the dispatch only reaches non-nil). Not a
        /// specialization, whose printed signature can be its original's, and
        /// not an async callee, whose result is not x0 at the call.
        func callResultClass(_ site: UInt64) -> String? {
            guard let call = function.instructions.first(where: { $0.address == site }),
                  call.controlFlow == .call,
                  let name = DisassembledFunction.calleeName(of: call),
                  !name.contains("specialization"),
                  let signature = DisassembledFunction.splitSignature(name), !signature.isAsync
            else { return nil }
            return Self.plainNominalName(signature.result)
        }
        /// A class parameter of a free function is the same: its declared
        /// type, exactly as the signature prints it (`classArguments`).
        func fieldVTableMethod(_ value: AbstractValue) -> (address: UInt64, name: String)? {
            let receiverClass: String?, slot: Int
            switch value {
            case .loadedFrom(.loadedFrom(.selfFieldValue(let field), offset: 0), offset: let offset):
                receiverClass = selfFieldClass(field); slot = offset
            case .loadedFrom(.loadedFrom(.argument(let argument), offset: 0), offset: let offset):
                receiverClass = argumentClass(argument); slot = offset
            case .loadedFrom(.loadedFrom(.argumentField(let argument, let field), offset: 0), offset: let offset):
                receiverClass = argumentFieldClass(argument, field); slot = offset
            case .loadedFrom(.loadedFrom(.callResult(let site), offset: 0), offset: let offset):
                receiverClass = callResultClass(site); slot = offset
            default:
                return nil
            }
            guard slot >= 0, slot % 8 == 0,
                  let owner = receiverClass,
                  let simple = owner.split(separator: ".").last.map(String.init),
                  let address = vtableIndex.methodAddress(type: simple, offset: slot),
                  let name = resolver.name(at: address, ownedBy: simple),
                  name.hasPrefix(owner + ".")
            else { return nil }
            return (address, name)
        }
        /// A call through word `k` of a witness table that is one of the key
        /// arguments in `self`'s class metadata: `ldr x22, [x20]; ldr x1,
        /// [x22, #0x58]; ldr x8, [x1, #8]; blr x8` in a method of `Gauge<M:
        /// Meter>` calls Meter's requirement 0 on M. Named `<requirement>
        /// witness for <parameter>`, with the requirement's signature for
        /// laying out the call, only when the table's protocol and the
        /// slot's requirement are both proven.
        func protocolWitnessCall(_ value: AbstractValue, site: UInt64) -> (name: String, signature: String?)? {
            if case .loadedFrom(.genericWitnessTable(let index), let offset) = value {
                return genericWitnessCall(table: index, offset: offset).map { ($0.name, $0.signature) }
            }
            // A table `swift_conformsToProtocol(T, protocol descriptor)`
            // returned (include/swift/Runtime/Metadata.h): word k is the
            // protocol's requirement k - 1. A witness takes Self's metadata
            // and Self's table as its last two arguments
            // (lib/IRGen/GenProto.cpp, expandTrailingWitnessSignature), so
            // the call is one only when it passes this table last and T
            // just before it. Named by the requirement's method descriptor
            // where the image keeps it, else by the protocol and the
            // requirement's index and kind, which the descriptor holds.
            if case .loadedFrom(.callResult(let tableSite), let offset) = value, offset >= 8, offset % 8 == 0,
               let tableCall = function.instructions.first(where: { $0.address == tableSite }),
               DisassembledFunction.calleeName(of: tableCall)?.hasPrefix("swift_conformsToProtocol") == true,
               let lookup = callArguments[tableSite], lookup.count >= 2, case .address(let descriptor) = lookup[1],
               lookup[0] != .unknown,
               let arguments = callArguments[site], arguments.count >= 2,
               arguments[arguments.count - 1] == .callResult(tableSite), arguments[arguments.count - 2] == lookup[0] {
                let subject = conformingTypeSpelling(lookup[0])
                if let requirement = resolver.protocolRequirement(descriptor: descriptor, word: offset / 8) {
                    return ("\(requirement.name) witness for \(subject)", requirement.signature)
                }
                if let shape = resolver.protocolRequirementShape(descriptor: descriptor, word: offset / 8) {
                    return ("\(shape.protocolName) requirement \(shape.index) (\(shape.kind)) witness for \(subject)", nil)
                }
                return nil
            }
            guard case .loadedFrom(.selfVTableMethod(let tableOffset), let offset) = value,
                  offset >= 8, offset % 8 == 0, let selfTypeName,
                  let table = vtableIndex.witnessTable(type: selfTypeName, offset: tableOffset),
                  let requirement = resolver.protocolRequirement(descriptor: table.protocolDescriptor, word: offset / 8)
            else { return nil }
            return ("\(requirement.name) witness for \(table.parameter)", requirement.signature)
        }
        /// A call through word `k` of the witness table a generic function
        /// received for its protocol requirement `table`: `feed<A where A:
        /// M.Sink>(A, Int)` takes A's Sink table in x3, and `ldr x8, [x3,
        /// #8]; blr x8` calls Sink's requirement 0 on A. Its register assumed
        /// a table for every protocol requirement before it
        /// (`genericWitnessTableRegisters`); each of those, and this one, must
        /// be a protocol with a descriptor in this image, which only a Swift
        /// protocol that needs a table has (an `@objc` or marker protocol has
        /// none). The table must be for a parameter, not a member type.
        func genericWitnessCall(table: Int, offset: Int) -> (name: String, signature: String)? {
            guard offset >= 8, offset % 8 == 0,
                  let requirements = genericRequirements?.requirements, table < requirements.count,
                  let subject = requirements[table].subject
            else { return nil }
            var descriptor: UInt64?
            for index in 0 ... table {
                guard let address = resolver.protocolDescriptor(named: requirements[index].protocolName) else { return nil }
                descriptor = address
            }
            guard let descriptor, let requirement = resolver.protocolRequirement(descriptor: descriptor, word: offset / 8)
            else { return nil }
            return ("\(requirement.name) witness for \(subject)", requirement.signature)
        }
        /// A call through slot `k` of the value-witness table of the
        /// metadata a type metadata accessor returned: `[[metadata - 8] +
        /// k]` (swift/include/swift/ABI/Metadata.h puts the table pointer
        /// just before the metadata; ValueWitness.def orders the slots).
        /// Only the eight function slots every table has; past them come
        /// the size, stride and flags.
        /// The name a descriptor argument has: a GOT slot the loader binds
        /// (`associated type descriptor for Swift.Sequence.Element`) or a
        /// symbol in this image. Nil when nothing names it.
        func descriptorName(_ value: AbstractValue) -> String? {
            switch value {
            case .loaded(let slot): return resolver.loadedName(at: slot)
            case .address(let address): return resolver.callTargetName(at: address)
            default: return nil
            }
        }
        /// A conforming type's metadata as a witness name spells it: a
        /// generic parameter, an argument, an accessor's type, else `?`.
        func conformingTypeSpelling(_ value: AbstractValue) -> String {
            switch value {
            case .genericMetadata(let name): return name
            case .argument(let index): return "arg\(index)"
            case .callResult(let site):
                let prefix = "type metadata accessor for "
                if let call = function.instructions.first(where: { $0.address == site }),
                   let callee = DisassembledFunction.calleeName(of: call), callee.hasPrefix(prefix), callee.count > prefix.count {
                    return String(callee.dropFirst(prefix.count))
                }
                return "?"
            default: return "?"
            }
        }
        func valueWitnessCall(_ value: AbstractValue, site: UInt64) -> String? {
            let callSite = site
            /// The witness at `offset` in a value-witness table: one of the
            /// eight every table has, or an enum's three after its size,
            /// stride, flags and extra inhabitant count (`+0x58`, ValueWitness.def).
            /// An enum slot exists only in an enum's table, so it is named
            /// only when the call passes the metadata it was loaded through
            /// where the witness takes its metadata, its last parameter.
            func slotName(_ offset: Int, metadata: AbstractValue) -> String? {
                guard offset >= 0, offset % 8 == 0 else { return nil }
                if offset / 8 < MetadataSymbolizer.valueWitnessNames.count {
                    return MetadataSymbolizer.valueWitnessNames[offset / 8]
                }
                guard offset >= 0x58, (offset - 0x58) / 8 < MetadataSymbolizer.enumValueWitnessNames.count else { return nil }
                let name = MetadataSymbolizer.enumValueWitnessNames[(offset - 0x58) / 8]
                guard let arity = DisassembledFunction.valueWitnessArity[name],
                      let arguments = callArguments[callSite], arguments.count >= arity, arguments[arity - 1] == metadata
                else { return nil }
                return name
            }
            // Metadata loaded from a slot the loader fixes (a GOT or literal
            // pool entry bound to `type metadata for X`): `ldr x2, [x2,
            // #0x60]; ldur x8, [x2, #-0x8]; ldr x8, [x8, #k]; blr x8`.
            if case .loadedFrom(.loadedThrough(let slot, offset: -8), let offset) = value,
               let witness = slotName(offset, metadata: .loaded(slot)),
               // `loadedName` names only a slot the loader owns.
               let name = resolver.loadedName(at: slot), name.hasPrefix("type metadata for "),
               name.count > "type metadata for ".count {
                return "\(witness) value witness for \(name.dropFirst("type metadata for ".count))"
            }
            guard case .loadedFrom(.loadedFrom(let metadata, offset: -8), let offset) = value,
                  let slot = slotName(offset, metadata: metadata)
            else { return nil }
            // A generic parameter's metadata, as the function received it.
            if case .genericMetadata(let name) = metadata { return "\(slot) value witness for \(name)" }
            // An argument no signature types: a stripped generic function's
            // metadata is only an incoming register. `[[arg - 8] + k]` is a
            // value witness when the call passes that same argument where
            // the witness takes its metadata, its last parameter
            // (swift/include/swift/ABI/ValueWitness.def): `destroy(x, T)`,
            // `initializeWithCopy(dest, src, T)`. Named for the argument, as
            // it renders: no type is known.
            if case .argument(let index) = metadata {
                guard let arity = DisassembledFunction.valueWitnessArity[slot],
                      let arguments = callArguments[site], arguments.count >= arity,
                      arguments[arity - 1] == metadata
                else { return nil }
                return "\(slot) value witness for arg\(index)"
            }
            // The metadata in word 3 of the existential container an
            // argument points to (`ldr x2, [x0, #0x18]; ldur x8, [x2, #-8];
            // ldr x8, [x8]` in `outlined init with copy of M.Shape`), under
            // the same proof: the call passes it where the witness takes its
            // metadata. Named for where it was read, as no type is known.
            if case .loadedFrom(.argument(let index), offset: 0x18) = metadata {
                guard let arity = DisassembledFunction.valueWitnessArity[slot],
                      let arguments = callArguments[site], arguments.count >= arity,
                      arguments[arity - 1] == metadata
                else { return nil }
                return "\(slot) value witness for the metadata at arg\(index) + 0x18"
            }
            // A generic argument of `self`'s class, read from its isa:
            // `ldr x12, [x20]; ldr x23, [x12, #0x50]` in a method of
            // `LRUCache<A, B>`.
            if case .selfVTableMethod(let argument) = metadata, let selfTypeName,
               let parameter = vtableIndex.genericParameter(type: selfTypeName, offset: argument) {
                return "\(slot) value witness for \(parameter)"
            }
            guard case .callResult(let site) = metadata,
                  let call = function.instructions.first(where: { $0.address == site }),
                  let callee = DisassembledFunction.calleeName(of: call)
            else { return nil }
            let prefix = "type metadata accessor for "
            if callee.hasPrefix(prefix), callee.count > prefix.count {
                return "\(slot) value witness for \(callee.dropFirst(prefix.count))"
            }
            // An associated type's metadata: `swift_getAssociatedTypeWitness(
            // request, table, T, requirements base, associated type
            // descriptor)` returns T's witness for the associated type the
            // descriptor names (include/swift/Runtime/Metadata.h). Named
            // `<slot> value witness for T.Element` when the descriptor is
            // named and the call passes this metadata back as its last
            // argument; T is spelled as it renders, `?` when unknown.
            if callee == "swift_getAssociatedTypeWitness", let arguments = callArguments[site], arguments.count >= 5,
               let descriptor = descriptorName(arguments[4]),
               descriptor.hasPrefix("associated type descriptor for "),
               let associated = descriptor.split(separator: ".").last, !associated.contains(" "),
               let arity = DisassembledFunction.valueWitnessArity[slot],
               let witnessArguments = callArguments[callSite], witnessArguments.count >= arity,
               witnessArguments[arity - 1] == metadata {
                return "\(slot) value witness for \(conformingTypeSpelling(arguments[2])).\(associated)"
            }
            // The mangled-name metadata helpers fetch the type their cache
            // variable (V1) or name pair (V2) spells.
            let arguments = callArguments[site] ?? []
            if callee == "__swift_instantiateConcreteTypeFromMangledName", case .address(let cache)? = arguments.first,
               let type = MangledNamePair.typeName(atCacheVariable: cache, in: resolver.machO, fixups: resolver.chainedFixups) {
                return "\(slot) value witness for \(type)"
            }
            if callee == Self.mangledNameMetadataHelperName, arguments.count >= 2, case .address(let pair) = arguments[1],
               let type = MangledNamePair.typeName(at: pair, in: resolver.machO, fixups: resolver.chainedFixups) {
                return "\(slot) value witness for \(type)"
            }
            return nil
        }
        let ownAddresses = Set(function.instructions.map(\.address))
        var changesCFG = false
        let instructions = function.instructions.map { insn -> Instruction in
            guard insn.branchTarget == nil,
                  insn.controlFlow == .call || insn.controlFlow == .branch,
                  let value = targets[insn.address],
                  let resolved = resolve(value, site: insn.address)
            else { return insn }
            let named = resolved.name + (resolved.isSelfDispatch ? DisassembledFunction.selfDispatchMarker : "")
            let annotation = insn.annotation.map { "\($0)  → \(named)" } ?? "→ \(named)"
            let parsed = DisassembledFunction.parsedCalleeName(text: insn.text, annotation: annotation)
            // A `br` resolved to an address inside this function is a tail
            // call that happens to land here (`return countdown(n - 1)`
            // through self's vtable, which an override may own), not a jump:
            // as a branch target it became an edge, and the call a loop.
            let target = insn.controlFlow == .branch && resolved.address.map(ownAddresses.contains) == true
                ? nil : resolved.address
            if insn.controlFlow == .branch, target != insn.branchTarget { changesCFG = true }
            var facts = insn.facts
            facts.isSelfDispatch = resolved.isSelfDispatch
            facts.arcIdentityContract = resolver.arcIdentityContract(for: value, named: resolved.name)
            let protocolWitness = protocolWitnessCall(value, site: insn.address)
            if let witness = protocolWitness, witness.name == resolved.name, let signature = witness.signature {
                facts.witnessRequirement = signature
            }
            facts.isWitnessDispatch = resolved.address == nil
                && (protocolWitness?.name == resolved.name || valueWitnessCall(value, site: insn.address) == resolved.name)
            return Instruction(
                address: insn.address, text: insn.text, annotation: annotation,
                controlFlow: insn.controlFlow, branchTarget: target,
                callArguments: insn.callArguments, callSelf: insn.callSelf,
                resultConsumed: insn.resultConsumed, sourceType: insn.sourceType,
                detail: insn.detail, callee: .kept(parsed == named ? named : parsed), facts: facts
            )
        }
        return (function.replacingInstructions(instructions), changesCFG)
    }

    /// VM range of a named section, if present.
    private func sectionRange(named name: String, in machO: MachOFile) -> Range<UInt64>? {
        guard let section = machO.sections.first(where: { $0.sectionName == name && $0.size > 0 })
        else { return nil }
        let start = UInt64(section.address)
        return start ..< (start + UInt64(section.size))
    }

    /// VM address ranges of C-string-literal sections (`__cstring`,
    /// `__objc_methname`, …). Used to safely resolve string-pointer arguments.
    private func stringSectionRanges(in machO: MachOFile) -> [Range<UInt64>] {
        machO.sections.compactMap { section in
            guard section.flags.type == .cstring_literals, section.size > 0 else { return nil }
            let start = UInt64(section.address)
            return start ..< (start + UInt64(section.size))
        }
    }

    /// Resolves a target address to a display name: a known function/descriptor,
    /// a C-string literal (quoted, only inside cstring sections), or a demangled
    /// Swift mangled-name string. Never guesses at arbitrary data.
    struct ReferenceResolver {
        let names: [UInt64: String]
        let stringRanges: [Range<UInt64>]
        let machO: MachOFile
        let demangleSymbol: @Sendable (String) -> String?
        /// Selector names, by selref slot and by string address — the two ways a
        /// call site can name one.
        var selectors = SelectorTable()
        /// VM range of `__cfstring`, whose entries are the `@"…"` literals.
        var cfStringRange: Range<UInt64>?
        /// Cross-image export/stub resolver for dyld-cache pointer slots.
        var cacheSymbols: CacheSymbolResolver?
        /// Reads across dyld subcache files. A cache image's __AUTH_CONST — where
        /// its __cfstring lives — is usually in a *different* subcache than its
        /// header, so `machO.fileOffset(of:)` returns nil for those addresses and
        /// every read has to go through the full cache instead.
        var cacheReader: CacheReader?
        /// Import/export identity for ARC calls. Display names never supply it.
        var arcFunctions: [UInt64: RuntimeFunctionReference] = [:]
        /// File-backed byte ranges of a standalone image; nil inside a cache.
        var fileRanges: FileBackedRanges?
        /// Every name identical code folding put at an address (symbols or
        /// metadata candidates). `names` holds one of them; a consumer that knows
        /// which owner it reached the address through picks from these instead.
        var foldedCandidates: [UInt64: [String]] = [:]
        /// Every protocol witness table with a symbol: its extent (to the
        /// next symbol) and the conformance it is for.
        var witnessTables: [(range: Range<UInt64>, conformance: String)] = []
        /// Every protocol and method descriptor symbol, demangled, by address
        /// (`protocolRequirement(descriptor:word:)`).
        var protocolDescriptorSymbols: [UInt64: [String]] = [:]
        /// Loader-proven external entries, separate from presentation names.
        var importedStubFunctions: [UInt64: ImportedFunctionReference] = [:]
        /// The mangled symbol of each generic specialization in the image, by
        /// address, so a call to one can be laid out from its substituted
        /// signature (`specializedSignature`). An address the linker folded
        /// several symbols onto has none: the bodies of `bump<Int>` and
        /// `bump<UInt>` can be one, and the symbol there names either.
        var specializationSymbols: [UInt64: String] = [:]

        /// The substituted signature of the specialization a call to `target`
        /// names, when its symbol proves one.
        func specializedSignature(at target: UInt64, printedName: String) -> String? {
            guard let symbol = specializationSymbols[target] else { return nil }
            return DisassembledFunction.specializedSignature(symbol: symbol, printedName: printedName)
        }

        /// Preserve this reason separately from an ordinary nil: a fallback
        /// must not reinterpret a declined SIL index as positional arguments.
        func specializedSignatureProof(at target: UInt64, printedName: String) -> SpecializedSignatureProof {
            guard printedName.hasPrefix("generic specialization <"), let symbol = specializationSymbols[target]
            else { return .unavailable }
            return DisassembledFunction.specializedSignatureProof(symbol: symbol, printedName: printedName)
        }

        /// What the symbol at `target` proves about the printed name. A
        /// folded target has no symbol, so nothing beyond the name.
        func specializationClause(at target: UInt64, printedName: String) -> SpecializationClause {
            guard let symbol = specializationSymbols[target] else { return .absent }
            return DisassembledFunction.specializationClause(symbol: symbol, printedName: printedName)
        }

        /// The requirement a witness table of the protocol whose descriptor
        /// is at `descriptor` holds in word `word`: its printed signature
        /// (`M.P.scaled(by: Swift.Int) -> Swift.Int`, as its method
        /// descriptor's symbol demangles) and its name with argument labels
        /// only (`M.P.scaled(by:)`). Word 0 is the conformance descriptor
        /// and requirement N is word N+1 (WitnessTableFirstRequirementOffset,
        /// swift/include/swift/ABI/MetadataValues.h).
        ///
        /// The descriptor (swift/include/swift/ABI/Metadata.h,
        /// TargetProtocolDescriptor) is a 24-byte header (flags, parent, name,
        /// NumRequirementsInSignature, NumRequirements, associated type
        /// names), then 12 bytes per requirement-signature entry, then 8
        /// bytes per requirement (flags, default implementation). Declined:
        /// a cache image or an unreadable descriptor; a descriptor not of a
        /// protocol, or of a special one (Error; a COM protocol carries an
        /// interface ID before its requirements); a requirement past the
        /// count, or not a synchronous method, initializer, getter or setter
        /// (a base protocol or associated type, a coroutine, an async
        /// function whose slot holds a function pointer record); and any
        /// requirement whose address has no `method descriptor for` symbol
        /// naming a member of the protocol the descriptor's own symbol names.
        /// The address of the in-image descriptor of the protocol printed
        /// `name`: the one address whose only descriptor symbol is
        /// `protocol descriptor for <name>`.
        func protocolDescriptor(named name: String) -> UInt64? {
            let symbol = "protocol descriptor for " + name
            let addresses = protocolDescriptorSymbols.filter { $0.value.contains(symbol) }
            guard addresses.count == 1, let match = addresses.first, match.value.count == 1 else { return nil }
            return match.key
        }

        /// The protocol a descriptor in this image describes, and the index
        /// and kind of the requirement at witness-table `word`, read from
        /// the descriptor itself: a stripped image keeps no method
        /// descriptor to name the requirement, but the descriptor names its
        /// protocol and module (relative pointers at +8 and +4,
        /// TargetProtocolDescriptor) and each requirement's kind. The same
        /// declines as `protocolRequirement`, and a protocol nested in
        /// anything but a module.
        func protocolRequirementShape(descriptor: UInt64, word: Int) -> (protocolName: String, index: Int, kind: String)? {
            guard machO.cache == nil, word >= 1,
                  let base = machO.fileOffset(of: descriptor).map(Int.init),
                  let flags = UnrecordedTypes.read(base, as: UInt32.self, in: machO),
                  let signatureCount = UnrecordedTypes.read(base + 12, as: UInt32.self, in: machO),
                  let requirementCount = UnrecordedTypes.read(base + 16, as: UInt32.self, in: machO),
                  flags & 0x1F == 3, (flags >> 18) & 0x3F == 0,
                  word - 1 < Int(requirementCount), signatureCount < 0x10000,
                  let requirementFlags = UnrecordedTypes.read(base + 24 + 12 * Int(signatureCount) + 8 * (word - 1), as: UInt32.self, in: machO),
                  requirementFlags & 0x20 == 0
            else { return nil }
            let kinds = [1: "method", 2: "init", 3: "getter", 4: "setter"]
            guard let kind = kinds[Int(requirementFlags & 0x0F)] else { return nil }
            // A name is a direct relative pointer to a C string, which can
            // start at an odd address. Only the parent field is indirectable:
            // its low bit means "through a GOT slot", which is declined.
            func relative(_ fieldOffset: Int, from address: UInt64, fileBase: Int, indirectable: Bool = false) -> UInt64? {
                guard let raw = UnrecordedTypes.read(fileBase + fieldOffset, as: Int32.self, in: machO),
                      !indirectable || raw & 1 == 0
                else { return nil }
                return UInt64(bitPattern: Int64(bitPattern: address &+ UInt64(fieldOffset)) &+ Int64(raw))
            }
            guard let nameAddress = relative(8, from: descriptor, fileBase: base),
                  let name = Self.cString(at: nameAddress, in: machO, ranges: fileRanges), !name.isEmpty,
                  let parent = relative(4, from: descriptor, fileBase: base, indirectable: true),
                  let parentBase = machO.fileOffset(of: parent).map(Int.init),
                  let parentFlags = UnrecordedTypes.read(parentBase, as: UInt32.self, in: machO), parentFlags & 0x1F == 0,
                  let moduleNameAddress = relative(8, from: parent, fileBase: parentBase),
                  let module = Self.cString(at: moduleNameAddress, in: machO, ranges: fileRanges), !module.isEmpty
            else { return nil }
            return ("\(module).\(name)", word - 1, kind + (requirementFlags & 0x10 == 0 ? ", static" : ""))
        }

        /// The descriptor of an in-image protocol named exactly `name` whose
        /// existential is opaque: not class-constrained (ProtocolContext
        /// flags bit 16 set: `ProtocolClassConstraint::Any`) and no special
        /// protocol (`Error`'s existential is a box). A value of such an
        /// `any P` is a five-word container, passed and held by address.
        /// The descriptor of an in-image Swift protocol named exactly `name`
        /// whose existential is class-bound (bit 16 clear:
        /// `ProtocolClassConstraint::Class`, no special protocol): the object
        /// and one witness table. An `@objc` protocol has no Swift descriptor,
        /// and its existential takes no table.
        func classBoundExistentialDescriptor(named name: String) -> UInt64? {
            guard machO.cache == nil, let descriptor = protocolDescriptor(named: name),
                  let base = machO.fileOffset(of: descriptor).map(Int.init),
                  let flags = UnrecordedTypes.read(base, as: UInt32.self, in: machO),
                  flags & 0x1F == 3, (flags >> 16) & 1 == 0, (flags >> 18) & 0x3F == 0
            else { return nil }
            return descriptor
        }

        func opaqueExistentialDescriptor(named name: String) -> UInt64? {
            guard machO.cache == nil, let descriptor = protocolDescriptor(named: name),
                  let base = machO.fileOffset(of: descriptor).map(Int.init),
                  let flags = UnrecordedTypes.read(base, as: UInt32.self, in: machO),
                  flags & 0x1F == 3, (flags >> 16) & 1 == 1, (flags >> 18) & 0x3F == 0
            else { return nil }
            return descriptor
        }

        func protocolRequirement(descriptor: UInt64, word: Int) -> (signature: String, name: String)? {
            guard machO.cache == nil, word >= 1,
                  let base = machO.fileOffset(of: descriptor).map(Int.init),
                  let flags = UnrecordedTypes.read(base, as: UInt32.self, in: machO),
                  let signatureCount = UnrecordedTypes.read(base + 12, as: UInt32.self, in: machO),
                  let requirementCount = UnrecordedTypes.read(base + 16, as: UInt32.self, in: machO),
                  // ContextDescriptorKind::Protocol is 3; SpecialProtocol
                  // is bits 2-7 of the kind-specific flags (bits 16-31).
                  flags & 0x1F == 3, (flags >> 18) & 0x3F == 0,
                  word - 1 < Int(requirementCount), signatureCount < 0x10000
            else { return nil }
            let offset = 24 + 12 * Int(signatureCount) + 8 * (word - 1)
            let address = descriptor + UInt64(offset)
            // ProtocolRequirementFlags: kind in bits 0-3 (Method 1, Init 2,
            // Getter 3, Setter 4), IsAsync 0x20.
            guard let requirementFlags = UnrecordedTypes.read(base + offset, as: UInt32.self, in: machO),
                  (1 ... 4).contains(requirementFlags & 0x0F), requirementFlags & 0x20 == 0,
                  let protocolSymbols = protocolDescriptorSymbols[descriptor], protocolSymbols.count == 1,
                  let requirementSymbols = protocolDescriptorSymbols[address], requirementSymbols.count == 1,
                  let protocolName = protocolSymbols.first, protocolName.hasPrefix("protocol descriptor for "),
                  let requirement = requirementSymbols.first, requirement.hasPrefix("method descriptor for ")
            else { return nil }
            let owner = protocolName.dropFirst("protocol descriptor for ".count) + "."
            var signature = String(requirement.dropFirst("method descriptor for ".count))
            let isStatic = signature.hasPrefix("static ")
            if isStatic { signature.removeFirst("static ".count) }
            guard owner.count > 1, signature.hasPrefix(owner),
                  let name = Self.requirementName(signature)
            else { return nil }
            return ((isStatic ? "static " : "") + signature, (isStatic ? "static " : "") + name)
        }

        /// A requirement's name with its argument labels and no types:
        /// `M.P.scaled(by: Swift.Int) -> Swift.Int` is `M.P.scaled(by:)`,
        /// `M.P.send<A where A1: Swift.Encodable>(A1) throws -> ()` is
        /// `M.P.send(_:)`, `M.P.label.getter : Swift.Int` is
        /// `M.P.label.getter`. Nil for anything else.
        static func requirementName(_ signature: String) -> String? {
            func isQualifiedIdentifier(_ text: Substring) -> Bool {
                !text.isEmpty && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            }
            if let parts = DisassembledFunction.splitSignature(signature),
               let range = DisassembledFunction.outermostArgumentListRange(of: parts.head) {
                var name = parts.head[..<range.lowerBound].dropLast()
                if let open = name.firstIndex(of: "<"), name.hasSuffix(">") { name = name[..<open] }
                guard isQualifiedIdentifier(name) else { return nil }
                let labels = DisassembledFunction.splitTopLevelArguments(parts.head[range]).map { parameter -> String in
                    guard let colon = parameter.range(of: ": "),
                          isQualifiedIdentifier(parameter[..<colon.lowerBound]),
                          !parameter[..<colon.lowerBound].contains(".")
                    else { return "_:" }
                    return parameter[..<colon.lowerBound] + ":"
                }
                return name + "(" + labels.joined() + ")"
            }
            guard let colon = DisassembledFunction.topLevelRange(of: " : ", in: signature) else { return nil }
            let name = signature[..<colon.lowerBound]
            guard isQualifiedIdentifier(name), name.hasSuffix(".getter") || name.hasSuffix(".setter") else { return nil }
            return String(name)
        }

        static func specializationSymbols(
            labels: [UInt64: String], names: [UInt64: String], folded: [UInt64: [String]]
        ) -> [UInt64: String] {
            var symbols: [UInt64: String] = [:]
            for (address, name) in names where DisassembledFunction.isSpecializationName(name) {
                guard (folded[address]?.count ?? 0) <= 1, let symbol = labels[address] else { continue }
                symbols[address] = symbol
            }
            return symbols
        }

        /// The witness a conformance's table holds at `slot`, when `target`
        /// is folded: the table's symbol names the conformance, and the one
        /// candidate that is that conformance's witness is the function the
        /// slot was filled with. Nil when the slot is in no table, or no
        /// candidate (or more than one) is that conformance's witness.
        func witnessName(at target: UInt64, loadedFrom slot: UInt64) -> String? {
            // Two tables at one address (aliased symbols) disagree: decline.
            let conformances = Set(witnessTables.filter { $0.range.contains(slot) }.map(\.conformance))
            guard declinedFoldName(at: target) != nil, conformances.count == 1, let conformance = conformances.first
            else { return nil }
            let suffix = " in conformance \(conformance)"
            let witnesses = Set((foldedCandidates[target] ?? []).compactMap { demangleSymbol($0) }
                .filter { $0.hasPrefix("protocol witness for ") && $0.hasSuffix(suffix) })
            return witnesses.count == 1 ? witnesses.first : nil
        }

        /// The heading's name, `sub_<addr>`, when `names` declines to pick
        /// one of the symbols folded onto `address`; nil anywhere else.
        func declinedFoldName(at address: UInt64) -> String? {
            guard foldedCandidates[address] != nil, let name = names[address],
                  name == "sub_\(String(address, radix: 16))"
            else { return nil }
            return name
        }

        /// The candidate at `address` that belongs to `typeName` (its simple
        /// name is a component of the member's qualified context), or nil. At a
        /// folded address `names` holds `sub_<addr>`, and the owner picks among
        /// the folded symbols only when it proves one: two of `typeName`'s own
        /// members folded together leave the slot's member unknown.
        func name(at address: UInt64, ownedBy typeName: String) -> String? {
            let candidates = (foldedCandidates[address] ?? []).map { demangleSymbol($0) ?? $0 }
                + [name(at: address)].compactMap { $0 }
            let members = Set(candidates.filter { Self.isMember($0, of: typeName) })
            return members.count == 1 ? members.first : nil
        }

        static func isMember(_ name: String, of typeName: String) -> Bool {
            let qualified = name.prefix { $0 != "(" && $0 != " " }
            return qualified.split(separator: ".").dropLast().contains { $0 == typeName }
        }

        /// The selector a loaded address denotes, when that address is a selref
        /// slot. Nil for every other load.
        func selector(at slot: UInt64) -> String? { selectors.bySelref[slot] }

        /// A display name for the *contents* of `slot` — what an `ldr` from it
        /// yields. Either a selector ref, or a GOT-style slot bound to an
        /// imported symbol (`_OBJC_CLASS_$_NSUserDefaults` → `NSUserDefaults`,
        /// which is how a class-method receiver is materialised). Nil for any
        /// other load: unnamed data we must not guess at.
        func loadedName(at slot: UInt64) -> String? {
            if let selector = selectors.bySelref[slot] { return "@selector(\(selector))" }
            // A bind in a slot the program can rewrite names only the value
            // it starts with: `int (*hook)(const char *) = puts;` in
            // __DATA,__data rendered `keep(puts)` after `silence` could have
            // replaced it.
            guard holdsLoaderOwnedPointer(at: slot), let symbol = boundSymbol(at: slot) else { return nil }
            if symbol.hasPrefix(Self.classSymbolPrefix) {
                return String(symbol.dropFirst(Self.classSymbolPrefix.count))
            }
            if let demangled = demangleSymbol(symbol) { return demangled }
            return symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
        }

        private static let classSymbolPrefix = "_OBJC_CLASS_$_"

        /// The eight bytes at `address` when it lies inside a `__TEXT` literal
        /// section (`__const`, `__literal4/8/16`): read-only data the linker never
        /// fixes up, so the bytes on disk are the constant the code loads. Nil
        /// anywhere else, including every writable or fixup-bearing section,
        /// where the on-disk bytes are not what runs.
        func literalWord(at address: UInt64) -> UInt64? {
            let literalSections: Set<String> = ["__const", "__literal4", "__literal8", "__literal16"]
            guard let section = machO.sections.first(where: {
                $0.segmentName == "__TEXT" && literalSections.contains($0.sectionName)
                    && UInt64($0.address) <= address && address + 8 <= UInt64($0.address) + UInt64($0.size)
            }) else { return nil }
            _ = section
            guard let bytes: [UInt8] = try? machO.readElements(
                offset: machO.resolveOffset(at: address), numberOfElements: 8
            ), bytes.count == 8 else { return nil }
            return bytes.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * UInt64($1.offset))) }
        }

        /// The imported symbol a slot binds to, via the chained-fixup imports.
        private func boundSymbol(at slot: UInt64) -> String? {
            guard let fileOffset = machO.fileOffset(of: slot) else { return nil }
            return chainedFixups.symbol(at: UInt64(fileOffset), in: machO)
        }

        /// Every chained-fixup bind and rebase of the image, by file offset,
        /// built on the first lookup and shared by every copy of the resolver.
        let chainedFixups = ChainedFixupTable()

        /// `@"literal"` for a `__cfstring` entry.
        ///
        /// Layout is `struct __NSConstantString { void *isa; int32 flags; int32 _;
        /// const char *str; long length; }`, so the character pointer sits at
        /// +16 — and is itself rebased, not a literal on-disk pointer.
        func cfString(at address: UInt64) -> String? {
            guard cfStringRange?.contains(address) == true,
                  let target = pointerTarget(at: address &+ 16),
                  let text = readCString(at: target)
            else { return nil }
            return "@\"\(text)\""
        }

        /// A printable C string, crossing subcaches when needed.
        private func readCString(at address: UInt64) -> String? {
            if let cacheReader { return cacheReader.cString(at: address).flatMap(Self.printableLiteralText) }
            return Self.cString(at: address, in: machO, ranges: fileRanges)
        }

        func name(at target: UInt64) -> String? {
            if let name = names[target] { return name }
            // A direct reference to a uniqued selector string — how a shared-cache
            // image names the selector it's about to send.
            if let selector = selectors.byStringAddress[target] { return "@selector(\(selector))" }
            if let literal = cfString(at: target) { return literal }
            if stringRanges.contains(where: { $0.contains(target) }),
               let string = Self.cString(at: target, in: machO, ranges: fileRanges) {
                return "\"\(string)\""
            }
            if let string = Self.rawCString(at: target, in: machO, ranges: fileRanges), !string.isEmpty,
               let demangled = demangleSymbol(string) {
                return demangled
            }
            return nil
        }

        /// The quoted text of a Swift literal of 16 bytes or more, given the
        /// address its String object word holds.
        ///
        /// At -O such a literal is the pair (count and flags, `(address − 32) |
        /// 1<<63`): the object word points 32 bytes before the bytes, where
        /// the native-string header would sit. Naming the address itself quoted
        /// whatever C string the linker placed there, another literal or the
        /// tail of one: a compare against one literal rendered a different one,
        /// and on one app 0 of 151 such sites showed the true text. With
        /// `count`, the bytes must be exactly that long.
        func swiftLargeStringLiteral(objectAddress: UInt64, count: Int? = nil) -> String? {
            let (target, overflow) = objectAddress.addingReportingOverflow(32)
            guard !overflow else { return nil }
            return swiftStringLiteral(at: target, count: count)
        }

        /// The quoted text of a Swift literal's bytes at `target`: a NUL-ended
        /// run in a string section, or in `__TEXT,__const` when `count` says
        /// how long it is, and exactly that long. With `isASCII`, the bytes
        /// must agree with the flag the compiler computed for them.
        func swiftStringLiteral(at target: UInt64, count: Int?, isASCII: Bool? = nil) -> String? {
            let constantRanges: [Range<UInt64>] = count == nil ? [] : machO.sections.compactMap {
                guard $0.segmentName == "__TEXT", $0.sectionName == "__const" else { return nil }
                return UInt64($0.address)..<(UInt64($0.address) + UInt64($0.size))
            }
            guard let range = (stringRanges + constantRanges).first(where: { $0.contains(target) }),
                  let length = count ?? Self.rawCString(at: target, in: machO, ranges: fileRanges)?.utf8.count,
                  length > 0, UInt64(length) < range.upperBound - target,
                  fileRanges.map({ $0.holdsBytes(at: target, count: length + 1) }) ?? true,
                  let bytes: [UInt8] = try? machO.readElements(offset: machO.resolveOffset(at: target), numberOfElements: length + 1),
                  bytes.count == length + 1, bytes.last == 0,
                  isASCII.map({ Self.bytes(bytes.dropLast(), agreeWithASCIIFlag: $0) }) ?? true,
                  let raw = String(bytes: bytes.dropLast(), encoding: .utf8)
            else { return nil }
            // Count UTF-8 bytes, not characters; retain combining sequences and
            // pooled suffix addresses. A Swift literal can contain NUL, so a
            // C-string scan is insufficient when the representation gives a
            // byte count. Escape the complete value instead of truncating it
            // into a different literal.
            return "\"\(Self.escapedLiteralText(raw))\""
        }

        /// Whether a literal's bytes are ASCII exactly when the compiler's
        /// `isASCII` flag says so. A disagreement means the bytes are not that
        /// literal's.
        static func bytes(_ bytes: some Sequence<UInt8>, agreeWithASCIIFlag isASCII: Bool) -> Bool {
            bytes.allSatisfy { $0 < 0x80 } == isASCII
        }

        /// A literal's text with each character a reader would take for
        /// syntax escaped, so the rendered `"…"` spells exactly these
        /// characters. Unescaped, the bytes `c\nd` rendered `"c\nd"`, which
        /// reads as a newline, and `a"b` rendered `"a"b"`, which does not
        /// parse. For printable ASCII, the only text a C string renders, the
        /// escapes are C's as well.
        static func escapedLiteralText(_ raw: String) -> String {
            var text = ""
            for scalar in raw.unicodeScalars {
                switch scalar.value {
                case 0: text += "\\0"
                case 9: text += "\\t"
                case 10: text += "\\n"
                case 13: text += "\\r"
                case 34: text += "\\\""
                case 92: text += "\\\\"
                case 1...31, 127, 0x2028, 0x2029: text += "\\u{\(String(scalar.value, radix: 16))}"
                default: text.unicodeScalars.append(scalar)
                }
            }
            return text
        }

        /// `→ name` form for inline operand annotation.
        func reference(at target: UInt64) -> String? { name(at: target).map { "→ \($0)" } }

        /// Name for a direct call/branch *code* target — a recovered function or
        /// descriptor in this image. Unlike `name(at:)` it does not fall back to
        /// string/data interpretations (a branch target is code, never a
        /// cstring), so it never invents a spurious name for a call.
        func callTargetName(at target: UInt64) -> String? { names[target] }

        func arcIdentityContract(at target: UInt64, named callee: String) -> Bool {
            arcFunctions[target]?.permitsARCIdentity(named: callee) == true
                || cacheSymbols?.arcIdentityContract(forCallTarget: target, named: callee) == true
        }

        func arcIdentityContract(for value: AbstractValue, named callee: String) -> Bool {
            guard DisassembledFunction.isARCReferenceHelper(callee) else { return false }
            switch value {
            case .address(let target), .immediate(let target):
                return arcIdentityContract(at: target, named: callee)
            case .loaded(let slot):
                guard holdsFixedPointer(at: slot) else { return false }
                if let target = pointerTarget(at: slot) { return arcIdentityContract(at: target, named: callee) }
                guard let offset = machO.fileOffset(of: slot) else { return false }
                return chainedFixups.arcFunction(at: UInt64(offset), in: machO)?.permitsARCIdentity(named: callee) == true
            case .loadedThrough(let slot, let offset):
                guard offset >= 0, holdsFixedPointer(at: slot), let object = pointerTarget(at: slot) else { return false }
                let field = object &+ UInt64(offset)
                guard holdsFixedPointer(at: field), let target = pointerTarget(at: field) else { return false }
                return arcIdentityContract(at: target, named: callee)
            default: return false
            }
        }

        /// A function target proven by an abstract register value. The concrete
        /// address is present for in-image rebases/direct addresses; a GOT bind
        /// can still supply an imported function name without an in-image VM
        /// address, improving pseudocode while honestly remaining absent from
        /// the address-based call graph.
        func indirectCallTarget(for value: AbstractValue) -> (address: UInt64?, name: String)? {
            switch value {
            case .address(let target), .immediate(let target):
                return callTargetName(at: target).map { (target, $0) }
            case .loaded(let slot):
                // A load reads what the slot holds when the call runs. Only a
                // slot the program cannot store to still holds its fixup's
                // value then; a writable global's rebase or bind is where it
                // starts (`next = other`).
                guard holdsFixedPointer(at: slot) else { return nil }
                if let target = pointerTarget(at: slot) {
                    if let name = witnessName(at: target, loadedFrom: slot)
                        ?? callTargetName(at: target)
                        ?? cacheSymbols?.name(forCallTarget: target) {
                        return (target, name)
                    }
                }
                return loadedName(at: slot).map { (nil, $0) }
            case .loadedThrough(let slot, let offset):
                // Two loads the image's own bytes fix: the pointer in `slot`,
                // then the pointer at `offset` in what it points to, each a
                // rebase in read-only memory. `ldur x8, [meta, #-0x8]; ldr x8,
                // [x8, #0x28]; blr x8` reads a type's value-witness table and
                // calls its assignWithTake, named as its symbol demangles.
                guard offset >= 0, holdsFixedPointer(at: slot), let object = pointerTarget(at: slot) else { return nil }
                let field = object &+ UInt64(offset)
                guard holdsFixedPointer(at: field), let target = pointerTarget(at: field),
                      let name = callTargetName(at: target) ?? cacheSymbols?.name(forCallTarget: target)
                else { return nil }
                return (target, name)
            default:
                return nil
            }
        }

        func importedFunction(at target: UInt64) -> ImportedFunctionReference? {
            importedStubFunctions[target]
        }

        func importedFunction(for value: AbstractValue) -> ImportedFunctionReference? {
            switch value {
            case .address(let target), .immediate(let target):
                return importedFunction(at: target)
            case .loaded(let slot):
                guard holdsFixedPointer(at: slot), let offset = machO.fileOffset(of: slot) else { return nil }
                return chainedFixups.importedFunction(at: UInt64(offset), in: machO)
            default:
                return nil
            }
        }

        /// Writable sections whose pointers only dyld and the Objective-C
        /// runtime set: class, superclass and protocol references, and the
        /// symbol pointer tables.
        private static let loaderOwnedPointerSections: Set<String> = [
            "__objc_classrefs", "__objc_superrefs", "__objc_protorefs",
            "__got", "__auth_got", "__la_symbol_ptr", "__nl_symbol_ptr",
        ]

        /// Whether the program cannot change the pointer in `slot`: it is
        /// read-only after fixups (`holdsFixedPointer`), or in a section only
        /// the loader and the runtime write.
        func holdsLoaderOwnedPointer(at slot: UInt64) -> Bool {
            if holdsFixedPointer(at: slot) { return true }
            return machO.sections.contains {
                UInt64($0.address) <= slot && slot - UInt64($0.address) < UInt64($0.size)
                    && Self.loaderOwnedPointerSections.contains($0.sectionName)
            }
        }

        /// Whether `slot` holds its fixup's value whenever code loads it: it
        /// lies in a segment dyld makes read-only once fixups are applied
        /// (`SG_READ_ONLY`, or by name `__DATA_CONST` and `__AUTH_CONST`,
        /// where the linker puts GOTs, witness tables and other constant
        /// pointers). A dyld-cache slot outside this image's segments (a
        /// coalesced GOT) is judged by the cache mapping that holds it.
        /// Anything else is writable, and its initial bytes are only what
        /// the program starts with.
        func holdsFixedPointer(at slot: UInt64) -> Bool {
            if let segment = machO.segments64.first(where: {
                let start = UInt64($0.virtualMemoryAddress)
                return start <= slot && slot - start < UInt64($0.virtualMemorySize)
            }) {
                return segment.flags.contains(.read_only)
                    || segment.segmentName == "__DATA_CONST" || segment.segmentName == "__AUTH_CONST"
            }
            guard machO.isLoadedFromDyldCache, let mapping = machO.fullCache?.mappingAndSlideInfo(for: slot)
            else { return false }
            return !mapping.flags.isDisjoint(with: [.constData, .readOnlyData, .constTproData])
        }

        /// VM address held by a rebased pointer slot. Full-dyld-cache and
        /// standalone Mach-O resolvers intentionally return different spaces.
        private func pointerTarget(at slot: UInt64) -> UInt64? {
            if machO.isLoadedFromDyldCache, let full = machO.fullCache,
               let fileOffset = full.fileOffset(of: slot) {
                return full.resolveRebase(at: fileOffset)
            }
            guard let fileOffset = machO.fileOffset(of: slot),
                  let runtimeOffset = machO.isLoadedFromDyldCache
                    ? machO.resolveRebase(at: UInt64(fileOffset))
                    : chainedFixups.rebaseTarget(at: UInt64(fileOffset), in: machO)
            else { return nil }
            return machO.address(forOffset: 0) &+ runtimeOffset
        }

        /// The C string at `target`. A standalone image is read only through
        /// the bytes its file holds there (`fileBackedCString`): MachOKit maps
        /// a zero-fill address past the end of the file, and `readString`'s
        /// `strlen` then ran off the mapping (SIGSEGV on Prime Video, from an
        /// `adrp` to a `__common` global, in some runs and not others).
        static func rawCString(at target: UInt64, in machO: MachOFile, ranges: FileBackedRanges?) -> String? {
            if let ranges { return machO.fileBackedCString(at: target, ranges: ranges) }
            guard let fileOffset = machO.fileOffset(of: target) else { return nil }
            return try? machO.readString(offset: Int(fileOffset))
        }

        private static func cString(at target: UInt64, in machO: MachOFile, ranges: FileBackedRanges?) -> String? {
            rawCString(at: target, in: machO, ranges: ranges).flatMap(printableLiteralText)
        }

        /// A C string's text for a rendered literal: printable ASCII, tab,
        /// newline and carriage return, escaped, and cut after 48 characters
        /// with `…`, which no such string contains. Nil for an empty string or
        /// any other byte. Printable-only, `printf("%d\n", x)` read
        /// `printf(0x1000004bc, x)`: most format strings end in a newline.
        static func printableLiteralText(_ s: String) -> String? {
            guard !s.isEmpty, s.unicodeScalars.allSatisfy({
                ($0.value >= 0x20 && $0.value < 0x7f) || [9, 10, 13].contains($0.value)
            }) else { return nil }
            return s.count > 48 ? escapedLiteralText(String(s.prefix(48))) + "…" : escapedLiteralText(s)
        }
    }

    /// The chained fixups of one standalone image, by file offset: the import
    /// each bind names and the runtime offset each rebase targets.
    ///
    /// MachOKit's `resolveBind(at:)` materialises every pointer of every
    /// segment's chains and searches them linearly (its `imports` recomputed
    /// on each access), and `resolveRebase(at:)` walks every page chain of the
    /// segment until it meets the offset: each lookup costs a walk of the
    /// image or segment. Argument rendering asks once per loaded slot. On Fiery
    /// Feeds `xrefs`, `sample` put 7,903 of 13,878 analysis samples under
    /// `loadedName(at:)` (binds), and, once that was fixed, 1,748 of 8,875 under
    /// `pointerTarget(at:)` (rebases). The table answers as MachOKit does (the
    /// first segment whose chain holds the offset decides; a rebase there is
    /// no bind and a bind no rebase) after one walk. Built lazily, so an image
    /// that never asks never walks its chains, as before.
    final class ChainedFixupTable: @unchecked Sendable {
        private let lock = NSLock()
        private var binds: [UInt64: String] = [:]
        private var arcFunctions: [UInt64: RuntimeFunctionReference] = [:]
        private var legacyStrongFunctions: [UInt64: RuntimeFunctionReference] = [:]
        private var legacyLazyEntries: [UInt64: Int] = [:]
        private var legacyLazyValidity: [UInt64: Bool] = [:]
        /// Each strong two-level import's raw symbol and library, by fixup
        /// file offset, for a consumer that checks an import's origin.
        private var importedFunctions: [UInt64: ImportedFunctionReference] = [:]
        private var rebases: [UInt64: UInt64] = [:]
        private var built = false

        func symbol(at fileOffset: UInt64, in machO: MachOFile) -> String? {
            lock.lock()
            defer { lock.unlock() }
            build(machO)
            return binds[fileOffset]
        }

        func importedFunction(at fileOffset: UInt64, in machO: MachOFile) -> ImportedFunctionReference? {
            lock.lock()
            defer { lock.unlock() }
            build(machO)
            return importedFunctions[fileOffset]
        }

        func arcFunction(at fileOffset: UInt64, in machO: MachOFile) -> RuntimeFunctionReference? {
            lock.lock()
            defer { lock.unlock() }
            build(machO)
            if let entry = legacyLazyEntries[fileOffset] {
                let valid: Bool
                if let cached = legacyLazyValidity[fileOffset] { valid = cached }
                else {
                    valid = legacyLazyStubMatches(slot: fileOffset, entry: entry, in: machO)
                    legacyLazyValidity[fileOffset] = valid
                }
                if !valid { return nil }
            }
            return arcFunctions[fileOffset]
        }

        func rebaseTarget(at fileOffset: UInt64, in machO: MachOFile) -> UInt64? {
            lock.lock()
            defer { lock.unlock() }
            build(machO)
            return rebases[fileOffset]
        }

        /// Every rebase, slot file offset to target runtime offset.
        func allRebases(in machO: MachOFile) -> [UInt64: UInt64] {
            lock.lock()
            defer { lock.unlock() }
            build(machO)
            return rebases
        }

        private static func arcName(_ name: String) -> String {
            name.hasPrefix("_") ? String(name.dropFirst()) : name
        }

        private func build(_ machO: MachOFile) {
            guard !built else { return }
            built = true
            guard let fixups = machO.dyldChainedFixups else {
                buildLegacyBindings(machO)
                for (offset, target) in ChainedRebases.opcodeTargets(in: machO) ?? [:] {
                    rebases[UInt64(offset)] = target
                }
                return
            }
            guard let startsInImage = fixups.startsInImage else { return }
            let imports = fixups.imports
            var seen: Set<UInt64> = []
            for segment in fixups.startsInSegments(of: startsInImage) {
                for pointer in fixups.pointers(of: segment, in: machO) {
                    let offset = UInt64(pointer.offset)
                    guard seen.insert(offset).inserted else { continue }
                    if pointer.fixupInfo.rebase != nil {
                        if let target = pointer.rebaseTargetRuntimeOffset(for: machO) { rebases[offset] = target }
                    } else if pointer.fixupInfo.bind != nil,
                              let (ordinal, pointerAddend) = pointer.bindOrdinalAndAddend(for: machO),
                              imports.indices.contains(ordinal),
                              let name = fixups.symbolName(for: imports[ordinal].info.nameOffset) {
                        binds[offset] = name
                        let entry = imports[ordinal].info
                        if DisassembledFunction.isARCReferenceHelper(Self.arcName(name)),
                           pointerAddend == 0, entry.addend == 0, !entry.isWeakImport,
                           let library = Disassembler.externalLibraryName(ordinal: entry.libraryOrdinal, in: machO) {
                            arcFunctions[offset] = RuntimeFunctionReference(rawSymbol: name, libraryName: library)
                        }
                        if pointerAddend == 0, entry.addend == 0, !entry.isWeakImport,
                           let library = Disassembler.externalLibraryName(ordinal: entry.libraryOrdinal, in: machO) {
                            importedFunctions[offset] = ImportedFunctionReference(rawSymbol: name, libraryName: library)
                        }
                    }
                }
            }
        }

        /// Preserve the loader program's end marker, flags and entry offsets.
        /// The BindingSymbol projection alone cannot prove a lazy call target.
        private func buildLegacyBindings(_ machO: MachOFile) {
            guard let normal = LegacyImportBindings.decode(machO.bindOperations?.data ?? Data(), kind: .normal),
                  let lazy = LegacyImportBindings.decode(machO.lazyBindOperations?.data ?? Data(), kind: .lazy),
                  let weak = LegacyImportBindings.decode(machO.weakBindOperations?.data ?? Data(), kind: .weak)
            else { return }
            let segments = Array(machO.segments64)
            var rejected = Set<UInt64>()
            var lazyReferences: [Int: RuntimeFunctionReference] = [:]
            var rejectedEntries = Set<Int>()
            for symbol in normal + lazy + weak {
                guard segments.indices.contains(symbol.segment) else {
                    arcFunctions.removeAll(); legacyStrongFunctions.removeAll(); legacyLazyEntries.removeAll()
                    return
                }
                let segment = segments[symbol.segment]
                let width: UInt64 = symbol.type == 1 ? 8 : 4
                let (address, overflow) = UInt64(segment.virtualMemoryAddress).addingReportingOverflow(symbol.offset)
                let (end, endOverflow) = address.addingReportingOverflow(width - 1)
                guard !overflow, !endOverflow, UInt64(segment.virtualMemorySize) >= width,
                      symbol.offset <= UInt64(segment.virtualMemorySize) - width,
                      let offset = machO.fileOffset(of: address),
                      let last = machO.fileOffset(of: end), UInt64(last) >= UInt64(offset),
                      UInt64(last) - UInt64(offset) == width - 1
                else {
                    arcFunctions.removeAll(); legacyStrongFunctions.removeAll(); legacyLazyEntries.removeAll()
                    return
                }
                let slot = UInt64(offset)
                binds[slot] = symbol.symbol
                guard symbol.type == 1, symbol.addend == 0, !symbol.isWeak,
                      let library = Disassembler.externalLibraryName(ordinal: symbol.libraryOrdinal, in: machO)
                else {
                    rejected.insert(slot)
                    if let entry = symbol.lazyEntry { rejectedEntries.insert(entry) }
                    continue
                }
                let reference = RuntimeFunctionReference(rawSymbol: symbol.symbol, libraryName: library)
                if let previous = legacyStrongFunctions[slot], previous != reference { rejected.insert(slot) }
                legacyStrongFunctions[slot] = reference
                if let entry = symbol.lazyEntry {
                    if let previous = legacyLazyEntries[slot], previous != entry { rejected.insert(slot) }
                    legacyLazyEntries[slot] = entry
                    if let previous = lazyReferences[entry], previous != reference { rejectedEntries.insert(entry) }
                    lazyReferences[entry] = reference
                }
                if DisassembledFunction.isARCReferenceHelper(Self.arcName(symbol.symbol)) { arcFunctions[slot] = reference }
            }
            for slot in rejected {
                arcFunctions.removeValue(forKey: slot)
                legacyStrongFunctions.removeValue(forKey: slot)
            }
            for (slot, entry) in legacyLazyEntries where rejectedEntries.contains(entry) {
                arcFunctions.removeValue(forKey: slot)
                legacyStrongFunctions.removeValue(forKey: slot)
            }
        }

        /// A lazy import first enters its own helper, which must select the
        /// same bind program. Merely finding a bind record at the slot is not
        /// proof that the initial branch reaches that record's function.
        private func legacyLazyStubMatches(slot: UInt64, entry: Int, in machO: MachOFile) -> Bool {
            guard slot <= UInt64(Int.max), entry >= 0, entry <= Int(UInt32.max),
                  let pointer: UInt64 = UnrecordedTypes.read(Int(slot), as: UInt64.self, in: machO),
                  let helper = machO.sections.first(where: {
                      $0.segmentName == "__TEXT" && $0.sectionName == "__stub_helper"
                          && $0.address >= 0 && $0.size >= 36
                          && pointer >= UInt64($0.address) && pointer - UInt64($0.address) <= UInt64($0.size - 12)
                  }) else { return false }
            let start = UInt64(helper.address)
            guard pointer >= start + 24, (pointer - start - 24) % 12 == 0 else { return false }
            func word(at address: UInt64) -> UInt32? {
                guard let offset = machO.fileOffset(of: address), offset <= Int.max else { return nil }
                return UnrecordedTypes.read(Int(offset), as: UInt32.self, in: machO)
            }
            guard word(at: pointer) == 0x18000050, let jump = word(at: pointer + 4),
                  jump & 0xfc000000 == 0x14000000, word(at: pointer + 8) == UInt32(entry)
            else { return false }
            let displacement = Int64(Int32(bitPattern: jump << 6) >> 6) * 4
            guard pointer &+ 4 &+ UInt64(bitPattern: displacement) == start,
                  word(at: start + 8) == 0xa9bf47f0, let engine = CapstoneEngine()
            else { return false }
            let words = (0..<6).compactMap { word(at: start + UInt64($0 * 4)) }
            guard words.count == 6 else { return false }
            let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
            let code = engine.disassemble(Data(bytes), address: start).map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }
            guard code.count == 6, code[0].detail?.id == AARCH64_INS_ADRP, code[1].detail?.id == AARCH64_INS_ADD,
                  code[0].detail?.operands.first?.operand.register?.key == "x17",
                  code[0].detail?.operands.first?.operand.register?.widthBits == 64,
                  code[1].detail?.operands.first?.operand.register?.key == "x17",
                  code[1].detail?.operands.first?.operand.register?.widthBits == 64,
                  code[1].detail?.operands.dropFirst().first?.operand.register?.key == "x17",
                  code[1].detail?.operands.dropFirst().first?.operand.register?.widthBits == 64,
                  let binder = RuntimeFunctionReference.pointerSlot(in: Array(code.suffix(3)), startingAt: start + 12),
                  let binderOffset = machO.fileOffset(of: binder),
                  legacyLazyEntries[UInt64(binderOffset)] == nil,
                  let reference = legacyStrongFunctions[UInt64(binderOffset)],
                  reference.rawSymbol == "dyld_stub_binder",
                  reference.libraryName == "/usr/lib/libSystem.B.dylib"
            else { return false }
            return true
        }
    }

    /// Run value tracking on a function and append recovered call arguments
    /// (`args(…)`) to each call instruction.
    /// Standard-library scalar types: a value of one is never a reference or
    /// an address, so never any method's `self` in x20.
    static let plainScalarTypes: Set<String> = [
        "Swift.Int", "Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.Int64",
        "Swift.UInt", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
        "Swift.Bool", "Swift.Double", "Swift.Float",
    ]

    /// Whether `callee`, a demangled Swift name with its signature, is an
    /// instance member of a type the class index proves a class: such a
    /// member takes `self` in x20. Static members, allocating initializers,
    /// thunks and free functions do not parse to an instance member.
    static func isClassInstanceMember(_ callee: String, classTypeIndex: ClassTypeIndex) -> Bool {
        guard DisassembledFunction.signatureKnown(displayName: callee, objcSignature: nil),
              let qualified = qualifiedSelfTypeFromDemangledName(callee)
        else { return false }
        return classTypeIndex.isClass(qualified)
    }

    /// A short name for an entry convention's kind, for the probe.
    static func conventionName(_ entry: MethodEntryConvention) -> String {
        switch entry {
        case .swiftInstance: "swift-instance"
        case .objectiveC: "objc"
        case .objectiveCInitializer: "objc-initializer"
        case .swiftFunction: "swift-function"
        case .swiftValueInstance: "swift-value-instance"
        case .asyncFunclet(let base, _): "async-funclet(" + (base.map(conventionName) ?? "none") + ")"
        }
    }

    /// The type whose instance arrives in x20, for one function — or nil, which
    /// is the honest answer for everything that isn't a Swift instance method.
    ///
    /// Two sources, and they are complementary rather than redundant:
    ///
    /// - The **demangled symbol** names the type directly and covers structs and
    ///   enums, whose methods are statically dispatched and have no metadata
    ///   record at all. It dies under `strip -x -S` for anything internal.
    /// - The **vtable index** is metadata and survives stripping completely, but
    ///   only classes have vtables.
    ///
    /// The **index is consulted first**, because it is the only source that
    /// carries `isInstance`. Getting this order wrong is not academic: it made
    /// `Animal.__allocating_init` — a static entry point whose x20 holds the
    /// *metatype* — render `swift_allocObject(self, 32, 7)`, attaching an
    /// instance's identity to a metatype pointer. The vtable knows
    /// (`Animal slot 6, Init, instance=false`); the symbol does not say.
    static func selfType(
        of function: DisassembledFunction,
        selfIndex: SelfTypeIndex,
        fieldMaps: [String: FieldMap],
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> String? {
        // A type whose SIMPLE name collided was dropped from the map by the
        // collision guard, but its QUALIFIED key survives — so a self type counts
        // as resolved when either key reaches a layout. The SIMPLE name is what is
        // returned: `vtableIndex` is keyed by simple name, and only the field-map
        // lookup prefers the qualified key.
        func resolves(_ simpleName: String) -> Bool {
            selfFieldMap(of: function, simpleName: simpleName, fieldMaps: fieldMaps) != nil
        }
        if let binding = selfIndex.binding(for: function.startAddress) {
            // Authoritative, including when it says no. An instance vtable slot
            // proves x20 is self whether or not the type has a layout to name
            // fields from: a class with no stored properties still dispatches
            // through its vtable, and its field reads simply stay unnamed.
            guard binding.isInstance else { return nil }
            return binding.selfTypeName
        }
        guard let fromSymbol = selfTypeFromDemangledName(function.analysisName) else { return nil }
        if resolves(fromSymbol) { return fromSymbol }
        // A class instance member takes self in x20 whether or not the class
        // has a stored property to lay out. A final method has no vtable
        // slot and a property-less class no field map, so neither source
        // above saw `final class Node: NSObject`'s `join`, and its self was
        // never seeded. The qualified name must be a class by metadata:
        // a free function parses to its module, which has no qualified name.
        // The name must be the function's own demangled symbol, with its
        // signature: only that says `static` for a type member. A name
        // metadata gives a stripped body (`SwiftSoup.Evaluator.IsEmpty.method`)
        // does not, and seeding self there lost 25 calls' arguments in one app.
        // A destructor has no signature to show, but is never static: it
        // takes the object it destroys in x20.
        if isSwiftMangled(function.symbol), let name = function.analysisName,
           DisassembledFunction.signatureKnown(displayName: name, objcSignature: nil)
            || name.hasSuffix(".__deallocating_deinit") || name.hasSuffix(".deinit"),
           let qualified = qualifiedSelfTypeFromDemangledName(name),
           classTypeIndex.isClass(qualified) {
            return fromSymbol
        }
        return nil
    }

    /// The no-payload enum an instance member or witness holds by address in
    /// x20, or nil. A resilient enum's members and every witness of a
    /// non-class protocol take self `@in_guaranteed`, and the swiftself
    /// register carries that address; a frozen or private enum's own members
    /// take the tag in x0 and leave x20 alone. The name cannot tell those
    /// apart, so the body must: x20 read as a load's base before anything
    /// writes it, in the straight line from the entry. x20 holds nothing else
    /// a Swift function dereferences on entry here. A static requirement and
    /// an initializer have a metatype there, and a closure its context; the
    /// name excludes those. Of a no-payload enum the byte at self is its tag,
    /// the case index `EnumCaseIndex` names. A private enum has no qualified
    /// name there (its parent is an anonymous context) and is declined.
    static func swiftEnumSelfType(of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex) -> String? {
        guard function.objcMethod == nil, let name = function.analysisName, isSwiftMangled(function.symbol)
        else { return nil }
        let type: String
        if name.hasPrefix("protocol witness for ") {
            guard !name.hasPrefix("protocol witness for static "),
                  let conformance = name.range(of: " in conformance "),
                  !name[..<conformance.lowerBound].contains(".init("),
                  let colon = name[conformance.upperBound...].range(of: " : ")
            else { return nil }
            type = String(name[conformance.upperBound ..< colon.lowerBound])
        } else {
            guard let qualified = qualifiedSelfTypeFromDemangledName(name) else { return nil }
            type = qualified
        }
        guard enumCaseIndex.isNoPayloadEnum(type) else { return nil }
        for insn in function.instructions {
            guard (insn.controlFlow ?? .sequential) == .sequential, let detail = insn.detail else { return nil }
            if insn.text.hasPrefix("ld"), detail.operands.contains(where: { info in
                if case .memory(let base?, _, _) = info.operand { return base.key == "x20" }
                return false
            }) { return type }
            if detail.writtenRegisterKeys.contains("x20") { return nil }
        }
        return nil
    }

    /// Strip a trailing `(…)` argument list.
    ///
    /// Matched from the end, for two reasons. A tuple argument
    /// (`value(for: (Int, Int))`) means the *first* `(` is not where the
    /// signature starts. And a private member is spelled
    /// `Type.(name in _HASH).setter` — cutting at the first `(` there destroys
    /// the name and loses the type, which is how every private property accessor
    /// in SwiftUI went unnamed.
    static func stripSignature(_ head: String) -> String {
        guard head.hasSuffix(")") else { return head }
        var depth = 0
        for index in head.indices.reversed() {
            if head[index] == ")" {
                depth += 1
            } else if head[index] == "(" {
                depth -= 1
                if depth == 0 { return String(head[..<index]) }
            }
        }
        return head
    }

    /// Demangled names whose x20 is not an instance of the type they mention.
    ///
    /// Checked against the name with its signature already removed, so an
    /// argument label cannot trip them.
    private static let nonInstanceMarkers = [
        "static ",                  // x20 holds the metatype
        "__allocating_init",        // ditto: a static entry point
        " for ",                    // "method descriptor for", "protocol witness for"
        " of ",                     // "dispatch thunk of", "variable initialization expression of"
        "@objc ",                   // an ObjC thunk: self is in x0, not x20
    ]

    /// `sample.Dog.breed.getter : Swift.String` → `Dog`.
    ///
    /// Positional, not a search. A right-to-left scan for "the first component
    /// that happens to be a known type" would resolve
    /// `struct Foo { var Bar: Int }`'s `m.Foo.Bar.getter` to the *type* `Bar`.
    /// Property accessors nest one level deeper than methods —
    /// `Module.Type.property.accessor` vs `Module.Type.method` — so the accessor
    /// kind decides which component is the type.
    ///
    /// The `fieldMaps` membership check at the call site is the backstop:
    /// `sample.run() -> ()` also has a dot, but a module has no field map.
    static func selfTypeFromDemangledName(_ name: String?) -> String? {
        selfTypeComponents(name).map { $0.parts[$0.typeIndex] }
    }

    /// The FULLY-QUALIFIED self type (`Module.Outer.Type`) — the same components
    /// `selfTypeFromDemangledName` takes the last of. This matches the qualified
    /// keys the field-map builder indexes, so a type whose SIMPLE name collided
    /// (and was dropped by the collision guard) still resolves to its OWN map.
    /// Nil when there is no module prefix to qualify with, so the caller falls
    /// back to the simple name rather than inventing a path.
    static func qualifiedSelfTypeFromDemangledName(_ name: String?) -> String? {
        guard let (parts, typeIndex) = selfTypeComponents(name), typeIndex >= 1 else { return nil }
        return parts[0...typeIndex].joined(separator: ".")
    }

    /// The demangled name's context components plus the index of the self type
    /// among them, or nil when the name does not denote an instance member.
    private static func selfTypeComponents(_ name: String?) -> (parts: [String], typeIndex: Int)? {
        guard let name else { return nil }
        // Cut the return clause and property type first, so `foo(a: Dog.Kind)`
        // and `... : Swift.String` are not mined for type names.
        var head = name
        if let arrow = DisassembledFunction.topLevelRange(of: " -> ", in: head) {
            head = String(head[..<arrow.lowerBound])
        }
        if let colon = head.range(of: " : ") { head = String(head[..<colon.lowerBound]) }
        head = stripSignature(head)
        guard !nonInstanceMarkers.contains(where: head.contains) else { return nil }

        let parts = head.split(separator: ".").map(String.init)
        // `deinit` is a member of the type, not an accessor of a property:
        // `Mod.Node.deinit` is Node's, and read as an accessor it named the
        // module.
        let accessors: Set<String> = ["getter", "setter", "modify", "read", "init"]
        // `Type.property.accessor` -> the type is 3 from the end.
        // `Type.method`            -> 2 from the end.
        let typeIndex = accessors.contains(parts.last ?? "") ? parts.count - 3 : parts.count - 2
        guard typeIndex >= 0, typeIndex < parts.count else { return nil }
        return (parts, typeIndex)
    }

    /// The field map for a resolved self type, preferring the QUALIFIED key so a
    /// type whose simple name collided still reaches its OWN layout. The qualified
    /// name must denote the same simple type, so a mismatch can never substitute a
    /// different type's map.
    static func selfFieldMap(
        of function: DisassembledFunction,
        simpleName: String,
        fieldMaps: [String: FieldMap]
    ) -> FieldMap? {
        // A qualified self type needs its own descriptor's map: falling back to
        // the simple name could borrow another type's fields. (Recovered from
        // the pre-merge stash 983aa25.)
        if let qualified = qualifiedSelfTypeFromDemangledName(function.analysisName) {
            guard qualified.split(separator: ".").last.map(String.init) == simpleName else { return nil }
            return fieldMaps[qualified]
        }
        return fieldMaps[simpleName]
    }

    /// Whether a symbol is Swift-mangled, and so uses the Swift calling
    /// convention (`self` in x20, error in x21).
    static func isSwiftMangled(_ symbol: String) -> Bool {
        let bare = symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
        return bare.hasPrefix("$s") || bare.hasPrefix("$S")
    }

    /// The raw (still-mangled) callee symbol from the instruction text, for
    /// calls objdump resolved through a stub or named inline. The reference
    /// index holds *demangled* names, so the mangling — the only reliable
    /// signal that a callee is Swift — has to come from the text.
    private static func rawCalleeSymbol(of insn: Instruction) -> String? {
        if let range = insn.text.range(of: "symbol stub for: ") {
            return String(insn.text[range.upperBound...].prefix { !$0.isWhitespace && $0 != ";" })
        }
        let fields = insn.text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2, fields[1].hasPrefix("_") else { return nil }
        return String(fields[1])
    }

    /// Whether `insn` calls a Swift function.
    private static func isSwiftCall(_ insn: Instruction, swiftTargets: Set<UInt64>) -> Bool {
        if let target = insn.branchTarget, swiftTargets.contains(target) { return true }
        return rawCalleeSymbol(of: insn).map(isSwiftMangled) ?? false
    }

    private static func hasRawSwiftCall(in instructions: [Instruction]) -> Bool {
        instructions.contains {
            // The exact call predicate below only accepts these two manglings.
            // Avoid splitting ordinary instruction text on a non-Swift image.
            ($0.text.contains("$s") || $0.text.contains("$S")) && isSwiftCall($0, swiftTargets: [])
        }
    }

    /// Positive entry-register proofs are consumed by Swift calls and by
    /// signature-derived leading receiver layouts. A signature need not have
    /// Swift mangling or metadata, so `swiftTargets.isEmpty` alone is no proof
    /// that these facts are unused. Any Swift evidence keeps the whole image's
    /// proof dependency graph, including its ordinary argument/helper bodies.
    static func needsEntryRegisterProofs(
        in machO: MachOFile, names: [UInt64: String], folded: [UInt64: [String]], swiftTargets: Set<UInt64>
    ) -> Bool {
        guard swiftTargets.isEmpty, machO.fullCache == nil,
              !machO.sections.contains(where: { $0.sectionName.hasPrefix("__swift") }) else { return true }
        func possibleConsumer(_ name: String) -> Bool {
            isSwiftMangled(name) || DisassembledFunction.splitSignature(name) != nil
        }
        return names.values.contains(where: possibleConsumer)
            || folded.values.contains { $0.contains(where: possibleConsumer) }
    }

    /// Split an Objective-C method symbol (`-[Class sel:with:]`, `+[Class sel]`,
    /// or with a category `-[Class(Cat) sel]`) into its owner name and selector.
    /// Nil for anything that is not an ObjC method symbol.
    private static func objcMethodSymbolParts(_ symbol: String) -> (owner: Substring, selector: Substring)? {
        guard symbol.hasPrefix("-[") || symbol.hasPrefix("+["), symbol.hasSuffix("]") else { return nil }
        let inner = symbol.dropFirst(2).dropLast()
        guard let space = inner.firstIndex(of: " ") else { return nil }
        let owner = inner[..<space]
        let selector = inner[inner.index(after: space)...]
        // A real selector is a run of identifier characters and colons — reject
        // anything with embedded spaces (a demangled Swift name, say).
        guard !owner.isEmpty, !selector.isEmpty, !selector.contains(" ") else { return nil }
        return (owner, selector)
    }

    /// The Objective-C receiver convention implied by a method symbol name, used
    /// when no metadata binding exists. `self` is x0, `_cmd` is x1, and one
    /// explicit argument per selector colon begins at x2 — the same ABI a bound
    /// method gets. Initializer families are detected from selector spelling so
    /// `self = [super init…]` still threads through.
    /// Where an Objective-C method's explicit arguments arrive, from its type
    /// encoding (`ObjCArgumentABI`). Stack locations are kept only for 8-byte
    /// slots; a narrower packed slot's upper bytes belong to nothing.
    ///
    /// A method that takes a struct seeds nothing. Its integer arguments'
    /// registers are known, but a send without a signature lays its own
    /// arguments out by colon position, and a struct the method passes
    /// straight on stays in its registers untouched, so seeding named the
    /// shifted ones: Terminal's `[super initWithContentRect:r styleMask:m
    /// backing:b defer:d]` rendered `initWithContentRect:arg1 styleMask:arg2
    /// backing:arg3`, each one argument off.
    static func objcArgumentLocations(_ method: ObjCMethodBinding) -> [String: Int] {
        guard let types = ObjCArgumentABI.parameterTypes(encoding: method.typeEncoding, argumentCount: method.argumentCount),
              !types.contains(where: { $0.first == "{" }) else { return [:] }
        let locations = ObjCArgumentABI.locations(encoding: method.typeEncoding, argumentCount: method.argumentCount)
        let widths = ObjCArgumentABI.stackSlotWidths(encoding: method.typeEncoding, argumentCount: method.argumentCount)
        return locations.filter { location, _ in !location.hasPrefix("stack@") || widths[location] == 8 }
    }

    private static func objcEntryFromSymbol(_ symbol: String) -> MethodEntryConvention? {
        guard let (_, selector) = objcMethodSymbolParts(symbol) else { return nil }
        let argumentCount = selector.filter { $0 == ":" }.count
        let isInitializer = selector == "init"
            || (selector.hasPrefix("init") && selector.dropFirst(4).first.map { !$0.isLowercase } == true)
        return isInitializer
            ? .objectiveCInitializer(argumentCount: argumentCount)
            : .objectiveC(argumentCount: argumentCount)
    }

    /// The owning class name from a method symbol, category suffix stripped
    /// (`-[UILabel(Accessibility) foo]` → `UILabel`), for looking up an ivar
    /// layout the metadata binding didn't provide.
    private static func objcClassName(fromSymbol symbol: String) -> String? {
        guard let (owner, _) = objcMethodSymbolParts(symbol) else { return nil }
        if let paren = owner.firstIndex(of: "(") { return String(owner[..<paren]) }
        return String(owner)
    }

    /// An `x == 0` / `x != 0` comparison — the truthiness/boolean-test form the
    /// structurer's text path already renders well (a BOOL ivar as `if (self->_f)`,
    /// a `cbz` as `if (!x)`). Baking the value tracer's raw comparison over it
    /// would lose that simplification, so those conditions stay with the text path
    /// and only genuine comparisons (`a >= b`, `x < 0`, `x == 5`) are baked.
    static func isTruthinessTest(_ value: AbstractValue) -> Bool {
        guard case .binary(let op, let lhs, let rhs) = value, op == .equal || op == .notEqual
        else { return false }
        // Equality against 0 or 1 is how a Bool is tested (`_enabled == 1`,
        // `x != 0`); ordering against them (`n > 0`) is a real comparison and is
        // still baked.
        func isBooleanConstant(_ operand: AbstractValue) -> Bool {
            operand == .immediate(0) || operand == .immediate(1)
        }
        // A masked value `(X & 0xff)` is a byte / no-payload-enum-tag extraction,
        // not a Bool: `(tag & 0xff) == 1` is an enum-case check (`d == .green`)
        // that must be baked and named, not deferred to the structurer's raw text
        // path. Only an *unmasked* `X == 0/1` is the Bool truthiness idiom.
        func isMaskedByte(_ operand: AbstractValue) -> Bool {
            if case .binary(.bitAnd, _, .immediate(let mask)) = operand { return mask <= 0xff }
            return false
        }
        if isMaskedByte(lhs) || isMaskedByte(rhs) { return false }
        return isBooleanConstant(lhs) || isBooleanConstant(rhs)
    }

    /// The value register a Swift function returns in.
    enum SwiftReturnRegister { case integer, floating }

    /// The demangled result type of a Swift function or property getter, or nil
    /// when it is `Void`, has no demangled signature, or the signature shape
    /// isn't one a single result type can be read from (a `.modify`/`.read`
    /// coroutine, a `with`/`for`-qualified thunk).
    ///
    /// A function/method spells its result after ` -> `; a property *getter*
    /// demangles as `Type.prop.getter : PropType`.
    static func swiftReturnTypeName(of function: DisassembledFunction) -> String? {
        guard function.objcMethod == nil, let name = function.layoutName else { return nil }
        return swiftReturnTypeName(forDemangledName: name)
    }

    /// The name an await's result is given: `awaited<N>`, after the resume
    /// funclet that receives it.
    static func awaitResultName(_ ordinal: Int) -> String { "awaited\(ordinal)" }

    /// `swiftReturnTypeName(of:)` on a bare demangled name (an awaited callee's).
    static func swiftReturnTypeName(forDemangledName fullName: String) -> String? {
        // A protocol witness prints its conformance after the signature
        // (`… : Swift.Int in conformance M.T : Swift.Hashable in M`), and its
        // ` : ` would otherwise be taken for the getter's type separator. The
        // witness returns the requirement's declared type.
        let name = fullName.range(of: " in conformance ").map { String(fullName[..<$0.lowerBound]) } ?? fullName
        let returnType: String
        if let arrow = name.range(of: " -> ", options: .backwards) {
            returnType = String(name[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            // The last arrow is the result's only when the result is not itself
            // a function type: `f() -> (Swift.Int) -> Swift.Int` returns a
            // two-word closure, not the Int its last arrow names. A getter of
            // a function-typed property spells the same arrow after its ` : `.
            if let getter = name.range(of: ".getter : "), getter.upperBound <= arrow.lowerBound { return nil }
            if let declared = DisassembledFunction.splitSignature(name)?.result, declared != returnType {
                return nil
            }
        } else if name.hasSuffix(".getter") == false, name.contains(".getter : "),
                  let colon = name.range(of: " : ", options: .backwards) {
            returnType = String(name[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }
        guard !returnType.isEmpty, returnType != "()",
              !returnType.contains(" with "), !returnType.contains(" for ")
        else { return nil }
        return returnType
    }

    /// Which single register a Swift function delivers its result in, inferred
    /// from the demangled return type — or nil when the function is `Void`,
    /// returns a value spanning several registers or an indirect buffer
    /// (`String`, tuples, large structs/existentials), or has no demangled
    /// signature. Restricting to single-register returns is what keeps a stale
    /// `x0`/`v0` from being printed as a fabricated return for a type that isn't
    /// actually returned there.
    static func swiftReturnRegister(
        of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex(), cfg: FunctionCFG? = nil
    ) -> SwiftReturnRegister? {
        guard let returnType = Self.swiftReturnTypeName(of: function) else { return nil }
        // The printed type is not the ABI. A closure reabstracted to a generic
        // convention returns even a one-word value through the x8 buffer, and
        // its x0 at `ret` is then whatever the last call left there (measured:
        // a `Dictionary.Values` closure in libswiftObservation rendered
        // `return Dictionary.removeAll(0)`).
        if Self.readsIncomingIndirectResult(function, cfg: cfg) { return nil }
        // An async function's result is delivered through its context's resume
        // function, never in x0/v0 at a `ret`; the same holds for its resume
        // funclets. Its x0 at a `ret` rendered `return swift_task_dealloc()`.
        if let name = function.analysisName,
           DisassembledFunction.splitSignature(name)?.isAsync == true
            || name.contains("resume partial function for ") {
            return nil
        }
        return swiftReturnRegister(forReturnType: returnType, enumCaseIndex: enumCaseIndex,
                                   classTypeIndex: classTypeIndex)
    }

    /// `swiftReturnRegister(of:)` for an awaited callee known only by name.
    static func swiftReturnRegister(forDemangledName name: String) -> SwiftReturnRegister? {
        guard let returnType = Self.swiftReturnTypeName(forDemangledName: name) else { return nil }
        return swiftReturnRegister(forReturnType: returnType)
    }

    /// A tail call forwards an ordinary synchronous Swift scalar result: a
    /// direct branch out of the function, or a `br` whose target the tracer
    /// named (a vtable or pointer-slot callee, left without an edge; one
    /// through self's vtable into this function is `return
    /// self.countdown(n - 1)`). Its pre-branch registers are arguments,
    /// never that result.
    static func scalarTailReturnSites(
        in function: DisassembledFunction,
        enumCaseIndex: EnumCaseIndex = EnumCaseIndex(), classTypeIndex: ClassTypeIndex = ClassTypeIndex(),
        cfg: FunctionCFG? = nil,
        provenSignature: (_ target: UInt64, _ printedName: String) -> String? = { _, _ in nil }
    ) -> Set<UInt64> {
        func ordinaryHead(_ head: String) -> Bool {
            guard let args = DisassembledFunction.outermostArgumentListRange(of: head) else { return false }
            var name = withoutPrivateDiscriminators(String(head[..<args.lowerBound].dropLast())).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("static ") { name.removeFirst("static ".count) }
            return name.contains(".") && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        }
        // Compute caller ABI eligibility once, not once per external branch.
        guard function.objcMethod == nil,
              let first = function.instructions.first, let last = function.instructions.last,
              let name = function.layoutName.map({ witnessRequirement($0) ?? $0 }),
              let caller = DisassembledFunction.splitSignature(name), !caller.isAsync, !caller.isThrowing,
              ordinaryHead(caller.head),
              swiftReturnRegister(of: function, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, cfg: cfg) != nil
        else { return [] }
        return Set(function.instructions.compactMap { insn in
            guard insn.controlFlow == .branch,
                  insn.branchTarget.map({ $0 < first.address || $0 > last.address }) ?? true,
                  let printed = DisassembledFunction.calleeName(of: insn),
                  // A proven specialization's result is its own: `bump<Double>`
                  // prints `-> A`, and a tail call to it returns a Double.
                  case let name = insn.branchTarget.flatMap({ provenSignature($0, printed) }) ?? printed,
                  let callee = DisassembledFunction.splitSignature(name), !callee.isAsync, !callee.isThrowing,
                  caller.result == callee.result,
                  ordinaryHead(callee.head) || signatureSpecializationKeepsResult(callee.head) && ordinaryHead(withoutSpecializationClauses(callee.head))
            else { return nil }
            return insn.address
        })
    }

    /// A protocol witness's requirement, `P4.P.f() -> Swift.Int` of
    /// `protocol witness for P4.P.f() -> Swift.Int in conformance P4.V :
    /// P4.P in P4`: the signature the witness is called with, whose result
    /// it forwards. A witness that tail-calls its member (`ldr x0, [x20];
    /// b V.f`) rendered `V.f(self: ?)` with no `return`. Nil for any other
    /// name.
    static func witnessRequirement(_ name: String) -> String? {
        let prefix = "protocol witness for "
        guard name.hasPrefix(prefix), let conformance = name.range(of: " in conformance ", options: .backwards)
        else { return nil }
        return String(name[name.index(name.startIndex, offsetBy: prefix.count) ..< conformance.lowerBound])
    }

    /// Whether a function signature specialization returns what the
    /// function it specializes returns: its clause rewrites parameters
    /// (dropped, propagated, re-owned) and has no `Return =` entry, which
    /// would change the result's convention. A closure-propagated
    /// specialization (`<Arg[0] = [Closure Propagated : …]> of
    /// M.apply(…) -> Swift.Int`) tail-called for a function returning Int
    /// rendered as a statement, not `return`.
    static func signatureSpecializationKeepsResult(_ head: String) -> Bool {
        let prefix = "function signature specialization <"
        guard head.hasPrefix(prefix), let end = head.range(of: "> of ") else { return false }
        let clause = head[head.index(head.startIndex, offsetBy: prefix.count) ..< end.lowerBound]
        return !clause.contains("Return") && !head[end.upperBound...].hasPrefix("function signature specialization <")
            && !head[end.upperBound...].hasPrefix("generic specialization <")
    }

    static func swiftReturnRegister(
        forReturnType returnType: String, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> SwiftReturnRegister? {
        // A printed nominal type does not determine its register class: a
        // one-Double struct returns in v0, a two-word struct in x0 and x1, a
        // larger one through x8. Read x0 only for layouts the signature or the
        // image's metadata proves are one integer register (`SwiftLowering`).
        // Defaulting every other type to x0 rendered a stale register as the
        // result (`abiOneDoubleFromInt` returned its callee's Int; recovered
        // from the pre-merge stash 983aa25 with its ABISource execution
        // oracle), and an Optional of a value type, whose nil is a tag or an
        // extra inhabitant, printed nil as `0`.
        switch SwiftLowering.of(returnType, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
        case .oneInteger: .integer
        case .oneFloat: .floating
        default: nil
        }
    }

    /// Which register a Swift callee's whole result is in, from the result
    /// type its name prints (`swiftReturnRegister(forReturnType:)`):
    /// `.notOneRegister` for any type whose layout is not proven one
    /// register, `.unknown` for a callee with no Swift signature or a result
    /// type it cannot read, an async one, or a String (two words, modelled
    /// apart).
    static func callResultBank(
        of callee: String, enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex,
        cache: CallResultBankCache
    ) -> ValueTracer.CallResultBank {
        cache.bank(for: callee) {
            callResultBank(of: callee, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex)
        }
    }

    /// `callResultBank` per callee name, for one image: a pure function of
    /// the name and the image's enum and class indexes, and the tracer asks
    /// at every call on every fixpoint iteration. Lookups only, never
    /// iterated, so the cache cannot change an order.
    final class CallResultBankCache: Sendable {
        private let store = Mutex<[String: ValueTracer.CallResultBank]>([:])

        func bank(for callee: String, compute: () -> ValueTracer.CallResultBank) -> ValueTracer.CallResultBank {
            if let hit = store.withLock({ $0[callee] }) { return hit }
            let bank = compute()
            store.withLock { $0[callee] = bank }
            return bank
        }
    }

    /// Whether a printed type holds a generic parameter (`A`, `B1`) as a
    /// whole token: what `#/(^|[^A-Za-z0-9_.])[A-Z][0-9]*($|[^A-Za-z0-9_])/#`
    /// matches, scanned by hand because a regex literal is parsed again each
    /// time it is evaluated (9.6% of a libSwiftParser run), and a `Regex` is
    /// not `Sendable`, so it cannot be a static. Over `Character`s, like the
    /// regex: an uppercase letter not after a word character or `.`, its
    /// digits, then the end or a non-word character.
    static func containsGenericParameterToken(_ type: String) -> Bool {
        func isWord(_ c: Character) -> Bool { c == "_" || (c.isASCII && (c.isLetter || c.isNumber)) }
        let characters = Array(type)
        for (index, c) in characters.enumerated() where c.isASCII && c.isUppercase {
            if index > 0, isWord(characters[index - 1]) || characters[index - 1] == "." { continue }
            var end = index + 1
            while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
            if end == characters.count || !isWord(characters[end]) { return true }
        }
        return false
    }

    static func callResultBank(
        of callee: String, enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex
    ) -> ValueTracer.CallResultBank {
        guard !callee.hasPrefix("objc_msgSend") else { return .unknown }
        if let signature = DisassembledFunction.splitSignature(callee) {
            guard !signature.isAsync else { return .unknown }
        } else if !callee.contains(".getter : ") {
            return .unknown
        }
        guard let type = swiftReturnTypeName(forDemangledName: callee) else { return .unknown }
        if twoWordStringTypes.contains(type) || type == "()" || type == "Swift.Never" { return .unknown }
        // A generic parameter's layout is its substitution's: a
        // specialization's printed `A1` may be a UInt in x0.
        if containsGenericParameterToken(type) { return .unknown }
        switch swiftReturnRegister(forReturnType: type, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
        case .integer?: return .integer
        case .floating?: return .floating
        case nil: return .notOneRegister
        }
    }

    /// The wrapped type of `Swift.Optional<T>`, `T?` or `T!`, or nil.
    static func optionalPayload(_ type: String) -> String? {
        if type.hasPrefix("Swift.Optional<"), type.hasSuffix(">") {
            return String(type.dropFirst("Swift.Optional<".count).dropLast())
        }
        if type.hasSuffix("?") || type.hasSuffix("!") { return String(type.dropLast()) }
        return nil
    }

    /// Whether the function reads the x8 it was called with on some path before
    /// writing it (`IndirectResultUse.reads`, a CFG walk over Capstone's operand
    /// roles). Under the Swift and AAPCS64 conventions an incoming x8 is only
    /// ever the indirect-result buffer, so a read means the result goes to
    /// memory, not x0/v0.
    static func readsIncomingIndirectResult(_ function: DisassembledFunction, cfg: FunctionCFG? = nil) -> Bool {
        let use = cfg.map { indirectResultUse(of: function, cfg: $0) } ?? indirectResultUse(of: function)
        return use == .reads
    }

    /// A specialization's name without its leading `function signature
    /// specialization <…> of ` and `generic specialization <…> of ` clauses:
    /// the function it specializes, as its name prints it. Any other name is
    /// returned unchanged.
    /// An accessor's name with its property, or with `(unknown)` in its
    /// place. A stripped binary's metadata names a vtable accessor by its
    /// kind alone, `Sample.Widget.setter`, and read as `Owner.property.setter`
    /// its type became the property: `self.Widget = 0` for the `label`
    /// setter. `owner` is the type the accessor belongs to, as its simple or
    /// qualified name.
    static func namingItsProperty(_ name: String, ownedBy owner: String) -> String {
        let accessors = ["getter", "setter", "modify", "read"]
        let head = name.range(of: " : ").map { String(name[..<$0.lowerBound]) } ?? name
        guard let dot = head.lastIndex(of: "."), accessors.contains(String(head[head.index(after: dot)...]))
        else { return name }
        let base = head[..<dot]
        guard base == owner || base.hasSuffix("." + owner) || owner.hasSuffix("." + base) else { return name }
        return String(base) + ".(unknown)" + name[dot...]
    }

    /// For a method of a frozen standard-library struct (or a type nested in
    /// one), whether it is static; nil for anything else. A protocol
    /// requirement (`Swift.Collection.endIndex.getter`) is not one: it takes
    /// an address-only `self` in x20. Nor is a stdlib class
    /// (`Swift._DictionaryStorage`), whose `self` is its reference in x20.
    static func standardLibraryStructMethod(_ callee: String) -> Bool? {
        var name = Substring(withoutSpecializationClauses(callee))
        let isStatic = name.hasPrefix("static ")
        if isStatic { name = name.dropFirst("static ".count) }
        guard name.hasPrefix("Swift.") else { return nil }
        let root = name.dropFirst("Swift.".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        // A method has a member after its type: `Swift.String.append`.
        guard name.dropFirst("Swift.".count + root.count).hasPrefix("."),
              standardLibraryStructs.contains(String(root))
        else { return nil }
        // A mutating method's x20 is `self`'s address whatever the caller
        // computed it from: an accessor that writes, or a method the
        // standard library declares `mutating`.
        let head = name.prefix { $0 != "(" && $0 != " " }
        if head.hasSuffix(".setter") || head.hasSuffix(".modify") || head.hasSuffix(".unsafeMutableAddressor")
            || standardLibraryMutatingMembers.contains(String(head.split(separator: ".").last ?? "")) {
            return nil
        }
        // An initializer takes its thin metatype, as a static method does:
        // `Dictionary.init(self: r0, …)` named a value left in x20.
        return isStatic || head.hasSuffix(".init")
    }

    /// For a member of a struct or an enum a system module declares
    /// `@frozen` (`SDKFrozenTypes`), whether it is static (an initializer
    /// too); nil for anything else. Swift passes a frozen type's `self` in
    /// x20 only by address, when it is address-only or the member is
    /// mutating; a loadable one travels as its words after the formals
    /// (`One<T>.get()` is `(i64 self, ptr T)`). A resilient one's always
    /// travels by address in x20: `Date.timeIntervalSince1970` is `(ptr
    /// swiftself)`, and its caller may forward an address it was handed.
    static func systemValueTypeMember(_ callee: String) -> Bool? {
        var name = Substring(withoutSpecializationClauses(callee))
        let isStatic = name.hasPrefix("static ")
        if isStatic { name = name.dropFirst("static ".count) }
        while name.hasPrefix("(extension in "), let colon = name.firstIndex(of: ":") {
            name = name[name.index(after: colon)...]
        }
        // `Swift.Array< where A: Swift.Equatable>.f`: the constrained
        // extension's clause is no part of the type's name.
        var head = ""
        var depth = 0
        for character in name {
            if depth == 0, character == "(" || character == " " { break }
            if character == "<" { depth += 1 } else if character == ">", depth > 0 { depth -= 1 } else if depth == 0 {
                head.append(character)
            }
        }
        let parts = head.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        for length in stride(from: parts.count - 1, through: 2, by: -1) {
            let owner = parts.prefix(length).joined(separator: ".")
            if let mutating = SDKFrozenTypes.mutatingMembers[owner] {
                // A mutating member (an accessor that writes, or a method
                // the interface declares `mutating`) takes `self`'s address
                // in x20: `Hasher._combine(self: arg0, 0)` is the caller's
                // `inout Hasher`.
                let member = parts[length...]
                guard let first = member.first, !mutating.contains(String(first)),
                      !["setter", "modify", "unsafeMutableAddressor"].contains(String(member.last ?? ""))
                else { return nil }
                return isStatic || first == "init"
            }
            // A resilient value type or a class: x20 may be `self`.
            if SDKMetadataAccessors.types[owner] != nil { return nil }
        }
        return nil
    }

    /// Members the standard library's frozen structs declare `mutating`
    /// (String.swift, StringRangeReplaceableCollection.swift, Array.swift,
    /// Dictionary.swift, Set.swift).
    static let standardLibraryMutatingMembers: Set<String> = [
        "append", "insert", "remove", "removeAll", "removeLast", "removeFirst", "removeSubrange",
        "replaceSubrange", "reserveCapacity", "updateValue", "removeValue", "popLast", "popFirst",
        "_appendElementAssumeUniqueAndCapacity", "_makeUniqueAndReserveCapacityIfNotUnique",
        "_reserveCapacityAssumingUniqueBuffer", "_appendElement", "_makeMutableAndUnique",
    ]

    /// Frozen value types of the standard library whose methods' `self`
    /// travels by value (stdlib/public/core, `@frozen public struct`), each
    /// at most four words. Not Hasher: larger than four words, every one of
    /// its methods takes `self` by address in x20.
    static let standardLibraryStructs: Set<String> = [
        "String", "Substring", "Character", "StaticString", "Array", "ArraySlice", "ContiguousArray",
        "Dictionary", "Set", "Optional", "Range", "ClosedRange", "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float", "Float16", "Bool",
        "UnsafePointer", "UnsafeMutablePointer", "UnsafeRawPointer", "UnsafeMutableRawPointer",
        "UnsafeBufferPointer", "UnsafeMutableBufferPointer", "UnsafeRawBufferPointer",
        "UnsafeMutableRawBufferPointer", "IndexingIterator", "_StringGuts", "_StringObject",
        "_NativeDictionary", "_NativeSet",
    ]

    static func withoutSpecializationClauses(_ name: String) -> String {
        var name = Substring(name)
        while name.hasPrefix("function signature specialization <") || name.hasPrefix("generic specialization <"),
              let of = name.range(of: "> of ") {
            name = name[of.upperBound...]
        }
        return String(name)
    }

    /// Whether a function signature specialization changed `self`'s
    /// parameter, which makes it thin: no swiftself, so x20 at a call to it
    /// is whatever the caller left there (`shouldModifySelfArgument`,
    /// swift/lib/SILOptimizer/FunctionSignatureTransforms). Self is the
    /// parameter after the formals, so an `Arg[n]` at or past their count
    /// names it. With an indirect result counted in, that `n` may be the
    /// last formal instead, and self is declined all the same.
    /// `<Arg[2] = Dead> of static FixIt.MultiNodeChange.makeMissing(_:_:)`
    /// read `makeMissing(self: sub_85a0(?), …)` for a value parked in x20.
    static func signatureSpecializationRewritesSelf(_ callee: String) -> Bool {
        let name = callee.hasPrefix("merged ") ? String(callee.dropFirst("merged ".count)) : callee
        guard name.hasPrefix("function signature specialization <") else { return false }
        let original = withoutSpecializationClauses(name)
        let formals = DisassembledFunction.splitSignature(original).flatMap { signature in
            DisassembledFunction.outermostArgumentListRange(of: signature.head).map {
                DisassembledFunction.splitTopLevelArguments(signature.head[$0]).count
            }
        } ?? 0
        let clauses = name.dropLast(original.count)
        return clauses.matches(of: #/Arg\[(\d+)\]/#).contains { Int($0.output.1).map { $0 >= formals } ?? true }
    }

    /// Whether a function's registers still follow the signature its name
    /// prints. A function signature specialization prints its original's
    /// signature but may change the parameters: `Arg[0] = Dead` drops one,
    /// so `<Arg[0] = Dead> of helperI(Swift.Int, Swift.Int)` takes `b` in
    /// x0 and its `b &* 23` read `return (arg0 * 23)`. Only an ownership
    /// change (`Owned To Guaranteed`, `Guaranteed To Owned`) leaves every
    /// register in place (swift/lib/Demangling/NodePrinter.cpp prints each
    /// kind; any other, a `Return =` entry or a merged specialization,
    /// declines). Every other name is its own signature.
    static func signatureSpecializationKeepsLayout(_ name: String) -> Bool {
        if name.hasPrefix("merged function signature specialization") { return false }
        let prefix = "function signature specialization <"
        guard name.hasPrefix(prefix) else { return true }
        guard let end = name.range(of: "> of ") else { return false }
        let clause = name[name.index(name.startIndex, offsetBy: prefix.count) ..< end.lowerBound]
        guard clause.wholeMatch(of: /Arg\[\d+\] = (Owned To Guaranteed|Guaranteed To Owned)(, Arg\[\d+\] = (Owned To Guaranteed|Guaranteed To Owned))*/) != nil
        else { return false }
        // A specialization of a specialization keeps the layout only if
        // both do: `<Arg[1] = Owned To Guaranteed> of <Arg[0] = [Closure
        // Propagated …]> of …` takes the inner one's registers.
        return signatureSpecializationKeepsLayout(String(name[end.upperBound...]))
    }

    /// The register→source-argument-index map to seed for a Swift free function
    /// or static method whose every parameter is a single-register scalar. In the
    /// Swift calling convention integer/pointer parameters fill x0… and
    /// floating-point ones fill v0… by independent counters, so the two are
    /// tracked separately. Nil for any signature with an aggregate, generic,
    /// `inout`, `String`, or otherwise multi-register parameter (or none), so a
    /// register is never mislabeled `arg k` when the real layout differs.
    /// The registers an unspecialized generic free function receives its
    /// type parameters' metadata in: the integer registers right after its
    /// formals, one per parameter in order, before any witness table
    /// (swift/docs/ABI/CallingConvention.rst; `pick<T>(Int, T, T) -> T` is
    /// `(sret, i64, ptr, ptr, ptr %T)`, T's metadata in x3). Empty for
    /// anything whose formals are not laid out in full, a method (its `self`
    /// and Self metadata have other places), an async function, or a
    /// signature that does not pass one metadata argument per parameter
    /// (`passesEveryGenericMetadata`).
    static func genericMetadataRegisters(
        of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex,
        fieldMaps: [String: FieldMap]
    ) -> [String: String] {
        guard let name = function.analysisName, isSwiftMangled(function.symbol),
              signatureSpecializationKeepsLayout(name), !name.hasPrefix("function signature specialization"),
              !name.hasPrefix("generic specialization"),
              let signature = DisassembledFunction.splitSignature(name), !signature.isAsync,
              let range = DisassembledFunction.outermostArgumentListRange(of: signature.head)
        else { return [:] }
        let head = signature.head[..<range.lowerBound].dropLast()
        guard let open = head.firstIndex(of: "<"), head.hasSuffix(">"),
              head[..<open].filter({ $0 == "." }).count == 1,
              head[..<open].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
        else { return [:] }
        let clause = head[head.index(after: open)..<head.index(before: head.endIndex)]
        let names = (clause.range(of: " where ").map { clause[..<$0.lowerBound] } ?? clause)
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.isEmpty, names.allSatisfy({ $0.wholeMatch(of: #/[A-Z][0-9]*/#) != nil }),
              let layout = swiftCallArgumentLayout(callee: name, enumCaseIndex: enumCaseIndex,
                                                   classTypeIndex: classTypeIndex, fieldMaps: fieldMaps),
              layout.stack.isEmpty, passesEveryGenericMetadata(symbol: function.symbol)
        else { return [:] }
        let integers = layout.slots.reduce(0) { total, slot in
            switch slot.kind {
            case .integer: total + slot.registers
            case .floating: total
            case .aggregate(let x, _): total + x
            }
        }
        var registers: [String: String] = [:]
        for (index, parameter) in names.enumerated() where integers + index < 8 {
            registers["x\(integers + index)"] = parameter
        }
        return registers
    }

    /// Whether a generic function's signature passes one metadata argument
    /// for each of its type parameters, read from its mangled nodes. IRGen
    /// passes fewer in two cases, and the arguments after a missing one move
    /// down a register: `keep<A, B>(Box<A>, B)` has B's metadata in x2,
    /// where counting parameters puts A's.
    /// - A parameter that is not canonical has no argument
    ///   (GenProto.cpp, enumerateGenericSignatureRequirements): one made
    ///   equal to another parameter or to a concrete type. One made equal
    ///   to a member type (`B == A.Item`) stays canonical.
    /// - A parameter a formal can supply is fulfilled from it
    ///   (PolymorphicConvention::considerParameter): see `isMetadataSource`.
    ///   So is the argument of a generic superclass bound (`A: Box<B>`),
    ///   whose instance is a source.
    /// False for any requirement or parameter this does not know.
    static func passesEveryGenericMetadata(symbol: String) -> Bool {
        var mangled = Substring(symbol)
        if mangled.hasPrefix("_$s") { mangled = mangled.dropFirst() }
        guard mangled.hasPrefix("$s"), let global = try? demangleAsNode(String(mangled)), global.kind == .global,
              global.children.count == 1, let declaration = global.children.first, declaration.kind == .function,
              let type = declaration.children.last, type.kind == .type,
              let generic = type.children.first, generic.kind == .dependentGenericType
        else { return false }
        let parts = Array(generic.children)
        guard parts.count == 2, parts[0].kind == .dependentGenericSignature, parts[1].kind == .type,
              let function = parts[1].children.first, function.kind == .functionType,
              let arguments = function.children.first(where: { $0.kind == .argumentTuple })
        else { return false }
        for entry in parts[0].children {
            let sides = Array(entry.children)
            switch entry.kind {
            case .dependentGenericParamCount, .dependentGenericLayoutRequirement:
                continue
            case .dependentGenericConformanceRequirement:
                guard sides.count == 2, let constraint = sides[1].children.first,
                      constraint.kind == .protocol || constraint.kind == .class
                else { return false }
            case .dependentGenericSameTypeRequirement:
                guard sides.count == 2, sides[1].children.first?.kind == .dependentMemberType else { return false }
            default:
                return false
            }
        }
        return !isMetadataSource(arguments)
    }

    /// Whether a formal's type node can supply a type parameter's metadata,
    /// as PolymorphicConvention::considerParameter reads one: a class built
    /// from a parameter (its instance leads to its metadata), or a metatype
    /// of anything but a bare parameter (a bare one is inexact, and
    /// fulfills nothing). A tuple's elements are parameters of their own. An
    /// `inout` is an address, and a struct, an enum or a function supplies
    /// nothing. A type this does not know counts if it mentions a parameter.
    private static func isMetadataSource(_ node: Node) -> Bool {
        func mentionsParameter(_ node: Node) -> Bool {
            node.contains { $0.kind == .dependentGenericParamType }
        }
        switch node.kind {
        case .argumentTuple, .type, .tuple, .tupleElement, .owned, .shared:
            return node.children.contains(where: isMetadataSource)
        case .inOut, .dependentGenericParamType, .dependentMemberType, .structure, .enum,
             .boundGenericStructure, .boundGenericEnum, .functionType, .noEscapeFunctionType:
            return false
        case .metatype:
            guard let instance = node.children.last, instance.kind == .type, instance.children.count == 1
            else { return true }
            return instance.children.first?.kind != .dependentGenericParamType && mentionsParameter(instance)
        default:
            return mentionsParameter(node)
        }
    }

    /// The registers holding a generic free function's witness tables
    /// (register key -> index among `genericProtocolRequirements`), when
    /// their places are proven. The polymorphic arguments follow the
    /// formals: each type parameter's metadata, then one table per
    /// requirement that needs one, in signature order
    /// (swift/lib/IRGen/GenProto.cpp, enumerateGenericSignatureRequirements).
    /// Each register here assumes every protocol requirement before it took
    /// a table; whoever names a table proves that, by the protocol's
    /// in-image descriptor.
    ///
    /// Declined: a function whose metadata arguments are not all in
    /// registers, and one whose requirements `genericProtocolRequirements`
    /// declines. Also any formal that is a source of metadata for IRGen's
    /// PolymorphicConvention, which then passes less: a class instance or a
    /// metatype built from a type parameter (`Box<A>`, `Box<A>.Type`).
    /// Only a parameter's bare value, `inout` or `.Type` (an inexact
    /// metatype, no source) may mention one.
    static func genericWitnessTableRegisters(
        of function: DisassembledFunction, metadata: [String: String]
    ) -> [String: Int] {
        guard !metadata.isEmpty, let name = function.analysisName,
              let signature = DisassembledFunction.splitSignature(name),
              let range = DisassembledFunction.outermostArgumentListRange(of: signature.head)
        else { return [:] }
        let parameters = genericParameterNames(in: signature.head)
        let registers = metadata.keys.compactMap { $0.hasPrefix("x") ? Int($0.dropFirst()) : nil }
        guard parameters.count == metadata.count, registers.count == metadata.count,
              let first = registers.min(), Set(registers) == Set(first ..< first + metadata.count),
              let generic = genericProtocolRequirements(of: function), generic.parameters == parameters.count
        else { return [:] }
        let requirements = generic.requirements
        for parameter in DisassembledFunction.splitTopLevelArguments(signature.head[range]) {
            var type = Substring(parameterType(parameter))
            if type.hasPrefix("inout ") { type = type.dropFirst("inout ".count) }
            if type.hasSuffix(".Type") { type = type.dropLast(".Type".count) }
            guard parameters.contains(String(type)) || !mentionsGenericParameter(String(type), parameters)
            else { return [:] }
        }
        var tables: [String: Int] = [:]
        for index in requirements.indices where first + metadata.count + index < 8 {
            tables["x\(first + metadata.count + index)"] = index
        }
        return tables
    }

    /// A generic free function's protocol requirements, in signature order:
    /// the depth-0 parameter each constrains (nil for a member type such as
    /// `A.Element`) and the protocol, printed. Read from the mangled
    /// signature, where a conformance names a protocol node and a superclass
    /// a class node, which the printed `where A: M.X` does not tell apart.
    /// A layout requirement takes no table and is skipped. Nil, declining
    /// every table, for a superclass (a metadata source), a same-type
    /// requirement (it removes a parameter), any other kind, or a signature
    /// with more than one depth.
    static func genericProtocolRequirements(
        of function: DisassembledFunction
    ) -> (parameters: Int, requirements: [(subject: String?, protocolName: String)])? {
        var mangled = Substring(function.symbol)
        if mangled.hasPrefix("_$s") { mangled = mangled.dropFirst() }
        guard mangled.hasPrefix("$s"), let global = try? demangleAsNode(String(mangled)), global.kind == .global,
              global.children.count == 1, let declaration = global.children.first, declaration.kind == .function,
              let type = declaration.children.last, type.kind == .type,
              let generic = type.children.first, generic.kind == .dependentGenericType,
              let signature = generic.children.first, signature.kind == .dependentGenericSignature
        else { return nil }
        let entries = Array(signature.children)
        guard let count = entries.first, count.kind == .dependentGenericParamCount, let parameters = count.index,
              !entries.dropFirst().contains(where: { $0.kind == .dependentGenericParamCount })
        else { return nil }
        var requirements: [(subject: String?, protocolName: String)] = []
        for entry in entries.dropFirst() {
            switch entry.kind {
            case .dependentGenericLayoutRequirement:
                continue
            case .dependentGenericConformanceRequirement:
                let parts = Array(entry.children)
                guard parts.count == 2, parts[0].kind == .type, parts[1].kind == .type,
                      let subject = parts[0].children.first, let constraint = parts[1].children.first,
                      constraint.kind == .protocol
                else { return nil }
                var name: String?
                if subject.kind == .dependentGenericParamType {
                    let indices = Array(subject.children)
                    guard indices.count == 2, indices[0].index == 0, let index = indices[1].index,
                          index < parameters, index < 26, let scalar = Unicode.Scalar(65 + Int(index))
                    else { return nil }
                    name = String(Character(scalar))
                } else if subject.kind != .dependentMemberType {
                    return nil
                }
                requirements.append((name, constraint.print(using: .default)))
            default:
                return nil
            }
        }
        return (Int(parameters), requirements)
    }

    static func swiftScalarArgumentRegisters(
        of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex(), fieldMaps: [String: FieldMap] = [:],
        isOpaqueExistential: (String) -> Bool = { _ in false },
        isClassBoundExistential: (String) -> Bool = { _ in false }
    ) -> [String: Int]? {
        swiftArgumentRegisters(of: function, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex,
                               fieldMaps: fieldMaps, isOpaqueExistential: isOpaqueExistential,
                               isClassBoundExistential: isClassBoundExistential)?.scalars
    }

    /// `swiftScalarArgumentRegisters`, with the register that holds each
    /// class-bound existential parameter's witness table (register key ->
    /// parameter index); the parameter itself is the object, in the register
    /// before it.
    static func swiftArgumentRegisters(
        of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex(), fieldMaps: [String: FieldMap] = [:],
        isOpaqueExistential: (String) -> Bool = { _ in false },
        isClassBoundExistential: (String) -> Bool = { _ in false }
    ) -> (scalars: [String: Int], existentialTables: [String: Int])? {
        guard function.objcMethod == nil, let name = function.layoutName,
              Self.isSwiftMangled(function.symbol),
              Self.signatureSpecializationKeepsLayout(name),
              // A getter/setter/accessor or a name without a call signature has no
              // ordinary parameter list to seed.
              let split = DisassembledFunction.splitSignature(name),
              // An async function with an indirect result takes the buffer
              // first, in x0 (`@bigRes(ptr %0, ptr swiftasync %1, i64 %2)`):
              // seeded from the printed signature, `arg0` named the buffer
              // and `x` read as raw x1. A result not proven direct may be
              // indirect, so nothing is seeded.
              !split.isAsync || SwiftLowering.of(split.result, enumCaseIndex: enumCaseIndex,
                                                 classTypeIndex: classTypeIndex).isDirect
        else { return nil }
        let signature = split.head
        // A tuple result with a generic element takes its buffers first,
        // from x0 (`dup<A>(A) -> (A, A)` receives its A in x2).
        guard !Self.returnsGenericTupleFromX0(name),
              let paramsRange = DisassembledFunction.outermostArgumentListRange(of: signature)
        else { return nil }
        let parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        guard !parameters.isEmpty else { return nil }

        var registers: [String: Int] = [:], tables: [String: Int] = [:]
        var integerIndex = 0, floatIndex = 0
        for (index, parameter) in parameters.enumerated() {
            switch Self.scalarParameterClass(parameter, enumCaseIndex: enumCaseIndex,
                                             classTypeIndex: classTypeIndex) {
            case .integer:
                guard integerIndex < 8 else { return nil }
                registers["x\(integerIndex)"] = index
                integerIndex += 1
            case .floating:
                guard floatIndex < 8 else { return nil }
                registers["v\(floatIndex)"] = index
                floatIndex += 1
            case .aggregate?:
                // `scalarParameterClass` classifies scalars only.
                return nil
            case nil:
                // A footprint the ABI fixes (a String's two words, an
                // Optional scalar's payload and tag, a StaticString's three
                // words) is left unseeded, since no one register is the
                // parameter, but the parameters after it
                // still have proven registers: `afterString(_:_:)`'s Int is
                // x2. Anything else is not provably laid out: seed nothing.
                let type = Self.parameterType(parameter)
                // A one-case enum is zero-sized: it takes no register.
                if enumCaseIndex.isSingleCaseEnum(type) { continue }
                // A value of a generic parameter (`A`, `A.Element`) arrives as
                // its address, one integer register (as `swiftCallArgumentLayout`
                // lays it out), and that address is the parameter.
                if Self.isGenericValue(type, Self.genericParameterNames(in: split.head)) {
                    guard integerIndex < 8 else { return nil }
                    registers["x\(integerIndex)"] = index
                    integerIndex += 1
                    continue
                }
                // An opaque existential of a protocol this image declares
                // (`_ s: any Shape`, printed `Module.Shape`) is a five-word
                // container passed by address: one integer register, which
                // is the parameter.
                if isOpaqueExistential(type) {
                    guard integerIndex < 8 else { return nil }
                    registers["x\(integerIndex)"] = index
                    integerIndex += 1
                    continue
                }
                // A class-bound existential (`_ n: any Named`, `Named:
                // AnyObject`) is the object and then its one witness table,
                // two integer registers.
                if isClassBoundExistential(type) {
                    guard integerIndex + 2 <= 8 else { return nil }
                    registers["x\(integerIndex)"] = index
                    tables["x\(integerIndex + 1)"] = index
                    integerIndex += 2
                    continue
                }
                // A struct this image lays out takes its fields' registers
                // (`SwiftLowering.aggregateRegisters`): no one of them is the
                // parameter, but those after it are placed. Declined,
                // `callPut(_ b: Box, _ k: Int)` seeded nothing, `k` included.
                if let banks = SwiftLowering.aggregateRegisters(
                    of: type, fieldMaps: fieldMaps, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
                    guard integerIndex + banks.integers <= 8, floatIndex + banks.floats <= 8 else { return nil }
                    integerIndex += banks.integers
                    floatIndex += banks.floats
                    continue
                }
                guard split.thrownType == nil,
                      let words = Self.integerRegisterFootprint(ofParameterType: type),
                      integerIndex + words <= 8
                else { return nil }
                // An `inout` parameter is its address, one register, as a
                // call site lays it out: `mix(_ h: inout Hasher, …)` passes
                // that `h` to `h.combine(v)` as `self` in x20.
                if type.hasPrefix("inout ") { registers["x\(integerIndex)"] = index }
                integerIndex += words
            }
        }
        return (registers, tables)
    }

    /// The register class of each source parameter of a Swift callee, in order,
    /// from its demangled name, or nil when that layout is not proven.
    ///
    /// A call site snapshots x0–x7 positionally, so a register the callee never
    /// reads renders as an argument (`one(arg0, arg1)` for `one(_: Int)`), and an
    /// integer after a Double reads in the Double's position. Laying the
    /// arguments out from the signature fixes both, but only where the footprint
    /// of every parameter is proven: integer-class and float-class scalars of
    /// one register each, on independent counters (`scalarParameterClass`),
    /// plus the String and `inout` footprints of `swiftCallArgumentSlots`.
    /// Declined: a parameter of any other type (an aggregate takes several
    /// registers, a generic or resilient one is indirect), a generic or
    /// specialized or closure or thunk name (trailing metadata and witness
    /// tables, other conventions), `async` (the context and continuation), and
    /// an instance method whose `self` may be a value type, which travels after
    /// the formals. A class method's `self` is in x20, an initializer's or a
    /// static method's metatype is in x20 or nowhere, so their formals start at
    /// x0 and are accepted.
    static func swiftCallArgumentLayout(
        callee: String, enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex
    ) -> [ScalarParameterClass]? {
        swiftCallArgumentSlots(callee: callee, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex)?
            .map(\.kind)
    }

    /// `swiftCallArgumentLayout` with each parameter's demangled type, which
    /// renders a constant in that slot (`2.5` for a Double, `true` for a Bool).
    /// `Module.(tick in _0A1B2C)` as `Module.tick`: a private declaration's
    /// discriminator is not part of how it is called.
    static func withoutPrivateDiscriminators(_ name: String) -> String {
        guard name.contains(" in _") else { return name }
        return name.replacingOccurrences(of: #"\(([A-Za-z_][A-Za-z0-9_]*) in _[0-9A-F]+\)"#,
                                         with: "$1", options: .regularExpression)
    }

    /// Whether `callee` is an instance property getter of `Swift.String`
    /// (`Swift.String.utf8.getter : Swift.String.UTF8View`), which takes
    /// exactly the String's two words and nothing else. Its `get` is
    /// nonmutating, so the words travel as the trailing formal, in x0, x1.
    static func isStringInstanceGetter(_ callee: String) -> Bool {
        guard callee.hasPrefix("Swift.String."), let colon = callee.range(of: ".getter : ") else { return false }
        let property = callee[callee.index(callee.startIndex, offsetBy: "Swift.String.".count) ..< colon.lowerBound]
        // A subscript's getter takes its index too.
        return !property.isEmpty && property != "subscript"
            && property.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Whether a property getter takes nothing in x0–x7: a static property's
    /// (the metatype rides in x20), a class instance property's (self in
    /// x20) or a global's. A value type's instance getter does not qualify,
    /// since a small struct's `self` travels in x0 onward. Subscripts take
    /// their index. Generic metadata, which a getter may also receive, is
    /// plumbing the renderer hides anyway.
    static func getterTakesNoArguments(_ callee: String, classTypeIndex: ClassTypeIndex) -> Bool {
        // A dispatch thunk's getter takes `self` in x20; x0 and x1 hold a
        // requirement's Self metadata and witness table, which printed as
        // two arguments: `Actor.unownedExecutor.getter(type metadata
        // accessor for Swift.MainActor(0), …)`.
        let isDispatchThunk = callee.hasPrefix(dispatchThunkPrefix)
        // A specialization of a qualifying getter only drops or re-owns
        // parameters (`<Arg[0] = Dead>` is the unused metatype).
        var name = isDispatchThunk ? String(callee.dropFirst(dispatchThunkPrefix.count)) : callee
        for prefix in ["function signature specialization <", "generic specialization <"] where name.hasPrefix(prefix) {
            guard let of = name.range(of: "> of ") else { return false }
            name = String(name[of.upperBound...])
        }
        guard let colon = name.range(of: " : ") else { return false }
        var base = withoutPrivateDiscriminators(String(name[..<colon.lowerBound]))
        guard base.hasSuffix(".getter") else { return false }
        base.removeLast(".getter".count)
        let isStatic = base.hasPrefix("static ")
        if isStatic { base.removeFirst("static ".count) }
        // A subscript's getter takes its index: `Grid.subscript.getter :
        // (Swift.Int) -> Swift.Int` read `subscript.getter(self: arg0)`
        // for `g[i]`.
        guard !base.isEmpty, base.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
              let dot = base.lastIndex(of: "."), !base[base.index(after: dot)...].isEmpty,
              base[base.index(after: dot)...] != "subscript"
        else { return false }
        let context = String(base[..<dot])
        return isDispatchThunk || isStatic || !context.contains(".") || classTypeIndex.isClass(context)
    }

    /// A setter as the function it is, for `swiftCallArgumentLayout`: a
    /// class instance property's, a static one's or a global's takes the new
    /// value from x0 (`self` or the metatype rides in x20), so `M.C.x.setter
    /// : Swift.Int` is `M.C.setter(Swift.Int) -> ()`. Its name prints no
    /// parameter list, so its arity came from its body, and a filtered run
    /// has no body for a callee it reached through a vtable: `self.x.setter()`
    /// and `self.s.setter(?, <the br x1 target>)` beside the whole image's
    /// `(?)`. Nil for anything else: a value type's non-mutating setter
    /// takes `self` after the value, and a subscript's takes its index.
    static func setterLayoutName(_ callee: String, classTypeIndex: ClassTypeIndex) -> String? {
        guard let colon = callee.range(of: " : ") else { return nil }
        var base = withoutPrivateDiscriminators(String(callee[..<colon.lowerBound]))
        guard base.hasSuffix(".setter") else { return nil }
        base.removeLast(".setter".count)
        let isStatic = base.hasPrefix("static ")
        if isStatic { base.removeFirst("static ".count) }
        guard !base.isEmpty, base.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
              let dot = base.lastIndex(of: "."), !base[base.index(after: dot)...].isEmpty,
              base[base.index(after: dot)...] != "subscript"
        else { return nil }
        let context = String(base[..<dot])
        guard isStatic || !context.contains(".") || classTypeIndex.isClass(context) else { return nil }
        return "\(isStatic ? "static " : "")\(context).setter(\(callee[colon.upperBound...])) -> ()"
    }

    /// An ordinary property's setter has one logical assigned value even
    /// when its value-type receiver or value cannot be placed in registers.
    /// This contract supplies no machine layout: a function-valued property
    /// is still one value, and a subscript or thunk is not an ordinary setter.
    static func ordinarySetterAssignedValueType(_ callee: String) -> String? {
        guard let marker = callee.range(of: ".setter : ") else { return nil }
        var base = withoutPrivateDiscriminators(String(callee[..<marker.lowerBound]))
        if base.hasPrefix("static ") { base.removeFirst("static ".count) }
        guard !base.isEmpty,
              base.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
              base.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
              let dot = base.lastIndex(of: ".")
        else { return nil }
        let property = base[base.index(after: dot)...]
        guard property != "subscript", property != "init", property != "deinit" else { return nil }
        let type = callee[marker.upperBound...].trimmingCharacters(in: .whitespaces)
        return type.isEmpty ? nil : type
    }

    static let dispatchThunkPrefix = "dispatch thunk of "

    /// Each source parameter's register bank, how many registers of it the
    /// parameter takes, and its demangled type. A scalar takes one; so does an
    /// `inout` parameter of any type, which is passed as its address. A
    /// `String` takes two integer registers (count and flags, then the object),
    /// and so does a `String?`, whose nil is an extra inhabitant
    /// (`takeOptString(nil, 7)` passes 0 in x0 and x1, 7 in x2). Any other
    /// parameter declines the whole layout, and so does a typed throw, whose
    /// error may travel through an extra pointer parameter.
    /// `anyContext` accepts a member of any type, a value type's included,
    /// whose `self` may follow the formal parameters: the slots are then
    /// only the leading ones.
    static func swiftCallArgumentSlots(
        callee: String, enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex,
        anyContext: Bool = false
    ) -> [(kind: ScalarParameterClass, registers: Int, type: String)]? {
        swiftCallArgumentLayout(callee: callee, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex,
                                anyContext: anyContext)
            .flatMap { $0.stack.isEmpty ? $0.slots : nil }
    }

    /// Whether a generic function's printed result is a tuple with a generic
    /// element, whose buffers come before the formals from x0.
    static func returnsGenericTupleFromX0(_ callee: String) -> Bool {
        guard let signature = DisassembledFunction.splitSignature(callee),
              let range = DisassembledFunction.outermostArgumentListRange(of: signature.head)
        else { return false }
        let name = signature.head[..<range.lowerBound].dropLast()
        guard let open = name.firstIndex(of: "<"), name.hasSuffix(">") else { return false }
        let clause = name[name.index(after: open)..<name.index(before: name.endIndex)]
        let names = (clause.range(of: " where ").map { clause[..<$0.lowerBound] } ?? clause)
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard names.allSatisfy({ $0.wholeMatch(of: #/[A-Z][0-9]*/#) != nil }) else { return false }
        let result = signature.result.trimmingCharacters(in: .whitespaces)
        return result.hasPrefix("(") && !result.hasPrefix("()") && mentionsGenericParameter(result, Set(names))
    }

    /// Whether `type` is a value of one of `generics`, or of an associated
    /// type of one (`A`, `A.Element`), which a generic function takes by
    /// address; `inout A` is an address too.
    static func isGenericValue(_ type: String, _ generics: Set<String>) -> Bool {
        guard !generics.isEmpty else { return false }
        var type = Substring(type.trimmingCharacters(in: .whitespaces))
        if type.hasPrefix("inout ") { type = type.dropFirst("inout ".count) }
        let root = type.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        return generics.contains(root) && type.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    }

    /// The type a method of `callee` belongs to: `M.W.take(…)` -> `M.W`.
    /// Nil for a free function or a name this cannot split.
    static func valueMethodReceiver(_ callee: String) -> String? {
        guard let signature = DisassembledFunction.splitSignature(callee),
              let range = DisassembledFunction.outermostArgumentListRange(of: signature.head)
        else { return nil }
        let name = withoutPrivateDiscriminators(String(signature.head[..<range.lowerBound].dropLast()))
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
              let dot = name.lastIndex(of: "."), name[..<dot].contains(".")
        else { return nil }
        return String(name[..<dot])
    }

    /// Whether the metatype of `instance` is one word: a generic
    /// parameter's (`A.Type`, `A1.Type`), which is its metadata pointer, or
    /// a class's, whose metatype is thick. A concrete struct or enum's
    /// metatype is thin and takes no register, and a protocol's carries
    /// witness tables, so neither is placed: `container<A>(keyedBy:
    /// A1.Type)` read `container(?)`.
    static func isOneWordMetatype(_ instance: String, _ generics: Set<String>, _ classTypeIndex: ClassTypeIndex) -> Bool {
        if generics.contains(instance) { return true }
        return classTypeIndex.isClass(instance)
    }

    /// The type parameters a demangled signature head declares in its
    /// generic clause (`M.f<A, B where A: P>(…)`): A and B.
    static func genericParameterNames(in head: String) -> Set<String> {
        guard let range = DisassembledFunction.outermostArgumentListRange(of: head) else { return [] }
        let name = head[..<range.lowerBound].dropLast()
        guard let open = name.firstIndex(of: "<"), name.hasSuffix(">") else { return [] }
        let clause = name[name.index(after: open)..<name.index(before: name.endIndex)]
        let names = (clause.range(of: " where ").map { clause[..<$0.lowerBound] } ?? clause)
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard names.allSatisfy({ $0.wholeMatch(of: #/[A-Z][0-9]*/#) != nil }) else { return [] }
        return Set(names)
    }

    /// Whether `type` names one of `generics` as a whole word.
    static func mentionsGenericParameter(_ type: String, _ generics: Set<String>) -> Bool {
        var word = ""
        for character in type + " " {
            if character.isLetter || character.isNumber || character == "_" || character == "." {
                word.append(character)
            } else {
                if generics.contains(word.split(separator: ".").first.map(String.init) ?? "") && !word.hasPrefix(".") {
                    return true
                }
                word = ""
            }
        }
        return false
    }

    /// The slots of the parameters that fit in registers, and how many
    /// parameters follow them on the stack. Past x7 or v7 a parameter's
    /// words go to the stack, packed to their own alignment, and so does
    /// every parameter after it here: each renders `?`. `_assertionFailure(_:
    /// _:file:line:flags:)` takes ten words, and declined whole it read
    /// x0-x7 as eight arguments.
    static func swiftCallArgumentLayout(
        callee: String, enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex,
        anyContext: Bool = false, fieldMaps: [String: FieldMap] = [:]
    ) -> SwiftArgumentLayout? {
        // A dispatch thunk calls a class method or a protocol requirement
        // through its vtable or witness table: `self` travels in x20 and the
        // formal parameters from x0, and a requirement's Self metadata and
        // witness table come after them. `dispatch thunk of
        // GaugeKit.Gauge.scaled(by:)` with an untracked x0 read
        // `scaled(self: g)`, as if it took nothing.
        let isDispatchThunk = callee.hasPrefix(dispatchThunkPrefix)
        var declared = isDispatchThunk ? String(callee.dropFirst(dispatchThunkPrefix.count)) : callee
        // A subscript getter prints its parameters as a function type,
        // `Grid.subscript.getter : (Swift.Int) -> Swift.Int`, and takes
        // them as a method takes its own.
        if let colon = declared.range(of: ".subscript.getter : ("), !declared[..<colon.lowerBound].contains(" ") {
            declared.replaceSubrange(colon, with: ".subscript(")
        }
        // An async callee takes its context in x22 and its formals as a
        // synchronous one does, unless its result is indirect, whose buffer
        // then comes first in x0 (swift/lib/IRGen/GenCall.cpp, the async
        // signature). Only a result proven to travel in registers is laid
        // out here.
        guard let signature = DisassembledFunction.splitSignature(declared),
              !signature.isAsync || SwiftLowering.of(signature.result, enumCaseIndex: enumCaseIndex,
                                                     classTypeIndex: classTypeIndex).isDirect,
              let range = DisassembledFunction.outermostArgumentListRange(of: signature.head)
        else { return nil }
        var name = Substring(Self.withoutPrivateDiscriminators(String(signature.head[..<range.lowerBound].dropLast())))
        let isStatic = name.hasPrefix("static ")
        if isStatic { name = name.dropFirst("static ".count) }
        // The module an extension is declared in does not change how its
        // members are called. The prefix failed the identifier test below, so
        // `static (extension in Foundation):Swift.String.
        // _unconditionallyBridgeFromObjectiveC(Swift.Optional<__C.NSString>)`,
        // one word in x0, went positional and read every register the thunk
        // still held: `(arg1, ?, arg0, arg1, arg2)`. An instance member of a
        // value type stays positional: its `self` words come after the
        // formals, and the `anyContext` layout trims a word still holding its
        // entry value, which there is `self` itself.
        if name.hasPrefix("(extension in "), let close = name.range(of: "):") {
            guard !anyContext else { return nil }
            name = name[close.upperBound...]
        }
        // A generic function's clause (`M.gen<A where A: P>`) names its type
        // parameters. A value of one is passed indirectly, one pointer, and the
        // metadata and witness tables follow the formals, which this lays out
        // without them (swift/docs/ABI/CallingConvention.rst).
        var genericParameters: Set<String> = []
        if let open = name.firstIndex(of: "<"), name.hasSuffix(">") {
            let clause = name[name.index(after: open)..<name.index(before: name.endIndex)]
            let names = (clause.range(of: " where ").map { clause[..<$0.lowerBound] } ?? clause)
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !names.isEmpty, names.allSatisfy({ $0.wholeMatch(of: #/[A-Z][0-9]*/#) != nil }) else { return nil }
            genericParameters = Set(names)
            // A member's own parameters are named in the requirements only
            // (`container<A where A1: Swift.CodingKey>(A1.Type)`: A is the
            // protocol's Self, A1 the method's Key). A demangled type is
            // module-qualified, so a bare `A1` there is a parameter.
            if let whereRange = clause.range(of: " where ") {
                let words = clause[whereRange.upperBound...].split { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
                for word in words {
                    let root = word.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
                    if root.wholeMatch(of: #/[A-Z][0-9]*/#) != nil { genericParameters.insert(root) }
                }
            }
            name = name[..<open]
            // A tuple result with a generic element is not returned through
            // x8: an indirect result beside a direct one, or two indirect ones,
            // take their buffers first, from x0 (GenCall.cpp, `CanUseSRet =
            // false`), and laid out from x0 `split<A>(_: A, _: Int) -> (A,
            // Swift.Int)` read the buffer as its `x`.
            let result = signature.result.trimmingCharacters(in: .whitespaces)
            if result.hasPrefix("("), !result.hasPrefix("()"), Self.mentionsGenericParameter(result, genericParameters) {
                return nil
            }
        }
        // Operator declarations carry their fixity after the spelling. They
        // retain their declared operands even when their physical ABI cannot
        // be placed, so two unknown equality operands render (?, ?), not ().
        let operatorArity: Int?
        if let fixity = ["infix", "prefix", "postfix"].first(where: { name.hasSuffix(" " + $0) }) {
            operatorArity = fixity == "infix" ? 2 : 1
            name = name.dropLast(fixity.count + 1)
        } else {
            operatorArity = nil
        }
        guard !name.isEmpty, let dot = name.lastIndex(of: ".") else { return nil }
        let context = String(name[..<dot]), member = name[name.index(after: dot)...]
        if operatorArity != nil {
            // This bounded ASCII spelling excludes closure, specialization,
            // witness and other thunk prose after the existing sanctioned
            // dispatch-thunk normalization. Unsupported spellings still decline.
            guard !context.isEmpty, !member.isEmpty,
                  context.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
                  context.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
                  member.allSatisfy({ "/=-+!*%<>&|^?~".contains($0) })
            else { return nil }
        } else {
            // An ordinary qualified identifier only: no `closure #1 in`,
            // `specialization <…> of`, `(X in _HASH)` or thunk prose.
            guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
            else { return nil }
        }
        let isFreeFunction = !context.contains(".")
        guard anyContext || isDispatchThunk || isFreeFunction || isStatic || member == "init"
                || classTypeIndex.isClass(context)
        else { return nil }

        let parameters = DisassembledFunction.splitTopLevelArguments(signature.head[range])
        if let operatorArity, parameters.count != operatorArity { return nil }
        var layout: [(kind: ScalarParameterClass, registers: Int, type: String)] = []
        var integers = 0, floats = 0, spilled = false
        var stack: [(type: String, kind: ScalarParameterClass)] = []
        var splitStackWords = 0
        for parameter in parameters {
            let type = parameterType(parameter)
            let kind: ScalarParameterClass, registers: Int
            if let scalar = scalarParameterClass(parameter, enumCaseIndex: enumCaseIndex,
                                                 classTypeIndex: classTypeIndex) {
                (kind, registers) = (scalar, 1)
            } else if Self.isGenericValue(type, genericParameters) {
                // Its address.
                (kind, registers) = (.integer, 1)
            } else if type.hasSuffix(".Type"), Self.isOneWordMetatype(String(type.dropLast(".Type".count)),
                                                                   genericParameters, classTypeIndex) {
                (kind, registers) = (.integer, 1)
            } else if signature.thrownType == nil, let words = integerRegisterFootprint(ofParameterType: type) {
                (kind, registers) = (.integer, words)
            // A complete storage layout does not prove a newly admitted
            // operator's aggregate ABI. A resilient two-Int value is passed
            // by address, so sizing it as two integer registers reads the
            // following operand from x2 instead of x1. Keep such operands
            // and everything after them unplaced. Void is a known ABI shape.
            } else if operatorArity == nil || type == "()" || type == "Swift.Void",
                      let banks = SwiftLowering.aggregateRegisters(
                of: type, fieldMaps: fieldMaps, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
                (kind, registers) = (.aggregate(integers: banks.integers, floats: banks.floats), 1)
            } else {
                // A struct, tuple, SIMD vector or closure takes registers its
                // name does not give (`Mix { Int, Double, Int }` takes x0, d0,
                // x1), so neither it nor any later parameter can be placed:
                // each renders `?`, as a parameter past x7 does, and the ones
                // before it keep their values. Read by position instead,
                // `fMix(Mix(i: k, d: 1.5, j: 7), 2.0)` rendered `fMix(arg0,
                // 7)`, the 7 as the Double, and `fPt(Pt(x: a, y: 3.0), k)`
                // rendered `fPt(arg1)`, `k` as the Pt.
                stack.append((type, .integer))
                spilled = true
                continue
            }
            switch kind {
            case .integer: integers += registers
            case .floating: floats += registers
            case .aggregate(let x, let v): integers += x; floats += v
            }
            if spilled || integers > 8 || floats > 8 {
                // A StaticString renders only its first word, so it is
                // placed while that word is in a register: the file name
                // of `_assertionFailure(_:_:file:line:flags:)` with a
                // StaticString message starts in x6.
                if !spilled, kind == .integer, type == "Swift.StaticString", integers - registers < 8 {
                    layout.append((kind, 8 - (integers - registers), type))
                    splitStackWords = integers - 8
                } else {
                    stack.append((type, kind))
                }
                spilled = true
            } else {
                layout.append((kind, registers, type))
            }
        }
        return SwiftArgumentLayout(slots: layout, stack: stack, splitStackWords: splitStackWords)
    }

    /// A Swift call's parameters: those in registers, then those on the
    /// stack, in order, after the last `splitStackWords` words of a
    /// StaticString that began in registers.
    struct SwiftArgumentLayout {
        let slots: [(kind: ScalarParameterClass, registers: Int, type: String)]
        let stack: [(type: String, kind: ScalarParameterClass)]
        let splitStackWords: Int
        var unplaced: Int { stack.count }
    }

    /// The byte size of each word a parameter of `type` puts on the stack,
    /// or nil for a type this cannot size. A String is two words; a
    /// StaticString a pointer, a count and a flags byte
    /// (stdlib/public/core/StaticString.swift:77-92).
    static func stackWordSizes(ofParameterType type: String) -> [Int]? {
        switch type {
        case "Swift.Int", "Swift.UInt", "Swift.Int64", "Swift.UInt64": return [8]
        case "Swift.Int32", "Swift.UInt32": return [4]
        case "Swift.Int16", "Swift.UInt16": return [2]
        case "Swift.Int8", "Swift.UInt8", "Swift.Bool": return [1]
        case _ where twoWordStringTypes.contains(type): return [8, 8]
        case "Swift.StaticString": return [8, 8, 1]
        default: return nil
        }
    }

    /// The words of the stack parameters, read from the eight-byte slots a
    /// call's stores fill. Apple arm64 packs each word at the next offset
    /// its own size aligns, where AAPCS64 would round each to eight bytes.
    /// A word is read only from a slot whose store began at its offset with
    /// its width. The first parameter that cannot be read stops the
    /// reading: it and every later one are nil.
    static func stackParameterWords(
        _ layout: SwiftArgumentLayout, stackArguments: [AbstractValue], widths: [Int]
    ) -> [[AbstractValue]?] {
        var offset = 0
        var readable = true
        func read(_ size: Int) -> AbstractValue? {
            offset = (offset + size - 1) / size * size
            defer { offset += size }
            guard offset % 8 == 0 else { return nil }
            let slot = offset / 8
            guard slot < stackArguments.count, slot < widths.count, widths[slot] == size else { return nil }
            return stackArguments[slot]
        }
        for size in [8, 8, 1].suffix(layout.splitStackWords) where read(size) == nil { readable = false }
        return layout.stack.map { parameter in
            guard readable, parameter.kind == .integer,
                  let sizes = stackWordSizes(ofParameterType: parameter.type)
            else { readable = false; return nil }
            let words = sizes.map(read)
            guard words.allSatisfy({ $0 != nil }) else { readable = false; return nil }
            return words.compactMap { $0 }
        }
    }

    /// A C function's arguments as its SDK declaration places them, for
    /// one `knownCArity` does not count: an integer or pointer takes the next
    /// x register, a float or double the next v register. Without it
    /// `glVertex3f(x, y, z)`, whose operands are all in v registers, took the
    /// x0 it found. Where a struct goes depends on how it is passed (an HFA
    /// such as CGRect in v registers, a small one in x registers, a large one
    /// by address), so it and every parameter after it are `unplaced`, each
    /// a `?`: `CGRectGetMinY(rect)` took x0 too. An HFA (`D4`, a CGRect)
    /// takes its `n` v registers and renders `?`, and what follows it is
    /// placed; one that does not fit in the v registers left goes on the
    /// stack, so it and what follows are unplaced. Nil for a variadic
    /// declaration, one with only integer parameters or none, or one that
    /// places more parameters than registers.
    static func cPrototypeLayout(
        callee: String
    ) -> (slots: [(kind: ScalarParameterClass, registers: Int, type: String)], unplaced: Int)? {
        DisassembledFunction.cPrototype(of: callee).flatMap(cPrototypeLayout(prototype:))
    }

    static func cPrototypeLayout(
        prototype: DisassembledFunction.CPrototype
    ) -> (slots: [(kind: ScalarParameterClass, registers: Int, type: String)], unplaced: Int)? {
        guard !prototype.isVariadic, prototype.parameters.contains(where: { $0 != "i" }) else { return nil }
        var integers = 0, floats = 0
        var slots: [(kind: ScalarParameterClass, registers: Int, type: String)] = []
        for parameter in prototype.parameters {
            switch parameter {
            case _ where DisassembledFunction.cIntegerParameterTypes[parameter] != nil:
                integers += 1
                slots.append((.integer, 1, DisassembledFunction.cIntegerParameterTypes[parameter] ?? "Swift.Int"))
            case "f": floats += 1; slots.append((.floating, 1, "Swift.Float"))
            case "d": floats += 1; slots.append((.floating, 1, "Swift.Double"))
            default:
                guard parameter.count == 2, let members = Int(parameter.dropFirst()), floats + members <= 8
                else { return (slots, prototype.parameters.count - slots.count) }
                floats += members
                slots.append((.floating, members, ""))
            }
        }
        guard integers <= 8, floats <= 8 else { return nil }
        return (slots, 0)
    }

    /// A value whose every byte is zero: `0`, or a vector register's words
    /// all `0` (`movi v0.2d, #0`).
    static func isAllZero(_ value: AbstractValue) -> Bool {
        switch value {
        case .immediate(0): return true
        case .aggregate(let words): return !words.isEmpty && words.allSatisfy(isAllZero)
        default: return false
        }
    }

    /// The mangled integer scalars: a struct of only these is returned in x
    /// registers, not v registers.
    static let integerScalarMangledTypes: Set<String> = [
        "Si", "Su", "Sb", "s4Int8V", "s5UInt8V", "s5Int16V", "s6UInt16V", "s5Int32V", "s6UInt32V",
        "s5Int64V", "s6UInt64V",
    ]

    /// Whether a struct of this layout comes back in x0 and x1: 9 to 16
    /// bytes of integer scalars only. One with a floating-point field may
    /// come back in v registers instead.
    static func returnsInTwoIntegerRegisters(_ map: FieldMap) -> Bool {
        (9...16).contains(map.instanceSize) && !map.fields.isEmpty
            && map.fields.allSatisfy { integerScalarMangledTypes.contains($0.typeMangledName) }
    }

    /// The two-word String types `swiftCallArgumentSlots` lays out.
    /// `_StringGuts` is String's own two words (`_object: _StringObject`,
    /// stdlib/public/core/StringGuts.swift): `_stringCompareWithSmolCheck`
    /// compares two of them.
    static let twoWordStringTypes: Set<String> = ["Swift.String", "Swift.Optional<Swift.String>", "Swift.String?",
                                                  "Swift._StringGuts"]
    /// The same types as a field record's mangled names spell them.
    static let twoWordStringMangledTypes: Set<String> = ["SS", "SSSg"]

    /// The integer registers a parameter that is not a scalar takes, for the
    /// shapes whose footprint the Swift ABI fixes whatever the image holds:
    /// an `inout` address, a String's two words and an Optional scalar's
    /// payload and tag. Nil for anything else.
    static func integerRegisterFootprint(ofParameterType type: String) -> Int? {
        if type.hasPrefix("inout "), type.count > "inout ".count { return 1 }
        if twoWordStringTypes.contains(type) { return 2 }
        // stdlib/public/core/StaticString.swift:77-92: a start pointer (or
        // a scalar), a code-unit count and a flags byte.
        if type == "Swift.StaticString" { return 3 }
        if let payload = optionalScalarPayload(ofParameterType: type) { return payload.bytes == 8 ? 2 : 1 }
        return nil
    }

    /// The payload type and size of an Optional of a fixed-width scalar,
    /// which has no spare bits for nil: Swift passes the payload's bytes, then
    /// a tag byte that is 1 for nil, in integer registers. An eight-byte
    /// payload takes two, the payload in the first (a Double's bits too, not
    /// a d register) and the tag in the second; a narrower one packs both into
    /// one, the tag just above the payload (`Int32?`: bits 32-39). Nil for
    /// any other type.
    static func optionalScalarPayload(ofParameterType type: String) -> (type: String, bytes: Int)? {
        let wrapped: String
        if type.hasPrefix("Swift.Optional<"), type.hasSuffix(">") {
            wrapped = String(type.dropFirst("Swift.Optional<".count).dropLast())
        } else if type.hasSuffix("?") {
            wrapped = String(type.dropLast())
        } else {
            return nil
        }
        switch wrapped {
        case "Swift.Int", "Swift.UInt", "Swift.Int64", "Swift.UInt64", "Swift.Double", "Swift.CGFloat",
             "CoreGraphics.CGFloat":
            return (wrapped, 8)
        case "Swift.Int32", "Swift.UInt32", "Swift.Float": return (wrapped, 4)
        case "Swift.Int16", "Swift.UInt16": return (wrapped, 2)
        case "Swift.Int8", "Swift.UInt8": return (wrapped, 1)
        default: return nil
        }
    }

    /// An Optional scalar argument from its registers, as
    /// `.aggregate([payload, tag])` when the tag is a known 0 or 1, so the
    /// renderer spells the payload or `nil`; a narrower payload's one register
    /// is split at the tag byte first. Unknown otherwise: a payload under an
    /// unknown tag is not that value.
    static func optionalScalarArgument(_ words: [AbstractValue], payloadBytes: Int) -> AbstractValue {
        let payload: AbstractValue, tag: UInt64
        if words.count == 2 {
            guard case .immediate(let bits) = words[1] else { return .unknown }
            (payload, tag) = (words[0], bits & 0xFF)
        } else {
            guard case .immediate(let bits) = words.first, payloadBytes < 8 else { return .unknown }
            let width = UInt64(payloadBytes * 8)
            (payload, tag) = (.immediate(bits & ((1 << width) - 1)), (bits >> width) & 0xFF)
        }
        switch tag {
        case 1: return .aggregate([.immediate(0), .immediate(1)])
        case 0 where payload != .unknown: return .aggregate([payload, .immediate(0)])
        default: return .unknown
        }
    }

    /// Maps each source-parameter index that is a no-payload enum to that enum's
    /// demangled type name, keyed the same way `.argument(index)` is numbered.
    /// This is what lets a `c == .case` comparison over an enum parameter name
    /// the compared tag: the parameter list carries the type, the index carries
    /// the register binding. Empty when the function has no enum parameters or no
    /// demangled signature.
    static func swiftEnumArgumentTypes(
        of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex
    ) -> [Int: String] {
        guard function.objcMethod == nil, let name = function.layoutName,
              Self.isSwiftMangled(function.symbol),
              let signature = DisassembledFunction.splitSignature(name)?.head
        else { return [:] }
        guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: signature)
        else { return [:] }
        let parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        var types: [Int: String] = [:]
        for (index, parameter) in parameters.enumerated() {
            var type = parameter
            if let colon = type.range(of: ": ", options: .backwards) {
                type = String(type[colon.upperBound...])
            }
            type = type.trimmingCharacters(in: .whitespaces)
            if enumCaseIndex.isNoPayloadEnum(type) { types[index] = type }
        }
        return types
    }

    /// The source-parameter indices that are `Swift.Bool`, keyed like
    /// `.argument(index)`. A Bool argument is a 0/1 value, so recognizing it
    /// lets `!b` (lowered `(arg ^ 1) & 1`) fold to `!arg` and `b == true`/`b`
    /// used in a condition read cleanly rather than as a masked integer test.
    static func swiftBoolArgumentIndices(of function: DisassembledFunction) -> Set<Int> {
        guard function.objcMethod == nil, let name = function.layoutName,
              Self.isSwiftMangled(function.symbol),
              let signature = DisassembledFunction.splitSignature(name)?.head
        else { return [] }
        guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: signature)
        else { return [] }
        let parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        var indices: Set<Int> = []
        for (index, parameter) in parameters.enumerated() {
            var type = parameter
            if let colon = type.range(of: ": ", options: .backwards) {
                type = String(type[colon.upperBound...])
            }
            if type.trimmingCharacters(in: .whitespaces) == "Swift.Bool" { indices.insert(index) }
        }
        return indices
    }

    /// The source-parameter indices that are floating-point, plus whether the
    /// function's float type is double-precision. A float immediate is stored as
    /// an IEEE bit pattern; recognizing a float-valued expression (one reaching a
    /// float parameter) lets a literal operand in it render as `3.14` instead of
    /// `0x40091eb851eb851f`. Nil when the function has no floating-point in its
    /// signature, so a non-float body never reinterprets an integer as a float.
    static func swiftFloatArgumentInfo(
        of function: DisassembledFunction
    ) -> (indices: Set<Int>, isDouble: Bool)? {
        guard function.objcMethod == nil, let name = function.layoutName,
              Self.isSwiftMangled(function.symbol),
              let split = DisassembledFunction.splitSignature(name)
        else { return nil }
        let doubles: Set<String> = [
            "Swift.Double", "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat",
        ]
        let floats: Set<String> = ["Swift.Float", "Swift.Float32", "Swift.Float16"]
        func normalize(_ raw: Substring) -> String {
            var type = String(raw)
            if let colon = type.range(of: ": ", options: .backwards) {
                type = String(type[colon.upperBound...])
            }
            return type.trimmingCharacters(in: .whitespaces)
        }
        var indices: Set<Int> = []
        var sawDouble = false, sawFloat = false
        let signature = split.head
        if let paramsRange = DisassembledFunction.outermostArgumentListRange(of: signature) {
            for (index, parameter) in DisassembledFunction.splitTopLevelArguments(signature[paramsRange]).enumerated() {
                let type = normalize(parameter[...])
                if doubles.contains(type) { indices.insert(index); sawDouble = true }
                else if floats.contains(type) { indices.insert(index); sawFloat = true }
            }
        }
        let returnType = split.result
        if doubles.contains(returnType) { sawDouble = true }
        else if floats.contains(returnType) { sawFloat = true }
        guard sawDouble || sawFloat else { return nil }
        return (indices, sawDouble)
    }

    /// The enum type owning a `…__derived_enum_equals` callee (the compiler's
    /// synthesized enum `Equatable.==`), or nil when the callee isn't that
    /// method. `static Module.Color.__derived_enum_equals` → `Module.Color`.
    static func derivedEnumEqualsType(_ callee: String) -> String? {
        guard let range = callee.range(of: ".__derived_enum_equals") else { return nil }
        var name = String(callee[..<range.lowerBound])
        if let arrow = name.range(of: "→ ", options: .backwards) {
            name = String(name[arrow.upperBound...])
        }
        if name.hasPrefix("static ") { name = String(name.dropFirst("static ".count)) }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Render an integer immediate for pseudocode. Small non-negatives print as
    /// decimal; a small negative — the two's-complement bit pattern of a signed
    /// value, e.g. `0xffffffffffffffff` for `-1` — prints as a signed decimal so
    /// a negative literal reads as `-1` rather than a 16-digit hex; everything
    /// else (large positives, bit masks, addresses, hashes) prints as hex, where
    /// the bit pattern is what a reader needs.
    ///
    /// The negative window is deliberately narrow (down to `-0x10000`): a genuine
    /// large *unsigned* value near `UInt64.max` must never be relabelled negative,
    /// and real negative literals are overwhelmingly small in magnitude.
    /// Whether a frame address less a size (`frame - n`, nested for
    /// successive allocations) subtracts a size with an unknown part.
    static func sizeIsUnknown(_ value: AbstractValue) -> Bool {
        func unknownPart(_ value: AbstractValue) -> Bool {
            switch value {
            case .unknown, .callResultHigh, .loadedThrough, .loadedFrom, .selfIsaSnapshot, .genericWitnessTable,
                 .existentialWitnessTable: return true
            case .binary(_, let lhs, let rhs): return unknownPart(lhs) || unknownPart(rhs)
            case .unary(_, let operand): return unknownPart(operand)
            default: return false
            }
        }
        guard case .binary(.subtract, let lhs, let rhs) = value, !ValueTracer.containsFrame(rhs) else { return false }
        return unknownPart(rhs) || sizeIsUnknown(lhs)
    }

    static func renderImmediate(_ v: UInt64) -> String {
        if v < 4096 { return String(v) }
        let signed = Int64(bitPattern: v)
        if signed < 0, signed >= -0x1_0000 { return String(signed) }
        return "0x" + String(v, radix: 16)
    }

    /// Name a loop-carried induction variable by id — `i`, `j`, `k`, then `i3`, …
    /// (skips `l`/`m`/`n`, which read poorly next to `1` and common loop bounds).
    /// `var i = 3`, or `var i = arg0` for a counter that starts from an
    /// argument.
    static func loopDeclaration(_ binding: LoopInitialization) -> String {
        "var \(binding.name) = \(binding.argument.map { "arg\($0)" } ?? renderImmediate(binding.value))"
    }

    static func inductionVariableName(_ id: Int) -> String {
        ["i", "j", "k"].indices.contains(id) ? ["i", "j", "k"][id] : "i\(id)"
    }

    /// A constant rendered per its declared type: a `Bool` as `true`/`false`, a
    /// floating-point value as its decimal. A float immediate holds the IEEE-754
    /// bit pattern, which as raw hex (`0x400921f9f01b866e`) reads like a garbage
    /// address; interpreting the bits per the type recovers `3.14159`. Nil when
    /// the type isn't one whose constants need a typed reading — the caller then
    /// falls back to the plain integer rendering.
    /// The standard library's literal initializer, which -Onone calls for
    /// every String literal with its bytes, their count and whether they are
    /// ASCII.
    static let builtinStringLiteralInit =
        "Swift.String.init(_builtinStringLiteral: Builtin.RawPointer, utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1)"

    /// A computed result of a narrow integer type is its register's low bits
    /// at the type's signedness: the caller reads no more. Rendered whole,
    /// `add16(_ x: UInt16) -> UInt16 { x &+ 72 }` read `return (((arg0 &
    /// 0xffffffff) + 72) & 0xffffffff)`, which is 0x10047 for 0xffff where
    /// the function returns 0x47. An argument or call result is that type
    /// already, and an expression already masked (or sign-extended) to the
    /// width is left as it is.
    static func narrowedResult(_ value: AbstractValue, type: String) -> AbstractValue {
        let widths: [String: (bits: Int, signed: Bool)] = [
            "Swift.Int8": (8, true), "Swift.Int16": (16, true), "Swift.Int32": (32, true),
            "Swift.UInt8": (8, false), "Swift.UInt16": (16, false), "Swift.UInt32": (32, false),
        ]
        guard let (bits, signed) = widths[type] else { return value }
        switch value {
        case .binary, .unary: break
        default: return value
        }
        let mask = (UInt64(1) << UInt64(bits)) - 1
        let shift = UInt64(64 - bits)
        // A mask covering the whole width says nothing the narrowing does not.
        var inner = value
        if case .binary(.bitAnd, let masked, .immediate(let existing)) = value, existing & mask == mask {
            inner = masked
        }
        if signed {
            if case .binary(.arithmeticShiftRight, .binary(.shiftLeft, _, .immediate(let left)), .immediate(let right)) = value,
               left == right, left >= shift {
                return value
            }
            return .binary(.arithmeticShiftRight, .binary(.shiftLeft, inner, .immediate(shift)), .immediate(shift))
        }
        if case .binary(.bitAnd, _, .immediate(let existing)) = value, existing <= mask { return value }
        return .binary(.bitAnd, inner, .immediate(mask))
    }

    /// In a proven floating context, an immediate (including each selected
    /// arm) is IEEE bits. Other scalar types keep their existing meaning.
    static func floatingPointValue(_ value: AbstractValue, type: String) -> AbstractValue {
        let bits: Int
        switch type {
        case "Swift.Double", "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat": bits = 64
        case "Swift.Float", "Swift.Float32": bits = 32
        case "Swift.Float16": bits = 16
        default: return value
        }
        return ValueTracer.floatOperand(value, bits: bits)
    }

    static func renderTypedConstant(bits: UInt64, type: String) -> String? {
        switch type {
        case "Swift.Bool":
            if bits == 0 { return "false" }
            if bits == 1 { return "true" }
            return nil
        case "Swift.Double", "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat":
            return String(Double(bitPattern: bits))
        case "Swift.Float", "Swift.Float32":
            return String(Float(bitPattern: UInt32(truncatingIfNeeded: bits)))
        case "Swift.Float16":
            return String(Float(Float16(bitPattern: UInt16(truncatingIfNeeded: bits))))
        // A narrow integer is its register's low bits, read at the declared
        // signedness: the callee reads no more, and the caller may leave the
        // rest as it likes. Read whole, `takeNarrow(-1, -2, -3, …)` rendered
        // `takeNarrow(255, 0xfffe, 0xfffffffd, …)`.
        case "Swift.Int8": return String(Int8(truncatingIfNeeded: bits))
        case "Swift.Int16": return String(Int16(truncatingIfNeeded: bits))
        case "Swift.Int32": return String(Int32(truncatingIfNeeded: bits))
        case "Swift.UInt8": return renderImmediate(UInt64(UInt8(truncatingIfNeeded: bits)))
        case "Swift.UInt16": return renderImmediate(UInt64(UInt16(truncatingIfNeeded: bits)))
        case "Swift.UInt32": return renderImmediate(UInt64(UInt32(truncatingIfNeeded: bits)))
        default:
            return nil
        }
    }

    /// For a nonmutating instance method of a small HFA-float struct, the SIMD
    /// register → `self` field-offset map to seed (plus the resolved self type
    /// and its field map, so the fields name). `self` arrives decomposed across
    /// `d0…` in that ABI; this is what lets `Vec2.magnitude()` read `self.x`.
    ///
    /// Two structural guards keep it from fabricating: the demangled name must be
    /// an instance method (not `static`, not `.init`) of a type whose layout is a
    /// genuine HFA (`FieldMap.homogeneousFloatFieldOffsets`), and the body must
    /// never use `x20` as a memory base — a `[x20, …]` access proves `self` is the
    /// pointer form (a mutating or indirectly-passed struct, or a class), where
    /// decomposing SIMD registers would be wrong.
    static func swiftValueTypeSelfFields(
        of function: DisassembledFunction, fieldMaps: [String: FieldMap]
    ) -> (typeName: String, fieldMap: FieldMap,
          seeded: [String: AbstractValue], argumentFieldMaps: [Int: FieldMap])? {
        guard function.objcMethod == nil, let name = function.analysisName,
              Self.isSwiftMangled(function.symbol), !name.hasPrefix("static ")
        else { return nil }

        // Two shapes: a method (`Type.method(params) -> Ret`) or a computed
        // property's getter (`Type.property.getter : Ret`, which takes no explicit
        // parameters). `.modify`/`.read` accessors are coroutines whose self is
        // the x20 pointer, so they are excluded.
        let selfTypeName: String
        let parameters: [String]
        if let signature = DisassembledFunction.splitSignature(name)?.head {
            guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: signature)
            else { return nil }
            let qualifiedMethod = signature[..<signature.index(before: paramsRange.lowerBound)]
            guard let dot = qualifiedMethod.lastIndex(of: ".") else { return nil }
            let methodName = qualifiedMethod[qualifiedMethod.index(after: dot)...]
            guard methodName != "init", !methodName.isEmpty else { return nil }
            selfTypeName = String(qualifiedMethod[..<dot])
            parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        } else {
            var base = name
            if let colon = base.range(of: " : ") { base = String(base[..<colon.lowerBound]) }
            guard base.hasSuffix(".getter") else { return nil }
            base = String(base.dropLast(".getter".count)) // Type.property
            guard let propertyDot = base.lastIndex(of: "."),
                  case let typePart = String(base[..<propertyDot]), !typePart.isEmpty,
                  base.index(after: propertyDot) < base.endIndex
            else { return nil }
            selfTypeName = typePart
            parameters = []
        }

        // The type must be a register-passed value struct — a float HFA (self in
        // SIMD registers) or a small integer struct (self in x0[/x1]) — and `self`
        // must not be accessed through x20 (which would be the pointer form).
        guard let selfMap = Self.namedFieldMap(selfTypeName, in: fieldMaps),
              !function.instructions.contains(where: { $0.text.contains("[x20") })
        else { return nil }

        // A nonmutating value `self` is the last ordinary parameter: the formal
        // arguments fill each register bank first, and an HFA `self` follows
        // them in the SIMD bank. Seeding it first labelled `scaled(_ factor:)`'s
        // d0 as self.x (native: d0 = factor, d1/d2 = self). Any non-float-scalar,
        // non-HFA parameter bails the whole decomposition so the register
        // assignment can't drift. (Recovered from the pre-merge stash 983aa25.)
        var seeded: [String: AbstractValue] = [:]
        var floatIndex = 0
        var integerIndex = 0
        let floatingSelfOffsets = selfMap.homogeneousFloatFieldOffsets
        // A small integer struct's self follows its formals in the general
        // registers: `g(_ k:)` takes k in x0 and self.s in x1, and `h(_ a:,
        // _ b:)` self.s in x2. Seeded only when every formal is one register
        // (the loop below declines anything else), after the last of them.
        var integerSelfAfterFormals: [Int]?
        if floatingSelfOffsets != nil {
            // Seeded after the formal arguments, below.
        } else if let selfOffsets = selfMap.wordIntegerFieldOffsetsInRegisters, !parameters.isEmpty {
            integerSelfAfterFormals = selfOffsets
        } else if let selfOffsets = selfMap.wordIntegerFieldOffsetsInRegisters, parameters.isEmpty {
            // A small integer struct shares the general-register bank with its
            // parameters, and (unlike a float HFA in its own SIMD bank) `self`
            // there is passed AFTER the formal parameters — so seeding it as x0/x1
            // is only safe when there are none. Restrict to getters; a method with
            // parameters declines rather than mis-assign registers (which would
            // mis-reconstruct a non-commutative body like `a * k + b`).
            for offset in selfOffsets {
                seeded["x\(offset / 8)"] = .selfFieldValue(offset: offset)
            }
            integerIndex = selfOffsets.count
        } else {
            return nil
        }
        var argumentFieldMaps: [Int: FieldMap] = [:]
        for (parameter, index) in zip(parameters, parameters.indices) {
            switch Self.scalarParameterClass(parameter) {
            case .integer:
                guard integerIndex < 8 else { return nil }
                seeded["x\(integerIndex)"] = .argument(index); integerIndex += 1
            case .floating:
                guard floatIndex < 8 else { return nil }
                seeded["v\(floatIndex)"] = .argument(index); floatIndex += 1
            case .aggregate?:
                // `scalarParameterClass` classifies scalars only.
                return nil
            case nil:
                // The only other shape we decompose is an HFA-float struct.
                guard let map = Self.namedFieldMap(Self.parameterType(parameter), in: fieldMaps),
                      let offsets = map.homogeneousFloatFieldOffsets,
                      floatIndex + offsets.count <= 8
                else { return nil }
                for offset in offsets {
                    seeded["v\(floatIndex)"] = .argumentField(argument: index, offset: offset)
                    floatIndex += 1
                }
                argumentFieldMaps[index] = map
            }
        }
        if let integerSelfAfterFormals {
            guard integerIndex + integerSelfAfterFormals.count <= 8 else { return nil }
            for (word, offset) in integerSelfAfterFormals.enumerated() {
                seeded["x\(integerIndex + word)"] = .selfFieldValue(offset: offset)
            }
        }
        if let floatingSelfOffsets {
            guard floatIndex + floatingSelfOffsets.count <= 8 else { return nil }
            for offset in floatingSelfOffsets {
                seeded["v\(floatIndex)"] = .selfFieldValue(offset: offset)
                floatIndex += 1
            }
        }
        return (selfMap.typeName, selfMap, seeded, argumentFieldMaps)
    }

    /// A demangled parameter's type, with any `label:` prefix removed.
    static func parameterType(_ parameter: String) -> String {
        if let colon = parameter.range(of: ": ", options: .backwards) {
            return withoutOwnership(String(parameter[colon.upperBound...]))
        }
        return withoutOwnership(parameter)
    }

    /// A parameter's type without its ownership specifier, which says who
    /// releases the value, not how it travels: `__owned Swift.Array<A>` is
    /// the Array's one word (`_finalizeUninitializedArray`, whose argument
    /// is the array literal being built).
    static func withoutOwnership(_ type: String) -> String {
        var type = Substring(type.trimmingCharacters(in: .whitespaces))
        for specifier in ["__owned ", "__shared ", "__consuming ", "consuming ", "borrowing "]
        where type.hasPrefix(specifier) {
            type = type.dropFirst(specifier.count)
        }
        return String(type)
    }

    /// A field map for a demangled type name.
    /// A qualified type name requires its own descriptor's map; simple keys
    /// serve genuinely unqualified names.
    private static func namedFieldMap(_ typeName: String, in fieldMaps: [String: FieldMap]) -> FieldMap? {
        fieldMaps[typeName]
    }

    enum ScalarParameterClass: Equatable {
        case integer, floating
        /// A struct passed in registers of both banks (`SwiftLowering.
        /// aggregateRegisters`): one argument, rendered `?`.
        case aggregate(integers: Int, floats: Int)
    }

    /// The register class of a demangled parameter, or nil when it isn't provably
    /// a single-register scalar. Deliberately an under-approximation: an unlisted
    /// type (a class reference is single-register too, but unidentifiable by name)
    /// blocks seeding, trading missed parameters for never mislabeling one.
    private static func scalarParameterClass(
        _ parameter: String, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> ScalarParameterClass? {
        // Demangled Swift signatures list bare types with no argument labels, but
        // tolerate a `label: Type` form defensively by taking the type.
        var type = parameter
        if let colon = type.range(of: ": ", options: .backwards) {
            type = String(type[colon.upperBound...])
        }
        type = withoutOwnership(type)
        // The one classification of how a value travels (`SwiftLowering`),
        // which a result's register also follows: a one-pointer collection
        // (`[Int]`, a Dictionary, a Set), `any Error` and `AnyObject` are one
        // integer register too, and seeded so: `afterArray(_ xs: [Int], _ i:
        // Int)` read `return ?` for `i &* 11`.
        switch SwiftLowering.of(type, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
        case .oneInteger: return .integer
        case .oneFloat: return .floating
        default: break
        }
        // An imported C enum or option set the image proves an integer.
        if enumCaseIndex.isImportedInteger(type) { return .integer }
        return nil
    }

    /// A single-register pointer type (nil-representable as 0).
    static func isSingleRegisterPointer(_ type: String) -> Bool {
        ["Swift.OpaquePointer", "Swift.UnsafeRawPointer", "Swift.UnsafeMutableRawPointer"]
            .contains(type)
            || type.hasPrefix("Swift.UnsafePointer<")
            || type.hasPrefix("Swift.UnsafeMutablePointer<")
    }

    /// A callee named by a bare C identifier: no Swift signature, no
    /// Objective-C send, and not a name this tool gives an in-image body
    /// (`sub_…`, an outliner fragment). Nothing in such a name bounds its
    /// parameters. Some families are left out because their arity is known
    /// even where no table holds it yet: an Itanium-mangled C++ name
    /// (`_Z1gi` is `g(int)`), a name reserved to the implementation
    /// (`__memset_chk(dest, c, len, destlen)`, `__cxa_begin_catch`), and
    /// the Swift and Objective-C runtimes' entry points, whose ABI their
    /// headers fix (`swift_setAtWritableKeyPath(root, keyPath, value)`,
    /// `objc_setProperty_nonatomic_copy(self, _cmd, value, offset)`).
    static func isUndeclaredCSymbol(_ callee: String) -> Bool {
        func isLetter(_ byte: UInt8) -> Bool { (byte | 0x20) >= 0x61 && (byte | 0x20) <= 0x7a }
        guard let first = callee.utf8.first, first == UInt8(ascii: "_") || isLetter(first),
              callee.utf8.allSatisfy({ byte in
                  byte == UInt8(ascii: "_") || byte == UInt8(ascii: "$") || isLetter(byte)
                      || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
              })
        else { return false }
        return !["objc_", "sub_", "OUTLINED_FUNCTION", "_Z", "__", "swift_", "_swift_"]
            .contains { callee.hasPrefix($0) }
    }

    /// The declared type of the stored field that is exactly the eight
    /// bytes at `offset` of a type laid out by `map`, when it is a plain
    /// nominal name (`Module.Engine`, or an Optional of one, whose payload a
    /// call only reaches once it is non-nil). Nil for a generic, function,
    /// existential or composed type, and for any offset no single field
    /// covers exactly.
    static func declaredClassOfField(at offset: Int, in map: FieldMap?) -> String? {
        guard let map, case .success(.whole(let name, _)) = map.lookup(offset: offset, bytes: 8),
              let type = map.fieldTypeNames[name]
        else { return nil }
        return plainNominalName(type)
    }

    /// `type` when it is a plain qualified nominal name, or an Optional of
    /// one (unwrapped); nil for anything generic, functional, existential,
    /// composed or unqualified.
    /// Parameter `index`'s type as the function's signature prints it, the
    /// numbering the entry convention seeds `.argument(index)` with.
    static func printedParameterType(of function: DisassembledFunction, at index: Int) -> String? {
        guard let name = function.layoutName, let split = DisassembledFunction.splitSignature(name),
              let range = DisassembledFunction.outermostArgumentListRange(of: split.head)
        else { return nil }
        let parameters = DisassembledFunction.splitTopLevelArguments(split.head[range])
        return parameters.indices.contains(index) ? parameterType(parameters[index]) : nil
    }

    static func plainNominalName(_ type: String) -> String? {
        var type = type
        let optional = "Swift.Optional<"
        if type.hasPrefix(optional), type.hasSuffix(">") { type = String(type.dropFirst(optional.count).dropLast()) }
        guard !type.isEmpty, type.contains("."),
              !type.contains(where: { "<>()[]&:, ?!".contains($0) })
        else { return nil }
        return type
    }

    private func enrichCallArguments(
        in function: DisassembledFunction,
        cfg: FunctionCFG,
        resolver: ReferenceResolver,
        swiftTargets: Set<UInt64>,
        entry: MethodEntryConvention?,
        fieldMap: FieldMap?,
        objcFieldSyntax: Bool,
        selfTypeName: String? = nil,
        vtableIndex: VTableIndex = VTableIndex(),
        argumentFieldMaps: [Int: FieldMap] = [:],
        classArgumentFieldMaps: [Int: FieldMap] = [:],
        classArgumentTypes: [Int: String] = [:],
        enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        payloadEnumIndex: PayloadEnumCaseIndex = PayloadEnumCaseIndex(),
        argumentEnumTypes: [Int: String] = [:],
        boolArguments: Set<Int> = [],
        classTypeIndex: ClassTypeIndex = ClassTypeIndex(),
        indirectResultUse: IndirectResultUse = .unknown,
        typeFieldMaps: [String: FieldMap] = [:],
        calleeConventions: [UInt64: CalleeResultConvention] = [:],
        asyncContextSlots: [Int: AbstractValue] = [:],
        asyncSuspensions: [UInt64: AsyncSuspensionNote] = [:],
        objcIndex: ObjCMetadataIndex? = nil,
        registerSummaries: [UInt64: CalleeRegisterFacts] = [:],
        selfMembers: SelfMemberCache = SelfMemberCache(),
        callResultBanks: CallResultBankCache = CallResultBankCache(),
        inlinedPrefixes: [UInt64: [Instruction]] = [:],
        callerProvenResult: SwiftReturnRegister? = nil
    ) -> DisassembledFunction {
        // Floating-point signature info: which arguments are float, and whether
        // the function's float type is double-precision — so a literal operand
        // in a float-valued expression renders as a decimal, not IEEE bits.
        let floatInfo = Self.swiftFloatArgumentInfo(of: function)
        // Per-argument recovered types (Phase-1 lattice), computed once from the
        // signature. The typed source the boolean path consults to decide whether
        // an unsigned machine comparison reads as a signed range check.
        let argumentTypes = TypeInference.argumentTypes(of: function, classTypeIndex: classTypeIndex)

        /// A source-level field path for this method convention.
        func fieldPath(_ name: String) -> String {
            objcFieldSyntax ? "self->\(name)" : "self.\(name)"
        }

        /// Part of a field: its member when the field is an imported C struct
        /// whose own field record in the image names those bytes (`stamp:
        /// timespec` at +8 is `stamp.tv_nsec`), else its byte range
        /// (`name[8..<16]`). A C struct's layout is the C ABI's, which the
        /// record states; a Swift struct's part keeps its range.
        /// `owner` is the map `name`'s last component is a field of: self's
        /// at the top, which resolves the field's symbolic type reference
        /// (`fieldTypeNames`); a member's own C struct's below.
        func memberPath(
            _ name: String, type: String?, subOffset: Int, bytes: Int,
            field: String? = nil, owner: FieldMap? = nil
        ) -> String {
            let fieldName = field ?? name
            let resolved = type.map { FieldMap.printableTypeName(
                mangled: $0, resolved: (owner ?? fieldMap)?.fieldTypeNames[fieldName]) }
            if let resolved, resolved.hasPrefix("__C."), let map = typeFieldMaps[resolved],
               case .success(let hit) = map.lookup(offset: subOffset, bytes: max(bytes, 1)) {
                switch hit {
                case .whole(let member, _):
                    return "\(name).\(member)"
                case .part(let member, let memberType, let inner, let innerBytes):
                    return memberPath("\(name).\(member)", type: memberType, subOffset: inner, bytes: innerBytes,
                                      field: member, owner: map)
                case .spans:
                    break
                }
            }
            return "\(name)[\(subOffset)..<\(subOffset + bytes)]"
        }

        /// Render a by-value struct argument's field — `arg1.y` — from the
        /// parameter's own field map, falling back to a byte offset.
        func argumentFieldName(argument: Int, offset: Int) -> String {
            if case .success(let hit)? = (argumentFieldMaps[argument] ?? classArgumentFieldMaps[argument])?
                .lookup(offset: offset, bytes: 1) {
                switch hit {
                case .whole(let name, _), .part(let name, _, _, _):
                    return "arg\(argument).\(name)"
                case .spans:
                    break
                }
            }
            return "arg\(argument)[0x\(String(offset, radix: 16))]"
        }

        /// Resolve a vtable-dispatch byte offset to the method `self`'s class
        /// calls there — the demangled name of its implementation. Nil when
        /// `self`'s type is unknown or the slot is an inherited (superclass) one
        /// this class's descriptor doesn't list.
        func resolveVTableMethod(_ offset: Int) -> String? {
            guard let selfTypeName,
                  let address = vtableIndex.methodAddress(type: selfTypeName, offset: offset)
            else { return nil }
            // The slot is self's own, so the name must be: at a folded address
            // `name(at:)` may be another class's symbol for the same bytes.
            return selfMembers.name(at: address, ownedBy: selfTypeName, resolver: resolver)
        }

        /// `self`'s own getters/setters, keyed by resolved method name, so a
        /// vtable dispatch to one renders as `self.property` (or `self.property =`)
        /// instead of `Type.property.getter(…)` with stale argument registers.
        let selfAccessors: [String: (property: String, isGetter: Bool)] = {
            guard let selfTypeName else { return [:] }
            return selfMembers.accessors(of: selfTypeName) {
                var map: [String: (property: String, isGetter: Bool)] = [:]
                for address in vtableIndex.methodAddresses(type: selfTypeName) {
                    guard let name = selfMembers.name(at: address, ownedBy: selfTypeName, resolver: resolver),
                          Self.namingItsProperty(name, ownedBy: selfTypeName) == name,
                          let access = DisassembledFunction.swiftAccessorProperty(name)
                    else { continue }
                    map[name] = access
                }
                return map
            }
        }()

        func fieldInfo(at offset: Int, bytes: Int) -> (names: [String], type: String?)? {
            guard let fieldMap else { return nil }
            switch fieldMap.lookup(offset: offset, bytes: max(bytes, 1)) {
            case .success(.whole(let name, let type)):
                Probe.record(.fieldNamed, [
                    "type": .name(fieldMap.typeName), "offset": .int(offset), "bytes": .int(bytes),
                    "field": .name(name), "fieldType": .name(type ?? "?"), "coverage": .label("whole"),
                ])
                return ([name], type)
            case .success(.part(let name, let type, _, _)):
                Probe.record(.fieldNamed, [
                    "type": .name(fieldMap.typeName), "offset": .int(offset), "bytes": .int(bytes),
                    "field": .name(name), "fieldType": .name(type ?? "?"), "coverage": .label("part"),
                ])
                return ([name], type)
            case .success(.spans(let names)):
                Probe.record(.fieldNamed, [
                    "type": .name(fieldMap.typeName), "offset": .int(offset), "bytes": .int(bytes),
                    "field": .name(names.joined(separator: "+")), "coverage": .label("spans"),
                ])
                return (names, nil)
            case .failure(let failure):
                Probe.record(.fieldUnnamed, [
                    "type": .name(fieldMap.typeName), "offset": .int(offset), "bytes": .int(bytes),
                    "reason": .label(Self.fieldFailureLabel(failure)),
                ])
                return nil
            }
        }

        /// A field name for an offset, or nil when it cannot be named honestly.
        func fieldName(at offset: Int, bytes: Int) -> String? {
            guard let names = fieldInfo(at: offset, bytes: bytes)?.names else { return nil }
            return names.count == 1 ? names[0] : "{\(names.joined(separator: ", "))}"
        }

        // A `.loaded` value only means something when we can name what lives at
        // the address; any other load is unnamed data. Sanitize recursively now
        // that arithmetic expressions can contain loaded values.
        func sanitizeValue(_ value: AbstractValue) -> AbstractValue {
            switch value {
            case .loaded(let address) where resolver.loadedName(at: address) == nil:
                // A load from the read-only literal pool is the constant itself
                // (the compiler's lowering of a non-encodable immediate); any
                // other unnamed load is unknown.
                if let word = resolver.literalWord(at: address) { return .immediate(word) }
                return .unknown
            case .asyncContext, .asyncCalleeContext, .asyncResumeParent, .asyncContextSlot:
                // Async plumbing: the context pointer, the continuation, and an
                // unproven context slot are not source values.
                return .unknown
            case .loadedThrough, .loadedFrom, .selfIsaSnapshot, .genericWitnessTable, .existentialWitnessTable:
                // A word read through a loaded pointer: named only as a call
                // target (`indirectCallTarget`), unknown as a value. So is an
                // isa kept across a call.
                return .unknown
            case .binary(let op, let lhs, let rhs):
                let lhs = sanitizeValue(lhs)
                let rhs = sanitizeValue(rhs)
                guard lhs != .unknown, rhs != .unknown else { return .unknown }
                return .binary(op, lhs, rhs)
            case .unary(let op, let operand):
                let operand = sanitizeValue(operand)
                return operand == .unknown ? .unknown : .unary(op, operand)
            case .select(let condition, let whenTrue, let whenFalse):
                let c = sanitizeValue(condition)
                let t = sanitizeValue(whenTrue)
                let f = sanitizeValue(whenFalse)
                guard c != .unknown, t != .unknown, f != .unknown else { return .unknown }
                return .select(condition: c, whenTrue: t, whenFalse: f)
            case .aggregate(let values):
                // A String slot's call result keeps its second word.
                let values = values.map { value -> AbstractValue in
                    if case .callResultHigh = value { return value }
                    return sanitizeValue(value)
                }
                return values.allSatisfy({ $0 != .unknown }) ? .aggregate(values) : .unknown
            case .callResultHigh:
                // Alone, a String result's second word is no argument: in a
                // positional list it trims like any unknown.
                return .unknown
            default:
                return value
            }
        }

        /// Calls whose Swift result is not one register: x0 after one is a
        /// part of the result, never the whole call.
        /// Filled once the call sites are known: a call handed a frame buffer
        /// in x8 returns through memory, and its `.callResult` is that whole
        /// buffer.
        var multiWordResultSites = Set<UInt64>()
        // An aggregate ObjC result is not any one scalar register read from
        // the send. Keep separate from Swift's proven two-word results: an
        // HFA, opaque aggregate or indirect result cannot be reassembled by
        // merely finding x0 and x1 beside each other.
        var nonScalarObjCResultSites = Set<UInt64>()
        /// A multi-word result's x0 and x1 passed on side by side are that
        /// whole value, one argument: `UTF8View.count.getter(String.utf8.getter(…))`.
        func collapsingMultiWordResults(_ values: [AbstractValue]) -> [AbstractValue] {
            var out: [AbstractValue] = []
            var index = 0
            while index < values.count {
                if index + 1 < values.count, case .callResult(let site) = values[index],
                   multiWordResultSites.contains(site), values[index + 1] == .callResultHigh(site) {
                    out.append(.aggregate([.callResult(site), .callResultHigh(site)]))
                    index += 2
                    continue
                }
                out.append(values[index])
                index += 1
            }
            return out
        }

        func sanitize(_ values: [AbstractValue]) -> [AbstractValue]? {
            ValueTracer.trimTrailingUnknown(collapsingMultiWordResults(values).map(sanitizeValue))
        }

        var tracer = ValueTracer(calleeConventions: calleeConventions, asyncContextSlots: asyncContextSlots)
        tracer.callFactsCache = callFactsCache
        tracer.argumentObjectFields = classArgumentFieldMaps.mapValues(Self.wholeWordFieldWidths)
        tracer.inlinedPrefixes = inlinedPrefixes
        tracer.callResultBank = { callee in
            Self.callResultBank(of: callee, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, cache: callResultBanks)
        }
        if let objcIndex {
            let selectors = resolver.selectors.bySelref
            let method = function.objcMethod
            tracer.callReturnsVoid = { callee, site in
                guard callee.hasPrefix("objc_msgSend") else { return false }
                let selector: String?
                if let marker = callee.firstIndex(of: "$") { selector = String(callee[callee.index(after: marker)...]) }
                else if site.arguments.count > 1, case .loaded(let slot) = site.arguments[1] { selector = selectors[slot] }
                else { selector = nil }
                guard let selector, let receiver = site.arguments.first else { return false }
                let receiverClass: (String, Bool)?
                if receiver == .selfPointer, let method { receiverClass = (method.className, method.isClassMethod) }
                else if objcFieldSyntax, case .selfFieldValue(let offset) = receiver, let fieldMap,
                        case .success(.whole(_, let encoding)) = fieldMap.lookup(offset: offset, bytes: 8),
                        encoding.hasPrefix("@\""), encoding.hasSuffix("\"") {
                    let name = String(encoding.dropFirst(2).dropLast())
                    receiverClass = !name.isEmpty && !name.contains("<") && !name.contains("\"") ? (name, false) : nil
                } else { receiverClass = nil }
                guard let (name, isClass) = receiverClass else { return false }
                return objcIndex.outgoingReturnsVoid(selector: selector, className: name, isClassMethod: isClass)
            }
        }
        var callTargets: [UInt64: UInt64] = [:]
        /// Whether a call's arguments follow a signature: the one its
        /// target's symbol proves whole, or the printed one where that stands.
        func followsASignature(target: UInt64, callee: String) -> Bool {
            switch resolver.specializationClause(at: target, printedName: callee) {
            case .proven(let layout): layout.isComplete
            case .declined: false
            case .absent: Self.signatureSpecializationKeepsLayout(callee)
            }
        }
        var unprovenTypedErrorSites = Set<UInt64>()
        // Symbol substitution is independent of whether the body admits a
        // register summary. Keep its proved layout even for an undecoded body.
        var specializedLayoutBySite: [UInt64: String] = [:]
        /// The name a call's arguments are laid out by: for a generic
        /// specialization its substituted signature, which says what the
        /// printed `A` is. `bump<Double>(d)` passes d in d0, and read from its
        /// printed `(A)` it rendered `bump(arg1)`, the Int then in x0.
        func layoutName(at address: UInt64, callee: String) -> String {
            if let thunk = witnessLayoutNames[address] { return thunk }
            if let setter = Self.setterLayoutName(callee, classTypeIndex: classTypeIndex) { return setter }
            if let specialized = specializedLayoutBySite[address] { return specialized }
            return callTargets[address].flatMap { resolver.specializedSignature(at: $0, printedName: callee) } ?? callee
        }
        /// A call through a protocol witness table, laid out as the
        /// requirement's dispatch thunk, which takes the same arguments:
        /// `self` in x20, the formals from x0, and the requirement's Self
        /// metadata and witness table after them.
        var witnessLayoutNames: [UInt64: String] = [:]
        // The GOT slots `adrp; ldr` pairs load the stack probe from, for a
        // `blr x16` the tracer cannot name before it runs, and the one
        // holding `swift_isaMask`'s address.
        do {
            let pairTracer = ValueTracer()
            for (index, insn) in function.instructions.enumerated().dropLast() {
                guard insn.detail?.id == AARCH64_INS_ADRP else { continue }
                let next = function.instructions[index + 1]
                guard let destination = next.detail?.operands.first?.operand.register?.key,
                      case .loaded(let slot)? = pairTracer.finalState(of: [insn, next])[destination]
                else { continue }
                switch resolver.loadedName(at: slot) {
                case "__chkstk_darwin": tracer.stackProbeSlots.insert(slot)
                case "swift_isaMask": tracer.isaMaskSlots.insert(slot)
                default: break
                }
            }
        }
        if let sites = registerSummaries[function.startAddress]?.provenAllocationSites, !sites.isEmpty {
            tracer.summaryProvenAllocations = Set(sites)
        }
        for insn in function.instructions where insn.controlFlow == .call || insn.controlFlow == .branch {
            guard let target = insn.branchTarget else { continue }
            // This proof is about the symbol, independent of whether a body
            // summary or any traced argument values are available.
            if let callee = DisassembledFunction.calleeName(of: insn) {
                switch resolver.specializedSignatureProof(at: target, printedName: callee) {
                case .signature(let specialized): specializedLayoutBySite[insn.address] = specialized
                case .unprovenDroppedTypedError: unprovenTypedErrorSites.insert(insn.address)
                case .unavailable: break
                }
            }
            guard registerSummaries[target] != nil else { continue }
            if let memory = registerSummaries[target]?.memoryEffect, case .literalStores = memory {
                tracer.calleeMemoryEffects[target] = memory
            }
            // A tail branch passes its arguments the same way a call does.
            callTargets[insn.address] = target
            if insn.controlFlow == .call, let clobbered = registerSummaries[target]?.clobberedCalleeSaved,
               !clobbered.isEmpty {
                tracer.calleeClobbers[target] = clobbered
            }
            if registerSummaries[target]?.writesNoFields == true { tracer.fieldPreservingCallees.insert(target) }
            if insn.controlFlow == .call, let mask = registerSummaries[target]?.mayReadRegisters,
               mask != CalleeRegisterSummary.allRegisterBits {
                tracer.calleeReadRegisters[target] = mask
            }
            if insn.controlFlow == .call, registerSummaries[target]?.readsFramePointer == true {
                tracer.framePointerUsers.insert(target)
            }
            if let callee = DisassembledFunction.calleeName(of: insn),
               DisassembledFunction.knownArityNameMayHaveTwin(callee) {
                tracer.inImageCallTargets.insert(target)
            }
            if insn.controlFlow == .call, registerSummaries[target]?.readsContextRegister == true {
                tracer.contextRegisterUsers.insert(target)
            }
        }
        var analysis = tracer.analyze(function, entry: entry, cfg: cfg)
        /// The widths of the loads from each offset of `self`, and of the
        /// stores that leave their source register named as the field
        /// (`.selfFieldValue`), for naming the part of a field such a value
        /// is. A paired load gives each register its own word:
        /// `ldp x0, x1, [x20, #off]` over a String field read as the whole
        /// field in x0. A store is a value's start too: after `stp x2, x3,
        /// [x0, #0x8]` over a 16-byte `_s`, x2 holds `_s`'s first eight
        /// bytes, and with only loads counted it rendered `self->_s`.
        var selfFieldReadWidths = analysis.selfFieldAliasWidths
        for access in analysis.selfFieldAccesses.values where !access.isWrite && !access.isAddressOf {
            if let word = access.registerBytes {
                selfFieldReadWidths[access.offset, default: []].insert(word)
                selfFieldReadWidths[access.offset + word, default: []].insert(word)
            } else {
                selfFieldReadWidths[access.offset, default: []].insert(access.bytes)
            }
        }
        // An x8-indirect function's x0 at `ret` is whatever was last left there
        // (usually a stale argument), never its result. Both single-register
        // return paths below are gated on this so no fabricated `return arg0`
        // is printed for a function that returns through the caller's buffer.
        let returnsDirectly = indirectResultUse != .reads
        // Call sites whose indirect result is read back word by word, each bound
        // to one name (`let r0 = callee(args)`) so the call is spelled out once
        // and every field read is `r0.field`; rendering the call at each read
        // would show it executed once per field. Filled once the values that
        // will render are known (below); read by `renderValue`.
        var boundResultSites: [UInt64: String] = [:]
        /// Bound because its direct result is read in several places (as
        /// opposed to word by word): its `let` renders as the value would.
        var reusedResultSites = Set<UInt64>()
        /// The site whose `let` is being rendered, which spells itself out.
        var definingSite: UInt64?
        /// The multi-word call whose two words are being rendered together.
        var wholeResultSite: UInt64?
        // Rendering limits can discard an otherwise evaluable tracer value.
        // Count actual placeholder emissions, rather than scanning text where
        // '?' can also be a ternary operator or part of a string literal.
        let trackReturnRendering = Probe.isActive
        var unknownRenderCount = 0
        var completeReturnRendering: [UInt64: Bool] = [:]
        func unknownRenderedValue() -> String {
            if trackReturnRendering { unknownRenderCount += 1 }
            return "?"
        }
        // Naming an indirect target does not replay the earlier dataflow graph.
        // Keep the original machine transfers for exit-proof completeness.
        let originalIndirectExitTransfers = Set(function.instructions.compactMap { instruction -> UInt64? in
            instruction.controlFlow == .branch && instruction.branchTarget == nil
                && function.switchTargets[instruction.address] == nil ? instruction.address : nil
        })
        let originalARCContracts = Set(function.instructions.filter { $0.facts.arcIdentityContract }.map(\.address))
        let resolvedControlFlow = annotateIndirectControlFlowTargets(
            in: function, targets: analysis.indirectControlFlowTargets,
            resolver: resolver, selfTypeName: selfTypeName, vtableIndex: vtableIndex,
            callArguments: analysis.callSites.mapValues(\.arguments),
            selfFieldClass: { offset in Self.declaredClassOfField(at: offset, in: fieldMap) },
            argumentClass: { classArgumentTypes[$0] },
            argumentFieldClass: { argument, offset in
                Self.declaredClassOfField(at: offset, in: classArgumentFieldMaps[argument])
            },
            argumentType: { argument in Self.printedParameterType(of: function, at: argument) }
        )
        let function = resolvedControlFlow.function
        // Resolving an external BR adds its successor address. BLR naming
        // changes no edge; notes and facts keep the existing graph valid.
        let cfg = resolvedControlFlow.changesCFG ? FunctionCFG(function) : cfg
        for insn in function.instructions {
            if let requirement = insn.facts.witnessRequirement {
                witnessLayoutNames[insn.address] = Self.dispatchThunkPrefix + requirement
            }
        }
        // A self dispatch resolved to its class's implementation takes that
        // body's parameters: an override keeps the signature, so the same
        // registers. A stripped binary names such an accessor by its kind
        // alone (`self.(unknown).getter`), and laid out positionally it read
        // whatever x0 held.
        for insn in function.instructions where insn.isSelfDispatch && (insn.controlFlow == .call || insn.controlFlow == .branch) {
            if let target = insn.branchTarget, registerSummaries[target] != nil, callTargets[insn.address] == nil {
                callTargets[insn.address] = target
            }
        }
        // Vtable targets become named only after the first trace. A newly
        // resolved setter must invalidate its result before downstream values
        // are recovered; rendering-time suppression leaves fabricated values
        // inside later expressions.
        // A value witness named through its table is resolved here too, and
        // `destroy` returns nothing: its x0 flowed into the next call.
        let resolvedVoidCalls = Set(function.instructions.compactMap { insn -> UInt64? in
            guard insn.controlFlow == .call,
                  let callee = DisassembledFunction.calleeName(of: insn),
                  DisassembledFunction.swiftAccessorProperty(callee)?.isGetter == false
                    || DisassembledFunction.isVoidValueWitness(callee)
            else { return nil }
            return insn.address
        })
        let resolvedARCCalls = function.instructions.contains {
            $0.facts.arcIdentityContract && !originalARCContracts.contains($0.address)
        }
        if !resolvedVoidCalls.isEmpty || resolvedARCCalls {
            tracer.voidCallSites = resolvedVoidCalls
            analysis = tracer.reanalyze(function, entry: entry, cfg: cfg)
        }
        Probe.observe(analysis, of: function, cfg: cfg)
        if Probe.isActive {
            for insn in function.instructions where insn.branchTarget == nil
                && (insn.controlFlow == .call || insn.controlFlow == .branch)
                && function.switchTargets[insn.address] == nil
                && analysis.indirectControlFlowTargets[insn.address] == nil {
                Probe.record(insn.controlFlow == .call ? .unresolvedIndirectCall : .unresolvedIndirectBranch,
                             at: insn.address, ["text": .name(insn.text)])
            }
            for (address, targets) in function.switchTargets.sorted(by: { $0.key < $1.key }) {
                Probe.record(.jumpTable, at: address, ["cases": .int(targets.count)])
            }
        }
        let selfDispatchSites = Set(function.instructions.filter(\.isSelfDispatch).map(\.address))
        /// A call through self's own vtable slot is `self.member(…)`: the named
        /// implementation is only the one that runs when self is exactly its class.
        func displayCallee(_ callee: String, at site: UInt64) -> String {
            let display = demangleCache.presentation(of: callee)
            return selfDispatchSites.contains(site)
                ? DisassembledFunction.selfDispatchCall(display)
                : DisassembledFunction.strippedCallee(display)
        }
        // An async function returns by branching through its own context's
        // ResumeParent slot. Proven only when the tracer followed the pointer
        // from the seeded context to the `br`; such a branch is treated as the
        // `ret` it is, for the return value and for the structurer.
        let asyncReturns = Set(function.instructions.compactMap { insn -> UInt64? in
            guard insn.controlFlow == .branch, insn.branchTarget == nil,
                  analysis.indirectControlFlowTargets[insn.address] == .asyncResumeParent
            else { return nil }
            return insn.address
        })
        // A tail branch to an in-image body that writes neither x0 nor v0
        // and leaves only through `ret` hands back the registers it was
        // given: it is this function's return of what x0 and v0 hold at the
        // branch. It makes no call and stores only to its own stack, so the
        // return is all it does. `callGen` is `b sub_3e0`, and sub_3e0 is a lone `ret`
        // (`gen(a, t) { a }` specialized), so it returns its arg0; read as an
        // ordinary tail call it rendered `sub_3e0()` and no return at all.
        let ownAddresses = Set(function.instructions.map(\.address))
        let passthroughTailBranches = Set(function.instructions.compactMap { insn -> UInt64? in
            guard insn.controlFlow == .branch, let target = insn.branchTarget,
                  !ownAddresses.contains(target),
                  let summary = registerSummaries[target], !summary.mayWriteResult, !summary.mayWriteFloatResult,
                  summary.storesOnlyToStack,
                  // x21 is Swift's error register: a body that may leave
                  // another value there changes a throwing caller's outcome
                  // after the branch, where its exit was read.
                  !summary.clobberedCalleeSaved.contains("x21")
            else { return nil }
            return insn.address
        })
        func isReturn(_ insn: Instruction) -> Bool {
            insn.controlFlow == .return || asyncReturns.contains(insn.address)
                || passthroughTailBranches.contains(insn.address)
        }
        // `swiftReturnRegister(of:)` declines every async function, because x0 at
        // its `ret` is stale. At a proven async return the result is in x0/v0,
        // but only for a type proven to travel in one register: an indirect
        // result arrives as a buffer pointer in x0, and the compiler then
        // branches through x0 itself (`ldr x0, [x22, #8]; br x0`).
        let asyncReturnRegister: SwiftReturnRegister? = {
            guard !asyncReturns.isEmpty, function.objcMethod == nil,
                  let type = Self.swiftReturnTypeName(of: function),
                  Self.isKnownDirectReturnType(type, classTypeIndex: classTypeIndex)
            else { return nil }
            return Self.swiftReturnRegister(forReturnType: type)
        }()
        var sites = analysis.callSites
        for insn in function.instructions where insn.controlFlow == .call || insn.controlFlow == .branch {
            guard let callee = DisassembledFunction.calleeName(of: insn),
                  Self.callResultBank(of: callee, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, cache: callResultBanks) == .notOneRegister
            else { continue }
            switch sites[insn.address]?.indirectResult {
            case .frame?, .indirectResultField?: continue
            default: multiWordResultSites.insert(insn.address)
            }
        }
        // A resolved unconditional branch outside this function is a tail call.
        // Keep internal CFG branches out: they have no callee name.
        for insn in function.instructions where insn.controlFlow == .branch {
            if DisassembledFunction.calleeName(of: insn) != nil,
               let site = analysis.branchSites[insn.address] {
                sites[insn.address] = site
            }
        }
        // A proven scalar signature, or a runtime entry point's known C arity,
        // fixes arity even when no register value survives tracking.
        // Positional snapshots intentionally omit trailing unknowns, and a
        // snapshot with nothing in it is not recorded, so absence of a
        // snapshot is not evidence of zero parameters: `memmove` whose
        // operands were all loaded through an unknown pointer read
        // `memmove()`.
        //
        // A direct call or tail call to an undeclared C import, by name: its
        // arity is unknown, not absent. Not a call through a register the
        // tracer resolved, which may land on an in-image body (`blr x8`
        // into `twice(long)`), nor an in-image callee with a summary.
        let unprovenARCSites = Set(function.instructions.lazy.filter { insn in
            guard insn.controlFlow == .call || insn.controlFlow == .branch
                    || insn.controlFlow == .conditionalBranch else { return false }
            return DisassembledFunction.calleeName(of: insn).map(DisassembledFunction.isARCReferenceHelper) == true
                && !insn.facts.arcIdentityContract
        }.map(\.address))
        let undeclaredCImportCalls = Set(function.instructions.lazy.filter { insn in
            let mnemonic = insn.text.prefix { $0 != " " && $0 != "\t" }
            return (mnemonic == "bl" || mnemonic == "b")
                && DisassembledFunction.calleeName(of: insn).map(Self.isUndeclaredCSymbol) == true
                || (unprovenARCSites.contains(insn.address) && callTargets[insn.address] == nil)
        }.map(\.address))
        var unprovenGenericLayoutSites = Set<UInt64>()
        var unplacedSetterValueSites = Set<UInt64>()
        for insn in function.instructions
        where insn.controlFlow == .call || insn.controlFlow == .branch {
            guard let callee = DisassembledFunction.calleeName(of: insn) else { continue }
            if Self.isSwiftCall(insn, swiftTargets: swiftTargets),
               Self.ordinarySetterAssignedValueType(callee) != nil {
                let name = layoutName(at: insn.address, callee: callee)
                // A declined receiver/value ABI does not erase the setter's
                // assigned source value. Compute this for existing snapshots
                // as well as missing ones, without requiring a body summary.
                if Self.swiftCallArgumentLayout(callee: name, enumCaseIndex: enumCaseIndex,
                       classTypeIndex: classTypeIndex, fieldMaps: typeFieldMaps) == nil,
                   Self.swiftCallArgumentLayout(callee: name, enumCaseIndex: enumCaseIndex,
                       classTypeIndex: classTypeIndex, anyContext: true, fieldMaps: typeFieldMaps) == nil {
                    unplacedSetterValueSites.insert(insn.address)
                }
            }
            if callee.hasPrefix("generic specialization <") {
                let name = layoutName(at: insn.address, callee: callee)
                // A printed source formal and a declined concrete layout do
                // not establish zero arguments. Neither body absence nor a
                // trailing run of unknown machine values proves its arity.
                // Zero-formal calls (including proved dropped formals) stay
                // zero-formal; metadata, x20 and x8 are not source arguments.
                if let signature = DisassembledFunction.splitSignature(name),
                   let range = DisassembledFunction.outermostArgumentListRange(of: signature.head),
                   !signature.head[range].trimmingCharacters(in: .whitespaces).isEmpty,
                   Self.swiftCallArgumentLayout(callee: name, enumCaseIndex: enumCaseIndex,
                       classTypeIndex: classTypeIndex, fieldMaps: typeFieldMaps) == nil,
                   Self.swiftCallArgumentLayout(callee: name, enumCaseIndex: enumCaseIndex,
                       classTypeIndex: classTypeIndex, anyContext: true, fieldMaps: typeFieldMaps) == nil {
                    unprovenGenericLayoutSites.insert(insn.address)
                }
            }
            guard sites[insn.address] == nil else { continue }
            // So does an in-image callee whose body proves an integer or
            // floating-point input, including an exact direct branch alias:
            // an unknown argument is still present. For example, `readsFirst(?)`
            // when its argument was loaded through an unknown pointer.
            guard unprovenTypedErrorSites.contains(insn.address)
                    || unprovenGenericLayoutSites.contains(insn.address)
                    || unplacedSetterValueSites.contains(insn.address)
                    || DisassembledFunction.knownCArity(of: callee) != nil
                    || Self.isStringInstanceGetter(callee)
                    || (Self.swiftCallArgumentLayout(
                        callee: layoutName(at: insn.address, callee: callee),
                        enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, fieldMaps: typeFieldMaps
                    ) ?? Self.swiftCallArgumentLayout(
                        callee: layoutName(at: insn.address, callee: callee),
                        enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, anyContext: true, fieldMaps: typeFieldMaps
                    )).map({ !$0.slots.isEmpty || $0.unplaced > 0 }) == true
                    || (!(callTargets[insn.address] != nil && DisassembledFunction.knownArityNameMayHaveTwin(callee))
                        && Self.cPrototypeLayout(callee: callee) != nil)
                    || insn.branchTarget.flatMap({ registerSummaries[$0] }).map({
                        $0.provenArgumentCount > 0 || $0.provenFloatArgumentCount > 0
                    }) == true
                    // An undeclared C callee's arity is unknown, which is
                    // not zero: `P()` read as a call with no arguments.
                    || undeclaredCImportCalls.contains(insn.address)
            else { continue }
            sites[insn.address] = CallSite()
        }
        // A property getter is often `ldr x0, [x20, #n]; ret` — no calls at all.
        // Bailing on `sites.isEmpty` alone would skip field naming for precisely
        // the functions it is most useful in.
        // So is a function whose only transfer out is a `br` through a
        // register: it needs its `jump=` note, or it reads as a leaf.
        guard !sites.isEmpty || !analysis.selfFieldAccesses.isEmpty
                || !analysis.exitValues.isEmpty || !analysis.exitFloatValues.isEmpty
                || !analysis.exitIndirectResults.isEmpty
                || !analysis.loopInitializations.isEmpty
                || DisassembledFunction.splitSignature(function.analysisDisplayName)?.isThrowing == true
                || function.instructions.contains(where: { $0.controlFlow == .branch && $0.branchTarget == nil })
        else {
            // No facts is still an observed unknown result, not an absent exit.
            // Do not run unrelated enrichment when only this contract is known:
            // the exit, and the stores no other fact describes, are all added.
            let stores = Self.leafMemoryWrites(function, analysis: analysis)
            guard function.hasProvenMachineValueReturn || !stores.isEmpty else {
                return function.retainingCFG(cfg)
            }
            let type = DisassembledFunction.splitSignature(function.analysisDisplayName)?.result
                ?? function.objcMethod?.signature ?? "unknown"
            let instructions = function.instructions.map { insn in
                if let statement = stores[insn.address] {
                    var facts = insn.facts
                    facts.statement = .assignment(statement)
                    return Instruction(
                        address: insn.address, text: insn.text,
                        annotation: [insn.annotation, statement].compactMap { $0 }.joined(separator: "  "),
                        controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                        callArguments: insn.callArguments, callSelf: insn.callSelf,
                        resultConsumed: insn.resultConsumed, sourceType: insn.sourceType, detail: insn.detail,
                        calleeDisplayName: insn.calleeDisplayName, callee: .kept(insn.callee), facts: facts)
                }
                guard insn.controlFlow == .return, function.hasProvenMachineValueReturn else { return insn }
                Probe.record(.returnOutcome, at: insn.address, ["status": .label("unknown"), "type": .name(type)])
                var facts = insn.facts
                facts.exit = .normal("?")
                return Instruction(
                    address: insn.address, text: insn.text,
                    annotation: [insn.annotation, facts.exit?.note].compactMap { $0 }.joined(separator: "  "),
                    controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                    callArguments: insn.callArguments, callSelf: insn.callSelf,
                    resultConsumed: insn.resultConsumed, sourceType: insn.sourceType, detail: insn.detail,
                    calleeDisplayName: insn.calleeDisplayName, callee: .kept(insn.callee), facts: facts)
            }
            return function.replacingInstructions(instructions).retainingCFG(cfg)
        }

        // The no-payload enum self is, when x20 holds its address.
        let selfEnumType: String? = if case .swiftInstance? = entry {
            Self.swiftEnumSelfType(of: function, enumCaseIndex: enumCaseIndex)
        } else { nil }

        // Facts of the function's own signature, read once rather than at
        // every instruction: each parses the demangled name, and the return
        // register walks the CFG.
        // A function no signature describes returns what its callers prove
        // it does (`callerProvenResult`): one of them reads x0 after calling
        // it, and none reads x1, v0, v1 or the error register.
        let provenMachineValueReturn = function.hasProvenMachineValueReturn || callerProvenResult != nil
        let signatureReturnsValue = DisassembledFunction.signatureReturnsValue(
            displayName: function.analysisDisplayName, objcSignature: function.objcMethod?.signature)
            || callerProvenResult != nil
        let functionReturnRegister = Self.swiftReturnRegister(
            of: function, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, cfg: cfg)
            ?? callerProvenResult

        // Callee name per call/tail-call address, for nesting result expressions.
        var calleeByAddress: [UInt64: String] = [:]
        for insn in function.instructions
        where insn.controlFlow == .call || insn.controlFlow == .branch {
            calleeByAddress[insn.address] = DisassembledFunction.calleeName(of: insn)
        }

        // Missing body summaries and demangled names are not external ABI
        // proof. Both receiver consumers use the same exact loader binding.
        var importedStringReceiverSites: Set<UInt64> = []
        for insn in function.instructions where calleeByAddress[insn.address] != nil {
            let imported: ImportedFunctionReference?
            if let target = insn.branchTarget {
                imported = resolver.importedFunction(at: target)
            } else {
                imported = analysis.indirectControlFlowTargets[insn.address].flatMap { resolver.importedFunction(for: $0) }
            }
            if let imported, imported.isStringHasPrefix,
               resolver.demangleSymbol(imported.rawSymbol) == calleeByAddress[insn.address] {
                importedStringReceiverSites.insert(insn.address)
            }
        }

        // x20 is `self` only under the Swift calling convention; for any
        // other callee it's a callee-saved register the caller happens to be
        // using, and calling it `self` would be a fabrication. Decided once
        // per call, so the call's statement, its binding and its spelling
        // inside another expression all name the same `self`.
        // The register each seeded parameter arrived in.
        let entryArgumentRegisters: [String: Int] = switch entry {
        case .swiftFunction(let map, _, _, _)?, .swiftInstance(let map, _)?: map
        default: [:]
        }
        /// `values`, the registers from x`first` on, without its trailing run
        /// of unknowns and of registers still holding their own entry value:
        /// those were left by the caller, not set up for the call. Earlier
        /// ones stay, since a pass-through receiver or argument is real
        /// (`[arg0 take:3 and:4]`).
        func withoutTrailingEntryValues(_ values: [AbstractValue], from first: Int) -> [AbstractValue] {
            var values = values
            while let last = values.last,
                  last == .unknown || entryArgumentRegisters["x\(first + values.count - 1)"]
                    .map({ last == .argument($0) }) == true {
                values.removeLast()
            }
            return values
        }
        // The parameters this function received as `inout`, whose entry
        // register holds an address.
        let inoutArguments: Set<Int> = {
            guard let signature = DisassembledFunction.splitSignature(function.analysisDisplayName),
                  let range = DisassembledFunction.outermostArgumentListRange(of: signature.head)
            else { return [] }
            let parameters = DisassembledFunction.splitTopLevelArguments(signature.head[range])
            return Set(parameters.indices.filter { Self.parameterType(parameters[$0]).hasPrefix("inout ") })
        }()
        /// Whether `value` is provably an address: a frame slot, a static
        /// address, this function's own `self` or a field of it, an indirect
        /// result, or an `inout` parameter.
        func isAddressValue(_ value: AbstractValue) -> Bool {
            switch value {
            case .frame, .address, .selfPointer, .selfField, .indirectResultPointer, .indirectResultField: true
            case .argument(let index): inoutArguments.contains(index)
            default: false
            }
        }
        var selfValueBySite: [UInt64: AbstractValue] = [:]
        /// The `self` words a value method or getter takes after (or as) its
        /// formals, by site: the ones every path that renders the call shows.
        var valueSelfBySite: [UInt64: AbstractValue] = [:]
        for insn in function.instructions {
            guard var site = sites[insn.address], Self.isSwiftCall(insn, swiftTargets: swiftTargets),
                  !importedStringReceiverSites.contains(insn.address)
            else { continue }
            // x20 not written since the last call is still the receiver of a
            // callee whose own name proves it a class instance member: x20
            // is callee-saved, so `c.m1() + c.m2()` passes c to both, and
            // the second read `P7.K.m2()`.
            // A dispatch through self's vtable already renders as `self.m(…)`.
            if site.selfValue == .unknown, !insn.isSelfDispatch, let callee = calleeByAddress[insn.address],
               Self.isClassInstanceMember(callee, classTypeIndex: classTypeIndex) {
                site.selfValue = site.x20Value
            }
            guard site.selfValue != .unknown else { continue }
            // A String result's second word moved into x20 is no receiver.
            if case .callResultHigh = site.selfValue { continue }
            // An in-image receiver requires positive entry-x20 use. A MAY
            // read of an overlapping save through an escaped frame proves
            // no context-self ABI and must not replace an ordinary argument.
            if let target = insn.branchTarget, let summary = registerSummaries[target],
               summary.provenEntryRegisterReads & (1 << 20) == 0 {
                continue
            }
            if let callee = calleeByAddress[insn.address] {
                if DisassembledFunction.receivesThinMetatype(callee, classTypeIndex: classTypeIndex)
                    || DisassembledFunction.takesNoSelf(callee)
                    || Self.signatureSpecializationRewritesSelf(callee) { continue }
                // A frozen standard-library struct's method takes `self` in
                // x20 only by address, when it is mutating; a non-mutating
                // one takes `self`'s words after its formals, and a static
                // one a thin metatype, nothing. Its name does not say which,
                // so x20 is `self` only when it holds an address:
                // `String.UTF16View.index(self: ((arg0 >>ᵁ 14) & 3), 15, …)`
                // named a scalar left in x20 as the view.
                if let isStatic = Self.standardLibraryStructMethod(callee),
                   isStatic || !isAddressValue(site.selfValue) { continue }
                // The same for any system struct or enum:
                // `_ArrayBuffer._isNative.getter(self: arg0, …)` named the
                // caller's x20, where the buffer is the one word in x0.
                // A specialization keeps the convention: `generic
                // specialization <Diagnostic> of _ArrayBuffer._consumeAndCreateNew`
                // takes the buffer in x3, after its formals, and only saves x20.
                if let isStatic = Self.systemValueTypeMember(callee),
                   isStatic || !isAddressValue(site.selfValue) { continue }
                // Nor does a global variable's addressor.
                if DisassembledFunction.isGlobalVariableAddressor(callee) { continue }
                // A value a call declared to return as a plain scalar is no
                // receiver: no method takes an Int as its self, by value or
                // by address. A caller that parks such a result in x20
                // (callee-saved) across the next call made `Pair.sum(self:
                // r0, 1)` and `Mode.code(self: r0)` of m1's Int.
                if case .callResult(let producer) = site.selfValue,
                   let producerName = calleeByAddress[producer],
                   let result = DisassembledFunction.splitSignature(producerName)?.result,
                   Self.plainScalarTypes.contains(result) { continue }
                // A free function, `Module.name(…)`, has no `self`; nor does a
                // specialization of one, whose name prints the original's
                // after its clause (`function signature specialization
                // <Arg[0] = Dead> of DeadArgs.helperI(…)` read `self=r0` for a
                // value its caller kept in x20).
                if let signature = DisassembledFunction.splitSignature(Self.withoutSpecializationClauses(callee)),
                   let range = DisassembledFunction.outermostArgumentListRange(of: signature.head) {
                    let name = signature.head[..<range.lowerBound].dropLast()
                    if name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
                       name.filter({ $0 == "." }).count == 1 { continue }
                }
            }
            selfValueBySite[insn.address] = site.selfValue
        }

        /// A selector proven by either a modern per-selector message stub or an
        /// old-style selref in x1. Stack values are never appended to a call
        /// merely because they happen to exist: only a known variadic selector
        /// makes those fresh stack stores part of the source argument list.
        func selectorName(callee: String, arguments: [AbstractValue]) -> String? {
            if callee.hasPrefix("objc_msgSend"), let marker = callee.firstIndex(of: "$") {
                return String(callee[callee.index(after: marker)...])
            }
            guard callee == "objc_msgSend" || callee.hasPrefix("objc_msgSendSuper"),
                  arguments.count > 1,
                  case .loaded(let slot) = arguments[1]
            else { return nil }
            return resolver.selector(at: slot)
        }

        if let objcIndex {
            for (address, site) in sites {
                guard let callee = calleeByAddress[address],
                      let selector = selectorName(callee: callee, arguments: site.arguments),
                      objcIndex.selectorMayReturnAggregate(selector)
                else { continue }
                // Keep the existing FP proof for a send to self: SDK `scale`
                // is globally ambiguous, but self's own declarations may all
                // prove one float. Do not override any indexed aggregate veto
                // or infer a superclass's declaration from the current owner.
                if SDKSelectorReturns.table[selector] == "h",
                   callee == "objc_msgSend" || callee.hasPrefix("objc_msgSend$"),
                   site.arguments.first == .selfPointer, let method = function.objcMethod,
                   objcIndex.selectorReturnsOneFloat(selector, className: method.className,
                                                    isClassMethod: method.isClassMethod) == true,
                   !objcIndex.selectorHasAggregateDeclaration(selector) {
                    continue
                }
                nonScalarObjCResultSites.insert(address)
            }
        }

        func isVariadicObjCSelector(_ selector: String) -> Bool {
            DisassembledFunction.MessageSend.isVariadicSelector(selector)
        }

        /// Whether the code just before the call at `address` leaves a value
        /// in v0–v7 for it: inside the call's block and after the previous
        /// call, one of them is written (`fmov d0, #1.5`, `ldr d0, [x1]`) and
        /// not then stored to memory. A register written and stored was a
        /// temporary for a copy (`ldr d0, [x8]; str d0, [sp]` building a block
        /// literal, `movi v0.2d, #0; stp q0, q0, [sp]` zeroing a struct, a
        /// variadic double put on the stack).
        let instructionIndex = Dictionary(
            function.instructions.enumerated().map { ($1.address, $0) }, uniquingKeysWith: { first, _ in first })
        let blockStarts = Set(function.instructions.compactMap(\.branchTarget))
        /// How many of v0–v7 hold one of the function's own arguments at its
        /// entry. Such an argument, untouched from the entry to a send, is a
        /// value left for it too: at -O2 `-[Relay relay:to:]` sends
        /// `[o put:x at:7]` with x still in d0, nothing writes it, and the
        /// integer layout rendered `put:7 at:?`. A method's encoding says
        /// which v registers hold an argument, and a Swift signature laid out
        /// in registers says the same. A function that shows neither, a C
        /// function or a block, may have been passed a float in any of them:
        /// `putPassed(o, x)` (C, -O2) sends `put:x at:7` with x still in d0,
        /// and the integer layout rendered `put:7 at:?`.
        let ownFloatArgumentRegisters: Int = {
            if let method = function.objcMethod {
                let colons = method.selector.filter { $0 == ":" }.count
                return ObjCArgumentABI.floatRegisterCount(encoding: method.typeEncoding, argumentCount: colons) ?? 0
            }
            if let slots = Self.swiftCallArgumentSlots(
                callee: function.analysisDisplayName, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
                return slots.reduce(0) { total, slot in
                    switch slot.kind {
                    case .floating: total + slot.registers
                    case .aggregate(_, let floats): total + floats
                    case .integer: total
                    }
                }
            }
            return 8
        }()
        /// Whether a call may leave its result in v0: unless its name's
        /// signature or C prototype returns an integer, a pointer or
        /// nothing, or its in-image body never writes v0 or calls out.
        func callMayReturnFloat(_ insn: Instruction) -> Bool {
            if let target = insn.branchTarget, let summary = registerSummaries[target], !summary.mayWriteFloatResult {
                return false
            }
            guard let callee = calleeByAddress[insn.address] else { return true }
            if let result = DisassembledFunction.cPrototype(of: callee)?.result, !isNameTwin(insn.address) {
                return !"iv".contains(result)
            }
            if let result = DisassembledFunction.splitSignature(callee)?.result {
                switch SwiftLowering.of(result, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
                case .oneInteger, .zeroSized: return false
                default: return true
                }
            }
            // Runtime entry points of known arity return an integer, a
            // pointer or nothing.
            return isNameTwin(insn.address) || DisassembledFunction.knownCArity(of: callee) == nil
        }
        func setsFloatingPointArgument(before address: UInt64, integerGap: Bool = true,
                                       receiver: AbstractValue = .unknown) -> Bool {
            guard let callIndex = instructionIndex[address] else { return false }
            var settled = Set<Int>()
            var stored = Set<Int>()
            var index = callIndex
            var reachedEntry = false
            while index > 0, !blockStarts.contains(function.instructions[index].address) {
                index -= 1
                let insn = function.instructions[index]
                // A call writes v0 with its result, if it has one, and that
                // may be the argument: `[o zput:f() at:7]` passes f()'s
                // double in d0 and rendered `zput:7 at:?`.
                if insn.controlFlow == .call {
                    // A send whose receiver is that call's x0 result proves
                    // the call returned in x0, and a C or Objective-C return
                    // is in x registers or v registers, never both: v0 holds
                    // no result of it. `[[F alloc] initWithLimit:3]` then
                    // `setLimit:4` rendered `setLimit:?`. (A Swift callee can
                    // return in both, so only a send counts.)
                    let returnedInX0 = receiver == .callResult(insn.address)
                        && calleeByAddress[insn.address].map {
                            selectorName(callee: $0, arguments: sites[insn.address]?.arguments ?? []) != nil
                        } == true
                    if !returnedInX0, !settled.contains(0), !stored.contains(0), callMayReturnFloat(insn) { return true }
                    break
                }
                if let flow = insn.controlFlow, flow != .sequential { break }
                guard let detail = insn.detail else { break }
                // The write happens after the instruction's reads, so it is
                // settled first.
                for info in detail.operands where info.isWritten {
                    guard case .register(let register) = info.operand, register.kind == .vector,
                          register.number < 8, !settled.contains(register.number)
                    else { continue }
                    settled.insert(register.number)
                    if !stored.contains(register.number) { return true }
                }
                let storesMemory = detail.operands.contains {
                    if case .memory = $0.operand { $0.isWritten } else { false }
                }
                if storesMemory {
                    for info in detail.operands where info.isRead {
                        if case .register(let register) = info.operand, register.kind == .vector,
                           register.number < 8, !settled.contains(register.number) {
                            stored.insert(register.number)
                        }
                    }
                }
                // Every instruction from the entry to the send is
                // straight-line and none of them is a call.
                if index == 0 { reachedEntry = true }
                if settled.count == 8 { break }
            }
            if callIndex == 0 { reachedEntry = true }
            // A float passed through from the entry takes one of the send's
            // argument positions, so the integer layout then leaves an
            // argument register unwritten (`putPassed`: `mov w2, #7` and
            // nothing in x3, `put:x at:7`). When every integer one is set
            // up for the send, a float in v0 would make one of those writes
            // dead.
            return reachedEntry && integerGap
                && (0 ..< min(ownFloatArgumentRegisters, 8)).contains { !settled.contains($0) }
        }

        /// The quoted literal a String's two words spell, when both are known:
        /// a small string's bytes, or a large literal's count and object.
        func swiftStringLiteral(_ low: AbstractValue, _ high: AbstractValue) -> String? {
            guard case .immediate(let first) = low else { return nil }
            if let object = Self.largeStringObjectAddress(high) {
                return resolver.swiftLargeStringLiteral(
                    objectAddress: object, count: Int(first & 0x0000_FFFF_FFFF_FFFF))
            }
            guard case .immediate(let second) = high,
                  let string = ValueTracer.decodeStringSmallString(lo: first, hi: second)
            else { return nil }
            return "\"\(ReferenceResolver.escapedLiteralText(string))\""
        }

        /// A String's two words read from one String field of `self`, as
        /// that field: `ldp x19, x20, [x20, #0x10]` handing a call
        /// `self.name`. Two words of different fields, or of a field of
        /// another type, are no String.
        /// A String's two words that are one call's String result: that call.
        func stringCallResult(_ low: AbstractValue, _ high: AbstractValue) -> UInt64? {
            guard case .callResult(let site) = low, high == .callResultHigh(site) else { return nil }
            return site
        }

        func selfStringField(_ low: AbstractValue, _ high: AbstractValue) -> String? {
            guard case .selfFieldValue(let offset) = low, high == .selfFieldValue(offset: offset + 8),
                  case .success(.whole(let name, let type))? = fieldMap?.lookup(offset: offset, bytes: 16),
                  Self.twoWordStringMangledTypes.contains(type)
            else { return nil }
            return fieldPath(name)
        }

        /// A receiver's physical footprint is not a whole String expression.
        /// Validate both words before sanitizing a call-result high word away.
        func stringReceiver(_ raw: [AbstractValue]) -> AbstractValue {
            guard raw.count == 2 else { return .unknown }
            if let site = stringCallResult(raw[0], raw[1]),
               calleeByAddress[site].flatMap({ Self.swiftReturnTypeName(forDemangledName: $0) }) == "Swift.String" {
                return .aggregate(raw)
            }
            let words = raw.map(sanitizeValue)
            return swiftStringLiteral(words[0], words[1]) != nil || selfStringField(words[0], words[1]) != nil
                ? .aggregate(words) : .unknown
        }

        /// A whole GPR expression, rather than a whole source value whose
        /// first word happened to be copied here. Width alone also cannot
        /// turn a Double field into an integer expression.
        func isWholeIntegerReceiverWord(_ value: AbstractValue, depth: Int = 0) -> Bool {
            guard depth < 8 else { return false }
            func integerField(_ map: FieldMap?, offset: Int) -> Bool {
                guard let map, let field = map.fields.first(where: { $0.offset == offset }), field.bytes <= 8,
                      let type = map.fieldTypeNames[field.name]
                else { return false }
                return SwiftLowering.of(type, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) == .oneInteger
            }
            switch value {
            case .callResult(let site):
                return calleeByAddress[site].map {
                    Self.callResultBank(of: $0, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, cache: callResultBanks) == .integer
                } ?? false
            case .callResultHigh, .aggregate, .arrayLiteral, .indirectCallResultWord:
                return false
            case .selfFieldValue(let offset):
                guard let widths = selfFieldReadWidths[offset], widths.count == 1, let width = widths.first,
                      let fieldMap, case .success(.whole) = fieldMap.lookup(offset: offset, bytes: width)
                else { return false }
                return integerField(fieldMap, offset: offset)
            case .argumentField(let argument, let offset):
                return integerField(argumentFieldMaps[argument] ?? classArgumentFieldMaps[argument], offset: offset)
            case .binary(_, let lhs, let rhs):
                return isWholeIntegerReceiverWord(lhs, depth: depth + 1) && isWholeIntegerReceiverWord(rhs, depth: depth + 1)
            case .select(let condition, let whenTrue, let whenFalse):
                return isWholeIntegerReceiverWord(condition, depth: depth + 1)
                    && isWholeIntegerReceiverWord(whenTrue, depth: depth + 1)
                    && isWholeIntegerReceiverWord(whenFalse, depth: depth + 1)
            case .unary(let op, let operand):
                switch op {
                case .negate, .bitwiseNot, .byteSwap, .leadingZeros, .leadingSignBits, .bitReverse:
                    return isWholeIntegerReceiverWord(operand, depth: depth + 1)
                default:
                    // FP conversions need a separate operand-bank proof.
                    return false
                }
            default:
                return true
            }
        }

        /// A call to an in-image function whose name is also a C library
        /// function's in the known-arity table: the table is no evidence for it.
        func isNameTwin(_ address: UInt64) -> Bool {
            if unprovenARCSites.contains(address) { return true }
            guard callTargets[address] != nil, let callee = calleeByAddress[address] else { return false }
            return DisassembledFunction.knownArityNameMayHaveTwin(callee)
        }
        func isRuntimeNoise(_ callee: String, at address: UInt64) -> Bool {
            !unprovenARCSites.contains(address) && DisassembledFunction.isRuntimeNoise(callee)
        }

        var argumentsByAddress: [UInt64: [AbstractValue]] = [:]
        /// Parameter types of the sites laid out from a signature.
        var laidOutTypes: [UInt64: [String]] = [:]
        /// Variadic sends whose variadic argument count is not provable: their
        /// fixed arguments render, followed by `…`.
        var unprovenVariadicSites: Set<UInt64> = []
        // In address order: each site records an `abi.argument-layout`
        // probe event, and Dictionary order changes with every process.
        for (address, site) in sites.sorted(by: { $0.key < $1.key }) {
            var values = site.arguments
            // Which layout decided this site's arguments. `positional` (the
            // registers as the call found them, trimmed of trailing unknowns)
            // is the one stale values have historically come through.
            var strategy = "positional"
            defer {
                Probe.record(.argumentLayout, at: address, [
                    "strategy": .label(strategy), "callee": .name(calleeByAddress[address] ?? "?"),
                    "count": .int(argumentsByAddress[address]?.count ?? 0),
                ])
            }
            // A dropped typed-error layout has no proven argument order or
            // arity. Do not retry its printed declaration, body reads or raw
            // register positions; use the existing explicit unknown tail.
            if unprovenTypedErrorSites.contains(address) {
                argumentsByAddress[address] = []
                unprovenVariadicSites.insert(address)
                strategy = "unproven-arity"
                continue
            }
            // `swift_willThrow(SWIFT_CONTEXT void *, SWIFT_ERROR_RESULT
            // SwiftError **)` (swift/include/swift/Runtime/Error.h:71) takes
            // the thrown error in x21 and nothing in x0. Rendering x0 printed
            // a stale register as the thrown value (`swift_willThrow(0)`, 105
            // times in SwiftData); the error box is x21's.
            if calleeByAddress[address] == "swift_willThrow" {
                values = site.errorValue == .unknown ? [] : [site.errorValue]
                strategy = "will-throw"
            }
            // `objc_retain_xN` takes the object in xN, nothing in x0: a
            // Swift method's `objc_retain_x20` read `args(arg0)`, x0's
            // value, where it retains `self`.
            if let callee = calleeByAddress[address], ValueTracer.retainedRegister(callee) != nil {
                argumentsByAddress[address] = [sanitizeValue(site.retainedValue)]
                strategy = "retained-register"
                continue
            }
            // A getter that takes no explicit argument shows none, whatever
            // x0 held: `static DispatchQoS.unspecified.getter(r0)` was a stale
            // register (55 static getters in one app).
            // A witness call's getter is its requirement's dispatch thunk's.
            if let callee = witnessLayoutNames[address] ?? calleeByAddress[address],
               Self.getterTakesNoArguments(callee, classTypeIndex: classTypeIndex) {
                argumentsByAddress[address] = []
                strategy = "no-parameters"
                continue
            }
            // A String's instance getter takes nothing but `self`, its two
            // words in x0 and x1: a later register is whatever the caller
            // left, and `takeTwo(_: String, _: Int)` read
            // `String.utf8.getter(?, ?, arg1)` with its Int still in x2.
            if let callee = calleeByAddress[address], Self.isStringInstanceGetter(callee) {
                argumentsByAddress[address] = (0 ..< 2).map { $0 < values.count ? sanitizeValue(values[$0]) : .unknown }
                strategy = "string-getter"
                continue
            }
            // A value type's instance getter takes no formal parameter: its
            // registers from x0 are `self`'s words, as many as the type
            // lowers to, and nothing after them. Positional, `Pair(a: x,
            // b: 4).total` read `Pair.total.getter(arg0, 4)`, a getter with
            // two arguments. It renders `total.getter(self: (arg0, 4))`.
            // Only when the site has no `self` in x20: a witness through an
            // existential, or a struct passed by address (`VersionTuple.
            // normalized.getter(self: local_80)`), takes it there.
            if selfValueBySite[address] == nil, let callee = calleeByAddress[address],
               let property = DisassembledFunction.swiftAccessorProperty(callee), property.isGetter,
               !callee.hasPrefix("static "), !callee.contains(".subscript"),
               let accessor = callee.range(of: ".\(property.property).getter"),
               case let receiver = String(callee[..<accessor.lowerBound]), classTypeIndex.isValueType(receiver),
               typeFieldMaps[receiver]?.isGeneric == false,
               let words = SwiftLowering.aggregateRegisters(of: receiver, fieldMaps: typeFieldMaps,
                                                            enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex),
               words.floats == 0, (1...4).contains(words.integers) {
                let own = (0 ..< words.integers).map { $0 < values.count ? sanitizeValue(values[$0]) : .unknown }
                let value: AbstractValue = own.count == 1 ? own[0] : .aggregate(own)
                selfValueBySite[address] = value
                valueSelfBySite[address] = value
                argumentsByAddress[address] = []
                strategy = "value-getter-self"
                continue
            }
            // A Swift callee with a proven layout gets exactly its parameters:
            // integer slots from x0… and float slots from v0…, each in order on
            // its own counter, with no trailing trim, so its arity shows.
            // A String's two words are one argument, kept only as a literal
            // both words spell: a known first word over an unknown second is
            // not that String. Read one register per word, `takeTwo(_: String,
            // _: Int)` with nothing tracked rendered `takeTwo()`, and with 7
            // in x2 `takeTwo(?, ?, 7)`.
            let swiftLayout: SwiftArgumentLayout? = calleeByAddress[address].flatMap {
                Self.swiftCallArgumentLayout(
                    callee: layoutName(at: address, callee: $0),
                    enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, fieldMaps: typeFieldMaps)
            }
            let swiftSlots = swiftLayout?.slots
            let cLayout = swiftSlots != nil || isNameTwin(address)
                ? nil : calleeByAddress[address].flatMap { Self.cPrototypeLayout(callee: $0) }
            // A value type's method takes its formal parameters from x0 too,
            // and then, unless it is mutating (`self` by address in x20),
            // `self`'s words: which, its name does not say. The formal
            // parameters are laid out and the registers after them kept as
            // found. `String.append(_:)` with an untracked argument read
            // `append(self: s)`, and with a small literal `append(10,
            // 0xe100000000000000)`.
            // A formal it cannot place (a struct, a parameter past x7) and
            // every one after it are `?`, and then where `self`'s words start
            // is unknown too, so nothing after them is shown.
            let leadingLayout = swiftSlots == nil && cLayout == nil
                ? calleeByAddress[address].flatMap {
                    Self.swiftCallArgumentLayout(
                        callee: layoutName(at: address, callee: $0),
                        enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, anyContext: true, fieldMaps: typeFieldMaps)
                }
                : nil
            let leadingSlots = leadingLayout?.slots
            /// Whether a call's v0 is its whole result: a `float` or `double`
            /// its declaration proves. A struct comes back in several v
            /// registers, so a later argument holding one of them is a part
            /// of it: Terminal's `NSOffsetRect(r, frame.origin.x,
            /// frame.origin.y)` after `frame = [? rect]` read
            /// `NSOffsetRect(?, r0, ?)`.
            func returnsOneFloat(_ site: UInt64) -> Bool {
                guard let callee = calleeByAddress[site] else { return false }
                if !isNameTwin(site), let result = DisassembledFunction.cPrototype(of: callee)?.result {
                    return result == "f" || result == "d"
                }
                if let type = Self.swiftReturnTypeName(ofDemangled: callee) {
                    return ["Swift.Double", "Swift.Float", "Swift.Float64", "Swift.Float32",
                            "Swift.CGFloat", "CoreGraphics.CGFloat"].contains(type)
                }
                if callee.hasPrefix("objc_msgSend$"), let objcIndex {
                    let selector = String(callee.dropFirst("objc_msgSend$".count))
                    if sites[site]?.arguments.first == .selfPointer, let method = function.objcMethod,
                       let declared = objcIndex.selectorReturnsOneFloat(
                           selector, className: method.className, isClassMethod: method.isClassMethod) {
                        return declared
                    }
                    return objcIndex.selectorReturnsOneFloat(selector)
                }
                return false
            }
            /// Whether every call result a float value is built from is that
            /// call's whole result. Below a conversion the operand is an
            /// integer register's, which this does not judge.
            func holdsWholeResults(_ value: AbstractValue, depth: Int = 0) -> Bool {
                guard depth < 8 else { return false }
                switch value {
                case .callResult(let site): return returnsOneFloat(site)
                case .binary(_, let lhs, let rhs):
                    return holdsWholeResults(lhs, depth: depth + 1) && holdsWholeResults(rhs, depth: depth + 1)
                case .unary(.toFloat, _), .unary(.unsignedToFloat, _): return true
                case .unary(_, let operand): return holdsWholeResults(operand, depth: depth + 1)
                case .select(let condition, let whenTrue, let whenFalse):
                    return holdsWholeResults(condition, depth: depth + 1) && holdsWholeResults(whenTrue, depth: depth + 1)
                        && holdsWholeResults(whenFalse, depth: depth + 1)
                default: return true
                }
            }
            if let slots = swiftSlots ?? cLayout?.slots ?? leadingSlots {
                var integer = 0, floating = 0
                let laidOut: [AbstractValue] = slots.map { slot in
                    switch slot.kind {
                    case .integer:
                        defer { integer += slot.registers }
                        let raw = (integer ..< integer + slot.registers).map {
                            $0 < values.count ? values[$0] : AbstractValue.unknown
                        }
                        let words = raw.map(sanitizeValue)
                        if let payload = Self.optionalScalarPayload(ofParameterType: slot.type) {
                            return Self.optionalScalarArgument(words, payloadBytes: payload.bytes)
                        }
                        // A StaticString is its text when its first word
                        // points at it; a scalar or anything else is `?`.
                        if slot.type == "Swift.StaticString" {
                            if case .address = words[0] { return words[0] }
                            return .unknown
                        }
                        // A metatype is metadata: a static address, a load of
                        // one, or an accessor's result. Anything else in its
                        // register was not set up for it: `describe(Int.self,
                        // k)`, whose callee ignores `t`, leaves `k` in x0.
                        if slot.type.hasSuffix(".Type") {
                            switch words[0] {
                            case .address, .loaded, .callResult: return words[0]
                            default: return .unknown
                            }
                        }
                        if words.count == 2 {
                            if let site = stringCallResult(raw[0], raw[1]) {
                                return .aggregate([.callResult(site), .callResultHigh(site)])
                            }
                            return swiftStringLiteral(words[0], words[1]) != nil
                                || selfStringField(words[0], words[1]) != nil ? .aggregate(words) : .unknown
                        }
                        return words[0]
                    case .aggregate(let x, let v):
                        // A struct's registers: its value is not one of them.
                        integer += x
                        floating += v
                        return .unknown
                    case .floating:
                        defer { floating += slot.registers }
                        // An HFA argument spans its registers; it renders `?`.
                        guard slot.registers == 1, floating < site.floatArguments.count else { return .unknown }
                        let value = site.floatArguments[floating]
                        return cLayout == nil || holdsWholeResults(value) ? value : .unknown
                    }
                }
                var unplaced = Array(repeating: AbstractValue.unknown,
                                     count: cLayout?.unplaced ?? swiftLayout?.unplaced ?? leadingLayout?.unplaced ?? 0)
                if cLayout == nil, let swiftLayout, !swiftLayout.stack.isEmpty {
                    let stackWords = Self.stackParameterWords(
                        swiftLayout, stackArguments: site.stackArguments, widths: site.stackArgumentWidths)
                    unplaced = zip(swiftLayout.stack, stackWords).map { parameter, words in
                        guard let words = words?.map(sanitizeValue) else { return .unknown }
                        switch parameter.type {
                        case "Swift.StaticString":
                            if case .address = words[0] { return words[0] }
                            return .unknown
                        case _ where words.count == 2:
                            return swiftStringLiteral(words[0], words[1]) != nil ? .aggregate(words) : .unknown
                        default:
                            return words[0]
                        }
                    }
                }
                var following: [AbstractValue] = []
                var followingTypes: [String] = []
                if leadingSlots != nil {
                    // The registers after the formal parameters are `self`'s
                    // words only for a non-mutating method. A call whose
                    // `self` is proven in x20 is mutating, and what follows is
                    // whatever the caller still held: `append(self: arg0, ?,
                    // arg2, arg3, arg4)` for a one-String `append(_:)`.
                    // A generic method's generic metadata and witness tables
                    // follow `self`, so its registers past the formals are
                    // not `self`'s words alone: `nestedContainer<A where
                    // A1: …>(0x46910, local_448, <metadata>, 0x46910)`.
                    let isGeneric = calleeByAddress[address].map {
                        DisassembledFunction.splitSignature($0).map { signature in
                            DisassembledFunction.outermostArgumentListRange(of: signature.head).map {
                                signature.head[..<$0.lowerBound].contains("<")
                            } ?? true
                        } ?? true
                    } ?? true
                    // When the receiver's own registers are known and any of
                    // them is a v register, no x register after the formals
                    // is all of `self`: `ABIVec2.dot(_:)` takes
                    // `self`'s two Doubles in d2 and d3, and read `dot(?,
                    // sub_…())`, a stale x0 as `self`.
                    let receiver = calleeByAddress[address].flatMap(Self.valueMethodReceiver).flatMap {
                        SwiftLowering.directAggregateRegisters(of: $0, fieldMaps: typeFieldMaps,
                                                         enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex)
                    }
                    let receiverSummary = callTargets[address].flatMap { registerSummaries[$0] }
                    let hasContextRole = receiverSummary.map { $0.provenEntryRegisterReads & (1 << 20) != 0 } ?? false
                    if selfValueBySite[address] == nil, !hasContextRole, leadingLayout?.unplaced == 0, !isGeneric {
                        if importedStringReceiverSites.contains(address), integer == 2 {
                            let raw = (integer ..< integer + 2).map { $0 < values.count ? values[$0] : .unknown }
                            following = [stringReceiver(raw)]
                            followingTypes = ["Swift.String"]
                        } else if let summary = receiverSummary, let receiver, receiver.floats == 0,
                                  receiver.integers > 0, integer + receiver.integers <= 8,
                                  (integer ..< integer + receiver.integers).allSatisfy({ summary.provenEntryRegisterReads & (1 << $0) != 0 }) {
                            // The exact ordinary inputs must be positively
                            // read, irrespective of legacy MAY-x20 analysis.
                            // An unchanged entry value is still a real input.
                            following = (integer ..< integer + receiver.integers).map {
                                $0 < values.count && isWholeIntegerReceiverWord(values[$0]) ? sanitizeValue(values[$0]) : .unknown
                            }
                            followingTypes = following.map { _ in "" }
                        } else if let summary = receiverSummary, let receiver, receiver.integers == 0,
                                  receiver.floats > 0, floating + receiver.floats <= 8,
                                  (floating ..< floating + receiver.floats).allSatisfy({ summary.provenFloatArgumentReads.contains($0) }) {
                            // A struct of floating-point fields takes its self
                            // in the v registers after the float formals:
                            // `P(x: 3.5, y: 4.25).length()` is `fmov d0, #3.5;
                            // fmov d1, #4.25; b P.length`, and read `length()`.
                            // A constant renders as the float its bits spell, at
                            // the width the body reads it.
                            let words = (floating ..< floating + receiver.floats).map { index -> AbstractValue in
                                guard index < site.floatArguments.count else { return .unknown }
                                let value = sanitizeValue(site.floatArguments[index])
                                guard let bits = summary.floatArgumentWidths[index] else { return .unknown }
                                return ValueTracer.floatOperand(value, bits: bits)
                            }
                            let value: AbstractValue = words.count == 1 ? words[0] : .aggregate(words)
                            selfValueBySite[address] = value
                            valueSelfBySite[address] = value
                        } else if receiverSummary != nil, receiver == nil || receiver?.floats ?? 0 > 0 {
                            // A receiver whose words are not all known here (a
                            // payload enum, a struct mixing integer and float
                            // fields): its self still travels with the call.
                            // Dropped, `E.pair(301, 302).tag(303)` read
                            // `E.tag(303)`, a call with no receiver. Only for
                            // an in-image callee whose body was summarized: an
                            // imported mutating method (string interpolation's
                            // `appendLiteral`) takes self in x20, not here.
                            selfValueBySite[address] = .unknown
                            valueSelfBySite[address] = .unknown
                        }
                    }
                }
                // Those words are the receiver, not more arguments: listed
                // after the formals, `Pair(a: 3, b: 4).scaled(k)` read
                // `Pair.scaled(arg0, 3, 4)`, a one-parameter method with
                // three. They render as its `self`, `scaled(self: (3, 4),
                // arg0)`, as a class method's `self` in x20 does.
                // They are `self` only when the receiver's type lowers to
                // exactly that many integer words: a method of a generic type
                // (`Array._endMutation()`) takes the type's metadata there,
                // which is no `self`.
                let selfWords = calleeByAddress[address].flatMap(Self.valueMethodReceiver).flatMap { receiver in
                    typeFieldMaps[receiver]?.isGeneric == false
                        ? SwiftLowering.aggregateRegisters(of: receiver, fieldMaps: typeFieldMaps,
                                                           enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex)
                        : nil
                }.flatMap { $0.floats == 0 ? $0.integers : nil }
                if !following.isEmpty, let selfWords, following.count <= selfWords {
                    let value: AbstractValue = following.count == 1 ? following[0] : .aggregate(following)
                    selfValueBySite[address] = value
                    valueSelfBySite[address] = value
                    following = []
                }
                if !(laidOut + unplaced + following).isEmpty {
                    argumentsByAddress[address] = (laidOut + unplaced).map(sanitizeValue) + following
                    laidOutTypes[address] = slots.map(\.type) + unplaced.map { _ in "" } + followingTypes
                }
                strategy = leadingSlots != nil ? "swift-leading" : cLayout == nil ? "swift-signature" : "c-declaration"
                continue
            }
            // A witness call whose requirement's parameters this cannot
            // place takes nothing it can show: its x0 and x1 may be the
            // requirement's Self metadata and witness table, so they are not
            // read by position. Its arguments render as `…`.
            if witnessLayoutNames[address] != nil {
                argumentsByAddress[address] = []
                unprovenVariadicSites.insert(address)
                strategy = "witness-unplaced"
                continue
            }
            // A runtime entry point of known C arity takes exactly its
            // parameters, unknown ones as `?`: with the trailing trim,
            // `memcpy` whose operands were all unknown read `memcpy()`, a
            // call that takes nothing.
            if let callee = calleeByAddress[address], let arity = DisassembledFunction.knownCArity(of: callee),
               callee != "swift_willThrow", !isNameTwin(address) {
                argumentsByAddress[address] = (0..<arity).map { $0 < values.count ? sanitizeValue(values[$0]) : .unknown }
                strategy = "c-arity"
                continue
            }
            // A C printf-family call passes its variadic arguments on the stack
            // (Apple arm64), one 8-byte slot each, in format order: x1 at the
            // call is scratch. `printf("%ld\n", x)` rendered `printf(0x534)`,
            // dropping x, and a stale x1 could read as the first value. The
            // count comes from the format's own bytes; an unreadable format
            // shows the fixed arguments, then `…`. An in-image function with
            // such a name is no evidence for that layout: `printf(long, long)`
            // rendered `printf(?, …)` for `printf(x, 4)`.
            if let callee = calleeByAddress[address], !isNameTwin(address),
               let variadic = Self.cFormatVariadics[callee] ?? Self.cFormatVariadics[Self.stripLeadingUnderscore(callee)] {
                let fixed = (0 ..< variadic.fixed).map { $0 < values.count ? values[$0] : AbstractValue.unknown }
                var kinds: [DisassembledFunction.MessageSend.FormatArgumentKind]?
                var formatText: String?
                if case .address(let format) = fixed[variadic.format] {
                    formatText = resolver.cfString(at: format)
                        ?? ReferenceResolver.rawCString(at: format, in: resolver.machO, ranges: resolver.fileRanges)
                            .map { "\"\($0)\"" }
                    kinds = formatText.flatMap(DisassembledFunction.MessageSend.formatArgumentKinds)
                }
                if let kinds {
                    let variadicValues = (0 ..< kinds.count).map {
                        $0 < site.stackArguments.count ? sanitizeValue(site.stackArguments[$0]) : AbstractValue.unknown
                    }
                    argumentsByAddress[address] = fixed.map(sanitizeValue) + variadicValues
                    // A Double's slot by its stored bits, an integer's by its
                    // conversion: `printf("%d", -1)` read `printf(…, 0xffffffff)`.
                    let doubles = Self.formatSlotTypes(kinds, values: variadicValues, storedBytes: site.stackArgumentWidths)
                    let integers = formatText.flatMap(DisassembledFunction.MessageSend.formatIntegerTypes)
                    let types = (0 ..< kinds.count).map { index -> String in
                        let double = doubles.map { $0[index] } ?? ""
                        return double.isEmpty ? integers.map { index < $0.count ? $0[index] : "" } ?? "" : double
                    }
                    if types.contains(where: { !$0.isEmpty }) {
                        laidOutTypes[address] = Array(repeating: "", count: fixed.count) + types
                    }
                    strategy = "c-format"
                } else {
                    argumentsByAddress[address] = fixed.map(sanitizeValue)
                    unprovenVariadicSites.insert(address)
                    strategy = "c-format-unread"
                }
                continue
            }
            // A declared variadic with no format (`int open(const char *, int,
            // ...)`): Apple arm64 passes the fixed arguments in registers and
            // every variadic one on the stack, so the fixed ones render from
            // their registers at their declared widths, then `…`. It read
            // `open(…)` with x0 and w1 set just before the call. Only integer
            // fixed parameters; an in-image twin is no evidence for the layout.
            if let callee = calleeByAddress[address], !isNameTwin(address),
               let prototype = DisassembledFunction.cPrototype(of: callee), prototype.isVariadic,
               prototype.parameters.count <= 8 {
                let types = prototype.parameters.compactMap { DisassembledFunction.cIntegerParameterTypes[$0] }
                if types.count == prototype.parameters.count {
                    argumentsByAddress[address] = (0 ..< types.count).map {
                        $0 < values.count ? sanitizeValue(values[$0]) : .unknown
                    }
                    laidOutTypes[address] = types
                    unprovenVariadicSites.insert(address)
                    strategy = "c-variadic"
                    continue
                }
            }
            // A format selector's variadic arguments are exactly its format's
            // conversions, one stack slot each: `?` where a slot is unknown,
            // none dropped as trailing unknowns, no stale x3–x7 before them.
            if let callee = calleeByAddress[address],
               let selector = selectorName(callee: callee, arguments: values),
               isVariadicObjCSelector(selector), selector.hasSuffix("Format:") {
                let fixed = 2 + selector.filter { $0 == ":" }.count
                if fixed <= 8, values.count >= fixed,
                   case .address(let formatAddress) = values[fixed - 1],
                   let literal = resolver.name(at: formatAddress),
                   let kinds = DisassembledFunction.MessageSend.formatArgumentKinds(literal) {
                    let variadic = (0 ..< kinds.count).map {
                        $0 < site.stackArguments.count ? sanitizeValue(site.stackArguments[$0]) : .unknown
                    }
                    argumentsByAddress[address] = Array(values.prefix(fixed)).map(sanitizeValue) + variadic
                    if let types = Self.formatSlotTypes(kinds, values: variadic, storedBytes: site.stackArgumentWidths) {
                        laidOutTypes[address] = Array(repeating: "", count: fixed) + types
                    }
                    strategy = "objc-format"
                    continue
                }
            }
            // A message send's explicit arguments follow its declared signature
            // across the x and v banks: a `double` argument is in d0, and the
            // integer after it in x2, not x3. Positionally, `[self
            // setAlpha:0.5]` showed whatever x2 held. For a send to self the
            // declaration of self's class is used when every implementation in
            // the image agrees; for a receiver of unknown class, a selector that
            // some implementation takes floats for shows its arguments as `?`.
            // (Recovered from the pre-merge stash 983aa25.)
            if let objcIndex, let callee = calleeByAddress[address],
               let selector = selectorName(callee: callee, arguments: values),
               !isVariadicObjCSelector(selector) {
                let receiver = values.first ?? .unknown
                let selectorValue = values.count > 1 ? values[1] : .unknown
                let colons = selector.filter { $0 == ":" }.count
                // The receiver's class: self's, or a typed ivar's (`@"Target"`).
                let receiverClass: (name: String, isClass: Bool)? = {
                    if receiver == .selfPointer, let method = function.objcMethod {
                        return (method.className, method.isClassMethod)
                    }
                    guard objcFieldSyntax, case .selfFieldValue(let offset) = receiver, let fieldMap,
                          case .success(.whole(_, let encoding)) = fieldMap.lookup(offset: offset, bytes: 8),
                          encoding.hasPrefix("@\""), encoding.hasSuffix("\""), encoding.count > 3
                    else { return nil }
                    let name = String(encoding.dropFirst(2).dropLast())
                    guard !name.isEmpty, !name.contains("<"), !name.contains("\"") else { return nil }
                    return (name, false)
                }()
                let signature: ObjCMetadataIndex.OutgoingSignature = receiverClass.map {
                    objcIndex.outgoingSignature(selector: selector, className: $0.name, isClassMethod: $0.isClass)
                } ?? .unavailable
                switch signature {
                case .known(let encoding, let types):
                    var explicit = Array(repeating: AbstractValue.unknown, count: types.count)
                    let locations = ObjCArgumentABI.locations(encoding: encoding, argumentCount: types.count)
                    let stackWidths = ObjCArgumentABI.stackSlotWidths(encoding: encoding, argumentCount: types.count)
                    // Struct arguments on the stack count too: a store that
                    // runs into one is not the argument before it alone.
                    let stackStarts = ObjCArgumentABI.stackArgumentStarts(encoding: encoding, argumentCount: types.count)
                    for (location, argument) in locations {
                        if location.hasPrefix("x"), let register = Int(location.dropFirst()) {
                            explicit[argument] = register < values.count ? values[register] : .unknown
                        } else if location.hasPrefix("v"), let register = Int(location.dropFirst()) {
                            explicit[argument] = register < site.floatArguments.count ? site.floatArguments[register] : .unknown
                        } else if location.hasPrefix("stack@"), let offset = Int(location.dropFirst("stack@".count)),
                                  offset % 8 == 0, offset / 8 < site.stackArgumentWidths.count,
                                  let bytes = stackWidths[location] {
                            guard ObjCArgumentABI.storeHoldsOnlyArgument(
                                at: offset, bytes: bytes, storedBytes: site.stackArgumentWidths[offset / 8],
                                stackStarts: stackStarts)
                            else { continue }
                            explicit[argument] = site.stackArguments[offset / 8]
                        }
                    }
                    argumentsByAddress[address] = ([receiver, selectorValue] + explicit).map(sanitizeValue)
                    laidOutTypes[address] = ["", ""] + types.map { type in
                        switch type {
                        case "f": "Swift.Float"
                        case "d", "D": "Swift.Double"
                        case "B": "Swift.Bool"
                        default: ""
                        }
                    }
                    strategy = "objc-signature"
                    continue
                case .declined:
                    argumentsByAddress[address] = ([receiver, selectorValue]
                        + Array(repeating: AbstractValue.unknown, count: colons)).map(sanitizeValue)
                    strategy = "objc-signature-disputed"
                    continue
                case .unavailable:
                    // A receiver whose class does not declare the selector
                    // inherits or forwards it, so the image's
                    // implementations are evidence for it as well:
                    // `[self span:r count:5]` from a subclass that inherits
                    // span:count: read the range as both arguments.
                    if colons > 0, let kept = objcIndex.positionalArgumentPrefix(selector) {
                        // `values` is x0-x7, so no stack argument is kept:
                        // its offset depends on the sizes before it.
                        let explicit = (0 ..< colons).map { argument in
                            argument < kept && 2 + argument < values.count ? values[2 + argument] : AbstractValue.unknown
                        }
                        argumentsByAddress[address] = ([receiver, selectorValue] + explicit).map(sanitizeValue)
                        strategy = "objc-maybe-nonpositional"
                        continue
                    }
                    // With no signature the explicit arguments are laid out
                    // as all integers, x2 on. A floating-point argument
                    // travels in v0 and on, so a value left in one of them
                    // for the send disproves that layout: `put:1.5 at:7`
                    // rendered `put:7 at:?`.
                    let integerGap = (0 ..< min(colons, 6)).contains { argument in
                        let index = 2 + argument
                        guard index < values.count else { return true }
                        let value = sanitizeValue(values[index])
                        return value == .unknown || value == .argument(index)
                    }
                    if colons > 0, setsFloatingPointArgument(before: address, integerGap: integerGap, receiver: receiver) {
                        argumentsByAddress[address] = ([receiver, selectorValue]
                            + Array(repeating: AbstractValue.unknown, count: colons)).map(sanitizeValue)
                        strategy = "objc-untyped-float"
                        continue
                    }
                }
            }
            // Stack values follow the register arguments by position, so the
            // registers are padded to their full count first: appended after a
            // trimmed list they slid into the fixed positions, and
            // `[NSArray arrayWithObjects:a, b, nil]` rendered its nil sentinel as
            // the first object (`arrayWithObjects:0`).
            if let callee = calleeByAddress[address],
               let selector = selectorName(callee: callee, arguments: values) {
                let colons = selector.filter { $0 == ":" }.count
                if isVariadicObjCSelector(selector) {
                    let fixed = min(2 + colons, 8)
                    var laidOut = (0 ..< fixed).map { $0 < values.count ? values[$0] : .unknown }
                    if selector.hasSuffix("WithObjects:") || selector.hasSuffix("WithObjectsAndKeys:") {
                        // nil-terminated: the list ends at the first nil, and an
                        // empty list ends at the fixed one.
                        if laidOut.last != .immediate(0) {
                            if let end = site.stackArguments.firstIndex(of: .immediate(0)) {
                                laidOut += site.stackArguments[...end]
                            } else {
                                unprovenVariadicSites.insert(address)
                            }
                        }
                    } else {
                        // A format whose conversions are not readable: the count
                        // is unknown, and contiguous stack slots may be spills.
                        unprovenVariadicSites.insert(address)
                    }
                    argumentsByAddress[address] = laidOut.map(sanitizeValue)
                    strategy = "objc-variadic"
                    continue
                }
                // With no signature the arguments' sizes are unknown. One
                // eight-byte slot per argument holds only where the area has
                // exactly one aligned store per argument: packed arguments
                // (two ints in one slot, or one at sp+4) leave fewer, and an
                // argument wider than a slot leaves more.
                let fixedStackCount = max(0, colons - 6)
                if fixedStackCount > 0, site.stackArgumentWidths.count == fixedStackCount {
                    values = (0 ..< 8).map { $0 < values.count ? values[$0] : .unknown }
                        + site.stackArguments.prefix(fixedStackCount)
                }
            }
            // An ordinary setter's assigned value is one source formal,
            // even when neither its value nor receiver placement is proved.
            // Keep it unplaced instead of reading a guessed positional word;
            // the separate selfValueBySite receiver remains unchanged.
            if unplacedSetterValueSites.contains(address) {
                argumentsByAddress[address] = [.unknown]
                strategy = "unplaced-setter-value"
                continue
            }
            // A generic specialization whose concrete parameter layout is
            // unavailable has no proved mapping from machine inputs to source
            // formals. Keep that uncertainty explicit, including without a
            // body summary; neither a highest register nor printed A is arity.
            if unprovenGenericLayoutSites.contains(address) {
                argumentsByAddress[address] = []
                unprovenVariadicSites.insert(address)
                strategy = "unproven-generic-layout"
                continue
            }
            // An in-image callee no signature describes passes what its body
            // reads: `bump(void)` after `printf` rendered `bump(printf(…))`,
            // and an outlined fragment that reads no argument register took
            // whatever x0 held.
            // A Swift signature names its parameters even where the -O body
            // ignores them (`gen<A>(arg0, arg1)`), so only a callee with none
            // (C, `sub_…`, an outlined fragment) is bounded by its body. A
            // specialization that drops or reshapes parameters prints its
            // original's signature, not its own, so it has none either:
            // `<Arg[0] = Dead> of helperI(Swift.Int, Swift.Int)` takes x0
            // alone, and positionally read `helperI(arg1, arg1)`.
            // A closure's printed signature lists its formals only; what it
            // captured follows them as more arguments (`ldr x1, [x20, #0x10];
            // b closure #1` passed k after y, and rendered `closure #1 (arg0)`).
            if let target = callTargets[address], let summary = registerSummaries[target],
               calleeByAddress[address].flatMap({ DisassembledFunction.splitSignature($0) }) == nil
                || calleeByAddress[address].map({ !followsASignature(target: target, callee: $0) }) == true
                || calleeByAddress[address].map({ $0.hasPrefix("closure #") || $0.hasPrefix("implicit closure #") }) == true,
               calleeByAddress[address].flatMap({ selectorName(callee: $0, arguments: values) }) == nil,
               calleeByAddress[address].flatMap(DisassembledFunction.knownCArity(of:)) == nil || isNameTwin(address) {
                // A register below the highest one read that the body never
                // reads holds whatever the caller left there, not an argument:
                // `useSecond` writes x0 before reading it, and
                // `useSecond(5, 7)` showed the stale 5. Every register
                // through the highest the body's instructions prove (directly
                // or through an exact branch alias) is a parameter, so an
                // unknown one is `?`, not absent:
                // `sink(long)` called with nothing tracked rendered `sink()`.
                // Past those, a register the body may read only by passing it
                // to a call is shown when its value is known, as before.
                let proven = summary.provenArgumentCount
                var bounded = (0 ..< max(summary.argumentCount, proven)).map {
                    $0 < values.count && summary.argumentReads.contains($0)
                        ? sanitizeValue(values[$0]) : AbstractValue.unknown
                }
                while bounded.count > proven, bounded.last == .unknown { bounded.removeLast() }
                // A body that reads v registers has floating-point parameters
                // on their own counter. Alone, they are its arguments in
                // order. Beside integer ones, the order between the two banks
                // is not in the body, so each parameter is `?`: `mixed(long,
                // double, long)` rendered `mixed(?, 7)`, the 7 in the Double's
                // place, and `takef3(double, double, double)` `takef3()`.
                let floats = summary.provenFloatArgumentCount
                if floats > 0 {
                    // A constant renders as a float of the width the body
                    // reads it at, not as its bit pattern.
                    func floatArgument(_ index: Int) -> AbstractValue {
                        guard index < site.floatArguments.count else { return .unknown }
                        let value = sanitizeValue(site.floatArguments[index])
                        if let bits = summary.floatArgumentWidths[index] {
                            return ValueTracer.floatOperand(value, bits: bits)
                        }
                        return value
                    }
                    bounded = bounded.isEmpty
                        ? (0 ..< floats).map(floatArgument)
                        : Array(repeating: .unknown, count: bounded.count + floats)
                }
                if !bounded.isEmpty { argumentsByAddress[address] = bounded }
                // A body that loads from the caller's outgoing area takes
                // stack arguments too: `c9(?)` claimed one argument where
                // the call also passes 100 at [sp]. Their count is not
                // proven, so the list ends in `…`.
                if summary.readsIncomingStack {
                    argumentsByAddress[address] = argumentsByAddress[address] ?? []
                    unprovenVariadicSites.insert(address)
                }
                strategy = "body-reads"
                continue
            }
            // An async callee not laid out above takes its formals behind an
            // indirect result's buffer in x0, and x0 may hold the callee
            // context: by position `bigRes(_ x: Int) async -> Big5` read
            // `bigRes(?, arg0)` and `bumpG()` read `bumpG(?)`. Its declared
            // parameters are shown, each unknown.
            // A resume funclet's name prints its function's signature, but it
            // takes only the context.
            // So does a generic function whose tuple result takes its buffers
            // first, from x0: `split<A>(_: A, _: Int) -> (A, Swift.Int)` read
            // `split<A>(local_18, local_20, ?, 0x4010)`, the buffer as `x` and
            // the metadata as an argument.
            if let callee = calleeByAddress[address], !callee.contains("resume partial function for "),
               let signature = DisassembledFunction.splitSignature(callee),
               signature.isAsync || Self.returnsGenericTupleFromX0(callee),
               let range = DisassembledFunction.outermostArgumentListRange(of: signature.head) {
                let parameters = DisassembledFunction.splitTopLevelArguments(signature.head[range])
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                argumentsByAddress[address] = parameters.map { _ in .unknown }
                strategy = "declared-count"
                continue
            }
            // A bare C symbol outside this image that no table, declaration
            // or body bounds: its arity is not in the binary. The registers
            // the call found are not its arguments: `extern void A(void)`
            // called after `P(a)` read `A(r0)`, P's stale result, and `P(a +
            // 1)` with x0 untracked read `P()`. It renders `A(…)`.
            if undeclaredCImportCalls.contains(address) {
                argumentsByAddress[address] = []
                unprovenVariadicSites.insert(address)
                strategy = "unproven-arity"
                continue
            }
            if let values = sanitize(values) { argumentsByAddress[address] = values }
        }

        /// Runtime entry points with a fixed public ABI often inherit unrelated
        /// live values in later argument registers. Keep only parameters the
        /// helper actually accepts before embedding it in a source expression.
        func normalizedArguments(callee: String, values: [AbstractValue], at address: UInt64?) -> [AbstractValue] {
            // Not for a call to an in-image function that shares the name.
            if let address, isNameTwin(address) { return values }
            return DisassembledFunction.knownCArity(of: callee).map { Array(values.prefix($0)) } ?? values
        }

        /// Render a runtime helper as the source send it lowers from.
        /// The table lives with `MessageSend` in Pseudo.swift — one definition,
        /// used by both the nested-expression and statement paths.
        func objcRuntimeIdiom(callee: String, arguments: [AbstractValue], depth: Int) -> String? {
            guard depth < 8 else { return nil }
            let rendered = arguments.prefix(2).map { renderValue($0, depth: depth + 1) }
            return DisassembledFunction.objcRuntimeIdiom(callee: callee, arguments: Array(rendered))
        }

        /// Reconstruct an array literal from the values stored into its allocation.
        /// Only a homogeneous literal — exactly `count` element stores, no boxed
        /// `[Any]` type-metadata interleaved — is rendered `[e0, …]`; anything else
        /// (a boxed existential array, an unrecovered element) stays `[…]`, so the
        /// contents are never fabricated.
        func renderArrayLiteral(site: UInt64, count: Int, depth: Int) -> String {
            let stored = analysis.arrayElements[site] ?? [:]
            guard count > 0, stored.count == count, depth < 5 else { return "[…]" }
            var elements: [String] = []
            for (_, value) in stored.sorted(by: { $0.key < $1.key }) {
                let rendered = renderValue(sanitizeValue(value), depth: depth + 1)
                guard rendered != "?", !DisassembledFunction.isGenericPlumbingArgument(rendered)
                else { return "[…]" }
                elements.append(rendered)
            }
            return "[\(elements.joined(separator: ", "))]"
        }

        /// The enum-case name for a compared operand, when it is a bare tag
        /// immediate of a known no-payload enum — `enumType` from a
        /// `__derived_enum_equals` callee, else inferred from a seeded enum
        /// argument on the other side. Nil declines to the operand's raw form.
        func enumCaseOperand(_ value: AbstractValue, enumType: String?) -> String? {
            guard let enumType, case .immediate(let tag) = sanitizeValue(value),
                  tag <= UInt64(Int.max),
                  let name = enumCaseIndex.caseName(ofEnum: enumType, tag: Int(tag))
            else { return nil }
            return "\(enumType).\(name)"
        }

        /// The enum type of a comparison operand that is a seeded no-payload enum
        /// argument, unwrapping the optimizer's `& 0xFF` tag-extraction mask.
        func enumArgumentType(of value: AbstractValue) -> String? {
            switch value {
            case .argument(let index):
                return argumentEnumTypes[index]
            case .selfFieldValue(offset: 0) where selfEnumType != nil:
                return selfEnumType
            case .binary(.bitAnd, let inner, .immediate(let mask))
                where mask == 0xFF || mask == 0xFFFF || mask == 0xFFFF_FFFF:
                return enumArgumentType(of: inner)
            default:
                return nil
            }
        }

        /// The operand render for a comparison side: the enum case name when it is
        /// a literal tag, the raw expression (mask stripped for a seeded enum arg)
        /// otherwise.
        func comparisonOperand(_ value: AbstractValue, enumType: String?, depth: Int) -> String {
            if let cased = enumCaseOperand(value, enumType: enumType) { return cased }
            // A seeded enum arg wrapped in `& 0xFF` is just the arg — the mask is
            // the tag extraction, redundant once we know it is an enum.
            if enumArgumentType(of: value) != nil,
               case .binary(.bitAnd, let inner, _) = value {
                return renderValue(inner, depth: depth + 1)
            }
            return renderValue(value, depth: depth + 1)
        }

        /// The inverse comparison operator, or nil when `op` isn't a comparison —
        /// which doubles as the "is this a comparison?" gate (so an arithmetic
        /// `enumArg + 1` never routes through the enum-naming path).
        func invertedComparison(_ op: AbstractBinaryOperator) -> AbstractBinaryOperator? {
            switch op {
            case .equal: return .notEqual
            case .notEqual: return .equal
            case .less: return .greaterEqual
            case .lessEqual: return .greater
            case .greater: return .lessEqual
            case .greaterEqual: return .less
            case .unsignedLess: return .unsignedGreaterEqual
            case .unsignedLessEqual: return .unsignedGreater
            case .unsignedGreater: return .unsignedLessEqual
            case .unsignedGreaterEqual: return .unsignedLess
            default: return nil
            }
        }

        /// The mirrored comparison — `a op b` ⇔ `b mirror(op) a` — for putting a
        /// constant operand on the right (`1 == arg0` → `arg0 == 1`, `0 < arg0` →
        /// `arg0 > 0`), which reads like the Swift source rather than the lowered
        /// `subs`/`cbz` form. Nil for a non-comparison (never reordered).
        func mirroredComparison(_ op: AbstractBinaryOperator) -> AbstractBinaryOperator? {
            switch op {
            case .equal: return .equal
            case .notEqual: return .notEqual
            case .less: return .greater
            case .lessEqual: return .greaterEqual
            case .greater: return .less
            case .greaterEqual: return .lessEqual
            case .unsignedLess: return .unsignedGreater
            case .unsignedLessEqual: return .unsignedGreaterEqual
            case .unsignedGreater: return .unsignedLess
            case .unsignedGreaterEqual: return .unsignedLessEqual
            default: return nil
            }
        }

        /// Whether a value is provably a boolean (0/1) expression: a comparison,
        /// a `Bool` parameter, a synthesized `==`, the `& 1`/`^ 1` normalization
        /// of one, a `0`/`1` literal, or a select both of whose arms are boolean.
        /// This is the gate for reconstructing `&&`/`||` — folding requires the
        /// non-literal arm to be a proven boolean, so a genuine integer ternary
        /// carrying a `0`/`1` is never mislabelled a logical operator.
        func isBooleanValued(_ value: AbstractValue) -> Bool {
            switch value {
            case .binary(let op, let lhs, let rhs):
                if invertedComparison(op) != nil { return true }
                if op == .bitAnd, case .immediate(let mask) = rhs, mask & 1 == 1 {
                    return isBooleanValued(lhs)
                }
                if op == .bitXor, case .immediate(1) = rhs {
                    return isBooleanValued(lhs)
                }
                return false
            case .argument(let index):
                return boolArguments.contains(index)
            case .selfFieldValue(let offset):
                let type = fieldInfo(at: offset, bytes: 1)?.type
                return type == "B" || type == "Swift.Bool"
            case .immediate(let k):
                return k == 0 || k == 1
            case .callResult(let addr):
                guard !nonScalarObjCResultSites.contains(addr) else { return false }
                return calleeByAddress[addr].map {
                    $0.contains("__derived_enum_equals") || $0.contains("__derived_struct_equals")
                } ?? false
            case .select(_, let whenTrue, let whenFalse):
                return isBooleanValued(whenTrue) && isBooleanValued(whenFalse)
            default:
                return false
            }
        }

        /// Render a value known to be boolean, negated if asked — preferring
        /// `renderBoolean` (which inverts a comparison cleanly), else the plain
        /// render with a `!(…)` wrap for a needed negation. Nil if not boolean.
        func renderBooleanOperand(_ value: AbstractValue, negated: Bool, depth: Int) -> String? {
            guard isBooleanValued(value) else { return nil }
            if let b = renderBoolean(value, negated: negated, depth: depth) { return b }
            let plain = renderValue(value, depth: depth)
            return negated ? "!(\(plain))" : plain
        }

        /// A boolean-valued select is a short-circuit `&&`/`||`: `C ? T : F` where
        /// one arm is a `false`/`true` literal and the other is a proven boolean.
        /// `C?1:F`=`C||F`, `C?0:F`=`!C&&F`, `C?T:1`=`!C||T`, `C?T:0`=`C&&T`. Nil
        /// (declining to the raw ternary) when the shape isn't one: a genuine
        /// integer ternary, or both arms literal (bool-vs-int ambiguous).
        func renderLogicalSelect(
            _ condition: AbstractValue, _ whenTrue: AbstractValue, _ whenFalse: AbstractValue,
            negated: Bool, depth: Int
        ) -> String? {
            // `(cond ? 1 : 0)` materializes the boolean `cond`; `(cond ? 0 : 1)`
            // materializes `!cond`. A value identity (same 0/1) — safe regardless
            // of the result type — but only when `cond` is a proven boolean, so a
            // genuine integer ternary with 0/1 arms is left alone.
            if case .immediate(let t) = whenTrue, case .immediate(let f) = whenFalse,
               t <= 1, f <= 1, t != f, isBooleanValued(condition) {
                // t==1 ⇒ cond ; t==0 ⇒ !cond ; then compose the outer negation.
                return renderBooleanOperand(condition, negated: (t == 0) != negated, depth: depth + 1)
            }
            var condNegated: Bool
            var isOr: Bool
            let other: AbstractValue
            if case .immediate(1) = whenTrue { condNegated = false; isOr = true; other = whenFalse }
            else if case .immediate(0) = whenTrue { condNegated = true; isOr = false; other = whenFalse }
            else if case .immediate(1) = whenFalse { condNegated = true; isOr = true; other = whenTrue }
            else if case .immediate(0) = whenFalse { condNegated = false; isOr = false; other = whenTrue }
            else { return nil }
            // The other arm must be a real (non-literal) proven boolean — the
            // proof that this select is boolean-valued, not an integer ternary.
            if case .immediate = other { return nil }
            guard isBooleanValued(other) else { return nil }
            // An outer negation distributes by De Morgan: !(a && b) = !a || !b.
            var otherNegated = false
            if negated { condNegated.toggle(); otherNegated = true; isOr.toggle() }
            guard let c = renderBooleanOperand(condition, negated: condNegated, depth: depth + 1),
                  let o = renderBooleanOperand(other, negated: otherNegated, depth: depth + 1)
            else { return nil }
            return "(\(c) \(isOr ? "||" : "&&") \(o))"
        }

        /// The exposed-unsigned operator notation for a comparison we cannot prove
        /// a signed Swift meaning for — a distinct marker so the reader sees it is
        /// an unsigned machine comparison, never a fabricated signed `<`.
        func unsignedSymbol(_ op: AbstractBinaryOperator) -> String {
            switch op {
            case .unsignedLess: return "<\u{1D41}"          // <ᵁ
            case .unsignedLessEqual: return "<=\u{1D41}"
            case .unsignedGreater: return ">\u{1D41}"
            case .unsignedGreaterEqual: return ">=\u{1D41}"
            default: return op.symbol
            }
        }

        /// Render an unsigned machine comparison (ARM64 cc LO/HS/HI/LS) per the
        /// operand's recovered type — the U1 fix. Three outcomes, never a bare
        /// signed comparison:
        ///  · proven `UInt` operand → a plain `<` (correct for unsigned);
        ///  · proven signed operand compared `<`/`<=` against a non-negative
        ///    constant `N` → the proven range idiom `(0 <= x) && (x < N)`
        ///    (`x <ᵤ N ⇔ 0<=x && x<N` for `N < 2^63`);
        ///  · otherwise → the exposed unsigned operation `x <ᵁ y`.
        func renderUnsignedComparison(
            _ op: AbstractBinaryOperator, _ lhs: AbstractValue, _ rhs: AbstractValue,
            negated: Bool, depth: Int
        ) -> String {
            let effectiveOp = negated ? invertedComparison(op)! : op
            // Normalize to (variable side, constant?) with the variable on the left.
            let varSide: AbstractValue, other: AbstractValue, viewOp: AbstractBinaryOperator
            var constant: UInt64?
            if case .immediate(let n) = rhs {
                varSide = lhs; other = rhs; viewOp = effectiveOp; constant = n
            } else if case .immediate(let n) = lhs, let mirror = mirroredComparison(effectiveOp) {
                varSide = rhs; other = lhs; viewOp = mirror; constant = n
            } else {
                varSide = lhs; other = rhs; viewOp = effectiveOp
            }
            let varType = TypeInference.typeOf(varSide, arguments: argumentTypes)
            let x = comparisonOperand(varSide, enumType: nil, depth: depth)

            // Proven unsigned (UInt): the unsigned compare IS a plain Swift `<`.
            if varType.isUnsignedInteger {
                return "(\(x) \(viewOp.signedForm.symbol) "
                    + "\(comparisonOperand(other, enumType: nil, depth: depth)))"
            }
            // Proven signed + non-negative constant + `<`/`<=`: the range idiom.
            if varType.isSignedInteger, let n = constant, n <= UInt64(Int64.max),
               viewOp == .unsignedLess || viewOp == .unsignedLessEqual {
                let cmp = viewOp == .unsignedLess ? "<" : "<="
                return "((0 <= \(x)) && (\(x) \(cmp) \(Self.renderImmediate(n))))"
            }
            // Signedness unknown / unprovable shape: expose the unsigned operation.
            return "(\(x) \(unsignedSymbol(viewOp)) "
                + "\(comparisonOperand(other, enumType: nil, depth: depth)))"
        }

        /// Recognizes enum equality (`c == .case` / `!= .case`) and the boolean
        /// noise around it — the redundant `& 1` normalization mask and the
        /// `^ 1` logical-NOT the compiler emits for `!=`. Returns nil (declining
        /// to the raw form) for anything that isn't a boolean expression it can
        /// improve, so ordinary comparisons render through the normal path.
        func renderBoolean(_ value: AbstractValue, negated: Bool, depth: Int) -> String? {
            switch value {
            case .select(let condition, let whenTrue, let whenFalse):
                // A short-circuit `&&`/`||`.
                return renderLogicalSelect(condition, whenTrue, whenFalse, negated: negated, depth: depth)
            case .argument(let index) where boolArguments.contains(index):
                // A Bool parameter is a boolean value (0/1); `!b` and truthiness
                // tests fold against it, and its raw form is just `arg`.
                return negated ? "!arg\(index)" : "arg\(index)"
            case .binary(.bitAnd, let lhs, .immediate(let mask))
                where mask & 1 == 1 && isBooleanValued(lhs):
                // Word normalization is redundant only for a proven 0/1 value.
                return renderBoolean(lhs, negated: negated, depth: depth)
            case .binary(.bitXor, let lhs, .immediate(1)):
                // `x ^ 1` is logical NOT of a boolean x.
                return renderBoolean(lhs, negated: !negated, depth: depth)
            case .binary(let op, let lhs, let rhs):
                // Only comparisons are boolean; `invertedComparison` returning
                // non-nil is the gate (so `enumArg + 1` never names `1` a case).
                guard invertedComparison(op) != nil else { return nil }
                // An unsigned machine comparison never renders as a bare signed
                // `<` — its Swift meaning depends on the operand's recovered type.
                if op.isUnsignedComparison {
                    return renderUnsignedComparison(op, lhs, rhs, negated: negated, depth: depth)
                }
                // A single-register (reference) optional compared to 0 is a nil
                // check: `r != 0` reads `r != nil`. Only when the operand's
                // recovered type is `.optional`, so an integer `!= 0` is untouched.
                if op == .equal || op == .notEqual {
                    for (opt, zero) in [(lhs, rhs), (rhs, lhs)] {
                        guard case .immediate(0) = zero,
                              TypeInference.typeOf(opt, arguments: argumentTypes).category == .optional
                        else { continue }
                        let effectiveOp = negated ? invertedComparison(op)! : op
                        return "(\(renderValue(opt, depth: depth + 1)) \(effectiveOp.symbol) nil)"
                    }
                }
                // Boolean falsity/truth test: `(bool == 0)` = !bool, `(bool != 0)`
                // = bool, `(bool == 1)` = bool, `(bool != 1)` = !bool — but only
                // when the other operand is itself a recognized boolean, so a
                // genuine zero-test on an integer (`(arg0 & 1) == 0`) is left
                // alone. This peels the double-negation the compiler emits for
                // `if x == .case { … }` (lowered as `(x == .case) == 0 ? … : …`).
                if op == .equal || op == .notEqual {
                    for (boolSide, litSide) in [(lhs, rhs), (rhs, lhs)] {
                        guard case .immediate(let lit) = litSide, lit == 0 || lit == 1
                        else { continue }
                        let negateFold = (op == .equal) == (lit == 0)
                        if let folded = renderBoolean(
                            boolSide, negated: negated != negateFold, depth: depth
                        ) { return folded }
                    }
                }
                let effectiveOp = negated ? invertedComparison(op)! : op
                // Only intervene when there's something to improve: an enum to
                // name (the immediate side is cased using the arg side's type),
                // or a pending negation. Same type to both — only the immediate
                // operand names; the arg operand isn't an immediate so it renders.
                let enumType = enumArgumentType(of: lhs) ?? enumArgumentType(of: rhs)
                guard enumType != nil || negated else { return nil }
                // For a non-enum comparison, put a lone constant operand on the
                // right (source order) just as the plain-render path does; an
                // enum comparison instead positions the tag via the case naming.
                if enumType == nil, case .immediate = lhs, case .immediate = rhs {
                    // const vs const — no reordering
                } else if enumType == nil, case .immediate = lhs,
                          let mirror = mirroredComparison(effectiveOp) {
                    return "(\(comparisonOperand(rhs, enumType: nil, depth: depth))"
                        + " \(mirror.symbol) \(comparisonOperand(lhs, enumType: nil, depth: depth)))"
                }
                let l = comparisonOperand(lhs, enumType: enumType, depth: depth)
                let r = comparisonOperand(rhs, enumType: enumType, depth: depth)
                return "(\(l) \(effectiveOp.symbol) \(r))"
            case .callResult(let addr):
                // `Enum.__derived_enum_equals(a, b)` is the synthesized `==`.
                guard !nonScalarObjCResultSites.contains(addr), let callee = calleeByAddress[addr],
                      callee.contains("__derived_enum_equals"),
                      let args = argumentsByAddress[addr], args.count == 2
                else { return nil }
                let enumType = Self.derivedEnumEqualsType(callee)
                let op = negated ? "!=" : "=="
                let l = comparisonOperand(args[0], enumType: enumType, depth: depth)
                let r = comparisonOperand(args[1], enumType: enumType, depth: depth)
                return "(\(l) \(op) \(r))"
            default:
                return nil
            }
        }

        /// The float width (64 or 32) an expression is anchored to — the signal
        /// that a bare `.immediate` beside it is an IEEE bit pattern, not an
        /// integer. Only a float ARGUMENT, a conversion to float, or a call whose
        /// callee's signature returns a float anchors it: a bare immediate is
        /// exactly the ambiguous case being resolved, so it is never a base
        /// case, and an integer body never matches. A conversion to integer, a
        /// float's bits read as an integer (`fmov x8, d0`), or a bit-level
        /// operator ends the float context below it.
        func floatWidth(_ value: AbstractValue) -> Int? {
            switch value {
            case .argument(let index):
                guard let floatInfo, floatInfo.indices.contains(index) else { return nil }
                return floatInfo.isDouble ? 64 : 32
            case .callResult(let site):
                // -Onone calls `Double.init(_:)` where -O emits `scvtf`.
                switch calleeByAddress[site].flatMap(Self.swiftReturnTypeName(ofDemangled:)) {
                case "Swift.Double"?, "Swift.Float64"?, "Swift.CGFloat"?, "CoreGraphics.CGFloat"?: return 64
                case "Swift.Float"?, "Swift.Float32"?: return 32
                default: return nil
                }
            case .binary(.bitAnd, _, _), .binary(.bitOr, _, _), .binary(.bitXor, _, _),
                 .binary(.shiftLeft, _, _), .binary(.shiftRight, _, _), .binary(.arithmeticShiftRight, _, _):
                // A bit-level operator's result is an integer, whatever it read:
                // `str d0, [sp]; ldrb w8, [sp]; cmp x8, #7` is `(arg0 & 255)`,
                // and through it the 7 rendered `3.5e-323`.
                return nil
            case .binary(_, let lhs, let rhs):
                return floatWidth(lhs) ?? floatWidth(rhs)
            case .unary(.bitwiseNot, _), .unary(.byteSwap, _), .unary(.leadingZeros, _),
                 .unary(.leadingSignBits, _), .unary(.bitReverse, _):
                return nil
            case .unary(.toFloat(let bits), _), .unary(.unsignedToFloat(let bits), _),
                 .unary(.floatConstant(let bits), _):
                return bits
            case .unary(.toInteger, _), .unary(.bitPattern, _):
                return nil
            case .unary(_, let operand):
                return floatWidth(operand)
            default:
                return nil
            }
        }

        func renderValue(_ value: AbstractValue, depth: Int) -> String {
            // A whole aggregate is not the scalar word read from the send.
            // Check before name-based idioms too: an ObjC selector may contain
            // a Swift helper's spelling without having its scalar result.
            if case .callResult(let site) = value, nonScalarObjCResultSites.contains(site), site != definingSite {
                return unknownRenderedValue()
            }
            if depth < 8, case .binary(.bitAnd, let inner, .immediate(let mask)) = value,
               mask & 1 == 1, isBooleanValued(inner) {
                return renderValue(inner, depth: depth + 1)
            }
            if depth < 8, let boolean = renderBoolean(value, negated: false, depth: depth) {
                return boolean
            }
            switch value {
            case .genericMetadata(let name):
                return "type metadata for \(name)"
            case .unknown, .callResultHigh, .loadedThrough, .loadedFrom, .selfIsaSnapshot, .genericWitnessTable,
                 .existentialWitnessTable:
                // A String result's second word alone is no source value, nor
                // is a word read through a loaded pointer (a call through one
                // is named by its target, `annotateIndirectControlFlowTargets`).
                return unknownRenderedValue()
            case .binary(.subtract, let lhs, _) where ValueTracer.containsFrame(lhs) && Self.sizeIsUnknown(value):
                // A dynamic stack allocation of an unknown size, `sub x8, sp,
                // x8; mov sp, x8` with x8 a value-witness size: the tracer
                // keeps it to bound what the buffer reaches, but `local_120
                // - ((? + 15) & -16)` names nothing. A size it knows
                // (`local_30 - ((arg0 + 1) << 4)`) still renders.
                return unknownRenderedValue()
            case .immediate(let v):
                return Self.renderImmediate(v)
            case .argument(let index):
                return "arg\(index)"
            case .local(let id):
                return Self.inductionVariableName(id)
            case .awaitResult(let ordinal):
                return Self.awaitResultName(ordinal)
            case .asyncContext, .asyncCalleeContext, .asyncResumeParent, .asyncContextSlot:
                // Sanitised to `.unknown` before rendering; plumbing, not a value.
                return unknownRenderedValue()
            case .address(let a):
                return resolver.name(at: a) ?? objcIndex?.classObjectNames[a] ?? "0x" + String(a, radix: 16)
            case .loaded(let a):
                // Sanitised above, so a surviving `.loaded` always has a name.
                return resolver.loadedName(at: a) ?? unknownRenderedValue()
            case .frame(let offset):
                // A frame-relative address: a local's address being passed
                // (inout/indirect). Named by frame offset, the way a disassembler
                // names stack slots.
                guard offset != 0 else { return "sp" }
                let magnitude = String(abs(offset), radix: 16)
                return offset < 0 ? "local_\(magnitude)" : "frame_\(magnitude)"
            case .selfPointer:
                return "self"
            case .selfField(let offset):
                // `&self.breed`, when the field is nameable; otherwise the raw
                // offset, which is still true.
                guard let name = fieldName(at: offset, bytes: 0) else {
                    return "&self+0x\(String(offset, radix: 16))"
                }
                return "&\(fieldPath(name))"
            case .selfFieldValue(offset: 0) where selfEnumType != nil:
                // The tag of a no-payload enum is the value itself.
                return "self"
            case .selfFieldValue(let offset):
                // Part of a field is not the field: a four-byte read at
                // `fCurPos + 80` rendered `self->fCurPos`. Every such value
                // starts at a load of this offset in this function, so when
                // those loads agree on a width it is the range read; when
                // they do not, the start alone is shown.
                if let fieldMap {
                    let widths = selfFieldReadWidths[offset] ?? []
                    if widths.count == 1, let width = widths.first,
                       case .success(.part(let name, let partType, let subOffset, let bytes)) =
                        fieldMap.lookup(offset: offset, bytes: width) {
                        return fieldPath(memberPath(name, type: partType, subOffset: subOffset, bytes: bytes))
                    }
                    if widths.count != 1,
                       case .success(.part(let name, _, let subOffset, _)) = fieldMap.lookup(offset: offset, bytes: 1),
                       subOffset > 0 {
                        return fieldPath("\(name)[\(subOffset)...]")
                    }
                }
                guard let name = fieldName(at: offset, bytes: 1) else {
                    return "self[0x\(String(offset, radix: 16))]"
                }
                return fieldPath(name)
            case .selfVTableMethod(let offset):
                // A bare method pointer (rarely rendered on its own — the call it
                // feeds is named at the dispatch site). Name it when resolvable.
                return resolveVTableMethod(offset).map { "\($0)" } ?? unknownRenderedValue()
            case .argumentField(let argument, let offset):
                return argumentFieldName(argument: argument, offset: offset)
            case .arrayLiteral(let site, let count):
                return renderArrayLiteral(site: site, count: count, depth: depth)
            case .indirectResultPointer:
                // The caller-owned buffer this function returns into.
                return "&result"
            case .indirectResultField(let offset):
                if let layout = returnLayout,
                   let field = layout.fields.first(where: { $0.offset == offset }) {
                    return "&result.\(field.name)"
                }
                return "&result+0x\(String(offset, radix: 16))"
            case .indirectCallResultWord(let site, let offset):
                // A word of a callee's indirect result, read back from the frame
                // slot it was returned into: `r0.field` (the call bound once at
                // its site) when the callee's result type is laid out here, else
                // the raw offset.
                guard depth < 6 else { return unknownRenderedValue() }
                let call = boundResultSites[site] ?? renderValue(.callResult(site), depth: depth + 1)
                if let callee = calleeByAddress[site],
                   let type = Self.swiftReturnTypeName(ofDemangled: callee),
                   let layout = Self.completeValueLayout(of: type, fieldMaps: typeFieldMaps, classTypeIndex: classTypeIndex),
                   case .success(let hit) = layout.lookup(offset: offset, bytes: 8) {
                    switch hit {
                    case .whole(let name, _): return "\(call).\(name)"
                    case .part(let name, _, _, _): return "\(call).\(name)"
                    case .spans: break
                    }
                }
                return "\(call)[0x\(String(offset, radix: 16))]"
            case .select(let condition, let whenTrue, let whenFalse):
                guard depth < 8 else { return unknownRenderedValue() }
                let c = renderValue(condition, depth: depth + 1)
                let t = renderValue(whenTrue, depth: depth + 1)
                let f = renderValue(whenFalse, depth: depth + 1)
                return "(\(c) ? \(t) : \(f))"
            case .binary(let op, let lhs, let rhs):
                guard depth < 8 else { return unknownRenderedValue() }
                // A String object word: the literal sits 32 bytes past the
                // address. The address itself is never named; what is there is
                // some other string.
                if let address = Self.largeStringObjectAddress(value) {
                    return resolver.swiftLargeStringLiteral(objectAddress: address)
                        ?? "(0x\(String(address, radix: 16)) | 0x8000000000000000)"
                }
                // A single-register optional compared against 0 is a nil check:
                // `r != 0` reads `r != nil`. Only when the other operand's
                // recovered type is `.optional` (a reference optional we seeded),
                // so an ordinary integer `!= 0` is untouched.
                if op == .equal || op == .notEqual {
                    for (opt, zero) in [(lhs, rhs), (rhs, lhs)] {
                        guard case .immediate(0) = zero,
                              TypeInference.typeOf(opt, arguments: argumentTypes).category == .optional
                        else { continue }
                        return "(\(renderValue(opt, depth: depth + 1)) \(op.symbol) nil)"
                    }
                }
                // In a float-valued binary, a bare immediate operand is an IEEE
                // bit pattern — render it as its decimal per the function's
                // precision, not as a 16-digit integer. Not for a bit-level
                // operator: it works on a value reinterpreted as an integer
                // (`fmov x8, d0; lsr x8, x8, #52`), and its literals are shift
                // counts and masks. As floats they rendered `(arg0 >> 2.57e-322)`
                // for `>> 52`.
                let bitLevel: [AbstractBinaryOperator] = [
                    .bitAnd, .bitOr, .bitXor, .shiftLeft, .shiftRight, .arithmeticShiftRight,
                ]
                let floatType: String? = switch bitLevel.contains(op) ? nil : floatWidth(lhs) ?? floatWidth(rhs) {
                case 64?: "Swift.Double"
                case 32?: "Swift.Float"
                default: nil
                }
                func operand(_ value: AbstractValue) -> String {
                    if let floatType, case .immediate(let bits) = value,
                       let decimal = Self.renderTypedConstant(bits: bits, type: floatType) {
                        return decimal
                    }
                    // A signed order reads its constant as a signed number: a
                    // 32-bit compare against -100000 sign-extends it to
                    // 0xfffffffffffe7960, which is that value.
                    if [.less, .lessEqual, .greater, .greaterEqual].contains(op), case .immediate(let bits) = value,
                       Int64(bitPattern: bits) < 0, Int64(bitPattern: bits) >= Int64(Int32.min) {
                        return String(Int64(bitPattern: bits))
                    }
                    return renderValue(value, depth: depth + 1)
                }
                // `0 - x` is unary negation — the shape the compiler emits for a
                // `-x` with no dedicated negate. (`x - 0` never occurs; the tracer
                // folds the identity.)
                if op == .subtract, case .immediate(0) = lhs {
                    return "-\(operand(rhs))"
                }
                // `udiv`: a plain `/` or `%` only when the dividend is a proven
                // UInt; otherwise the U1 marker, never the signed operator it
                // disagrees with at every negative input.
                if op == .unsignedDivide || op == .unsignedRemainder {
                    let proven = TypeInference.typeOf(lhs, arguments: argumentTypes).isUnsignedInteger
                    let symbol = proven ? op.symbol : op.symbol + "\u{1D41}"
                    return "(\(operand(lhs)) \(symbol) \(operand(rhs)))"
                }
                // Normalize `const op var` to `var mirror(op) const` so a
                // comparison reads like source; only when the right side isn't
                // itself a constant (so `const op const` is left as-is).
                if case .immediate = lhs, case .immediate = rhs {
                    // both constant — no reordering
                } else if case .immediate = lhs, let mirror = mirroredComparison(op) {
                    return "(\(operand(rhs)) \(mirror.symbol) \(operand(lhs)))"
                }
                return "(\(operand(lhs)) \(op.symbol) \(operand(rhs)))"
            case .unary(let op, let operand):
                guard depth < 8 else { return unknownRenderedValue() }
                let inner = renderValue(operand, depth: depth + 1)
                switch op {
                case .negate: return "-\(inner)"
                case .bitwiseNot: return "~\(inner)"
                case .byteSwap(let bits): return "byteSwap\(bits)(\(inner))"
                case .leadingZeros(let bits): return "leadingZeros\(bits)(\(inner))"
                case .leadingSignBits(let bits): return "leadingSignBits\(bits)(\(inner))"
                case .bitReverse(let bits): return "bitReverse\(bits)(\(inner))"
                case .squareRoot: return "sqrt(\(inner))"
                case .absoluteValue: return "abs(\(inner))"
                case .toFloat(let bits):
                    return "\(bits == 64 ? "Double" : bits == 32 ? "Float" : "Float\(bits)")(\(inner))"
                case .unsignedToFloat(let bits):
                    // `Double(x)` converts a UInt as unsigned, and a value whose
                    // bit 63 is clear the same either way; anything else is
                    // spelled as its bits read unsigned.
                    let type = bits == 64 ? "Double" : bits == 32 ? "Float" : "Float\(bits)"
                    let clear: Bool = switch operand {
                    case .binary(.bitAnd, _, .immediate(let mask)), .immediate(let mask): mask <= UInt64(Int64.max)
                    default: TypeInference.typeOf(operand, arguments: argumentTypes).isUnsignedInteger
                    }
                    return clear ? "\(type)(\(inner))" : "\(type)(UInt(bitPattern: \(inner)))"
                case .toInteger(let signed, let bits):
                    return "\(signed ? "Int" : "UInt")\(bits == 64 ? "" : String(bits))(\(inner))"
                case .bitPattern(let bits):
                    // A proven float of this width reads `a.bitPattern`; a
                    // value not known to be a float is its own bits. A float
                    // of another or an unknown width read whole is neither.
                    let type = TypeInference.typeOf(operand, arguments: argumentTypes)
                    if let width = floatWidth(operand) ?? (type.category == .floatingPoint ? type.width ?? 0 : nil) {
                        return width == bits ? "\(inner).bitPattern" : unknownRenderedValue()
                    }
                    return inner
                case .floatFromBits(let bits):
                    // The tracer folds a float's own bits back to it. A field
                    // declared as this float, copied through a general register
                    // (-Onone `ldr x8, [x20, #0x10]; str x8, [sp]; ldr d1, [sp]`),
                    // is that float too. What is left is an integer's bits.
                    if case .selfFieldValue(let offset) = operand,
                       fieldInfo(at: offset, bytes: bits / 8)?.type == (bits == 64 ? "Sd" : "Sf") {
                        return inner
                    }
                    return "\(bits == 64 ? "Double" : "Float")(bitPattern: \(inner))"
                case .floatConstant(let bits):
                    guard case .immediate(let pattern) = operand else { return unknownRenderedValue() }
                    switch bits {
                    case 64: return String(Double(bitPattern: pattern))
                    case 32: return String(Float(bitPattern: UInt32(truncatingIfNeeded: pattern)))
                    default: return String(Float(Float16(bitPattern: UInt16(truncatingIfNeeded: pattern))))
                    }
                }
            case .aggregate(let values):
                // A multi-word result's two words together: the call.
                if values.count == 2, case .callResult(let site) = values[0], values[1] == .callResultHigh(site),
                   multiWordResultSites.contains(site) {
                    let saved = wholeResultSite
                    wholeResultSite = site
                    defer { wholeResultSite = saved }
                    return renderValue(values[0], depth: depth)
                }
                // One lane is a scalar a call preserved the low half of
                // (`callPreservedVectorValue`); its high lane is unknown.
                let lanes = values.count == 1 ? values + [.unknown] : values
                return "(" + lanes.map { renderValue($0, depth: depth + 1) }.joined(separator: ", ") + ")"
            case .callResult(let addr):
                // x0 after a call whose result spans registers is one part of
                // it: `mkPair(x).a + 2` read `(mkPair(x) + 2)`.
                if multiWordResultSites.contains(addr), addr != definingSite, addr != wholeResultSite {
                    return unknownRenderedValue()
                }
                // A call bound to a name for its field reads is that name
                // everywhere, so it is never spelled out a second time.
                if let name = boundResultSites[addr], addr != definingSite { return name }
                let inner = argumentsByAddress[addr] ?? []
                func unresolved() -> String {
                    if trackReturnRendering { unknownRenderCount += 1 }
                    return "/* unresolved call @ 0x\(String(addr, radix: 16)) */ ?"
                }
                // Deeply nested message chains (`[[[[self a] b] c] d]`) are common
                // in framework code; a shallow cap turns the tail into `unresolved`.
                // callResult references cannot cycle — a call's arguments are fully
                // computed before it runs — so this bound only limits line length,
                // never termination. Kept below the depth-8 expression cap.
                guard depth < 6, let callee = calleeByAddress[addr] else { return unresolved() }
                // The retain/autorelease family returns its argument: unwrap it.
                // With nothing tracked at the call the argument is unknown, and
                // so is what it returns; the call itself is resolved, so it is
                // no `unresolved call`.
                if !unprovenARCSites.contains(addr), DisassembledFunction.returnsItsArgument(callee) {
                    return inner.first.map { renderValue($0, depth: depth + 1) } ?? unknownRenderedValue()
                }
                if DisassembledFunction.isUniquenessCheck(callee) {
                    let object = inner.first.map { renderValue($0, depth: depth + 1) } ?? unknownRenderedValue()
                    return "isKnownUniquelyReferenced(\(object))"
                }
                // The rest of the runtime bookkeeping returns nothing a source
                // value could be (`swift_release`, `swift_beginAccess` are void):
                // x0 after one is not a value to name.
                if isRuntimeNoise(callee, at: addr) { return unknownRenderedValue() }
                // The mangled-name metadata helper fetches the type its
                // second argument spells: `type metadata for MN.Box<Swift.Int>`,
                // not `__swift_instantiateConcreteTypeFromMangledNameV2(0x8008, 0xde8)`.
                if callee == Self.mangledNameMetadataHelperName, inner.count >= 2,
                   case .address(let pair) = sanitizeValue(inner[1]),
                   let type = MangledNamePair.typeName(at: pair, in: resolver.machO, fixups: resolver.chainedFixups) {
                    return "type metadata for \(type)"
                }
                // `_finalizeUninitializedArray(array)` IS the array — render its
                // argument, which carries the recovered elements.
                if callee.contains("_finalizeUninitializedArray"), let first = inner.first {
                    return renderValue(first, depth: depth + 1)
                }
                // Any other array-literal runtime call collapses to `[…]`.
                if let literal = DisassembledFunction.arrayLiteralPlaceholder(callee: callee) {
                    return literal
                }
                // A vtable dispatch to one of `self`'s own getters is the property
                // access it reads — `self.x` — not a method call with stale args.
                if let access = selfAccessors[callee], access.isGetter {
                    return "self.\(access.property)"
                }
                // Checked-cast / safe-category helpers return their operand
                // unchanged; unwrap to that operand so the cast doesn't bury the
                // value. The operand index is explicit per helper, never guessed.
                if let index = DisassembledFunction.castPassthroughIndex(of: callee),
                   index < inner.count {
                    return renderValue(inner[index], depth: depth + 1)
                }
                // `objc_alloc(cls)` is `[cls alloc]`, so the argument is the
                // receiver as-is.
                //
                // It is NOT re-attributed to whatever produced that class.
                // `objc_opt_class(x)` is `[x class]`, so
                // `objc_alloc(objc_opt_class(x))` is `[[x class] alloc]`, and
                // rendering it `[x alloc]` drops a real call. Measured, because
                // the lowering is the reverse of what it looks like:
                //
                //   [self alloc]        (self is a Class)    -> objc_alloc(self)
                //   [[self class] alloc] (self is an instance) -> objc_alloc(objc_opt_class(self))
                //
                // So the composed form is exactly the case where `[x alloc]` is
                // wrong — and in an instance method it is not even valid ObjC,
                // since `alloc` is a class method. Nesting renders the `class`
                // call on its own, which is both true and what the source said.
                if let idiom = objcRuntimeIdiom(callee: callee, arguments: inner, depth: depth) {
                    return idiom
                }
                let callValues = normalizedArguments(callee: callee, values: inner, at: addr)
                let rawArguments: [String] = renderArguments(callValues, depth: depth + 1, site: addr)
                // A dynamic cast reads its target type from the metadata argument
                // that the plumbing strip would remove, so match it on the raw
                // arguments first — this is what lets `return x as? T` render as a
                // cast rather than the raw `swift_dynamicCast…(…)` call.
                if let cast = DisassembledFunction.swiftCastIdiom(callee: callee, arguments: rawArguments) {
                    return cast
                }
                // Strip the implicit generic plumbing from the rendered arguments
                // here, where they are still a clean per-argument list — the
                // string-level fold can't, because a demangled closure/`throws`
                // type embeds unbalanced parentheses that defeat its parser.
                let arguments = DisassembledFunction.strippingGenericPlumbing(rawArguments)
                if let send = DisassembledFunction.MessageSend(callee: callee, arguments: arguments) {
                    return send.rendered
                }
                let parts = selfValueBySite[addr].map { ["self: \(renderValue($0, depth: depth + 1))"] } ?? []
                return "\(displayCallee(callee, at: addr))(\((parts + arguments).joined(separator: ", ")))"
            }
        }

        /// The literal a `String(_builtinStringLiteral:utf8CodeUnitCount:isASCII:)`
        /// call builds, read as exactly its byte count. Named as a C string,
        /// the pointer printed only printable ASCII and cut it after 48
        /// characters, so at -Onone `"\u{7}ring "` and `"café "` showed an
        /// address, and a 60-byte literal `"…charac…"`, which the
        /// interpolation fold then printed as the string.
        func builtinStringLiteral(_ values: [AbstractValue], site: UInt64) -> String? {
            guard values.count == 3, let callee = calleeByAddress[site],
                  callee.hasPrefix(Self.builtinStringLiteralInit),
                  case .address(let address) = values[0], case .immediate(let count) = values[1],
                  case .immediate(let isASCII) = values[2], isASCII <= 1, count < 1 << 32
            else { return nil }
            return resolver.swiftStringLiteral(at: address, count: Int(count), isASCII: isASCII == 1)
        }

        // Render an argument list, collapsing the two-register pairs that encode
        // a Swift small string into a single quoted literal.
        func renderArguments(_ values: [AbstractValue], depth: Int, site: UInt64? = nil) -> [String] {
            var parts = renderArgumentList(values, depth: depth, site: site)
            if let site, parts.count == values.count, let literal = builtinStringLiteral(values, site: site) {
                parts[0] = literal
            }
            return parts
        }

        func renderArgumentList(_ values: [AbstractValue], depth: Int, site: UInt64?) -> [String] {
            // A laid-out site: each slot is one parameter of a known type, so a
            // constant renders as that type and no pair is a small string.
            /// A large literal's two words, (count and flags, object), as one
            /// string when the count is the literal's length.
            func largeString(at index: Int) -> String? {
                guard index + 1 < values.count, case .immediate(let countAndFlags) = values[index],
                      let address = Self.largeStringObjectAddress(values[index + 1])
                else { return nil }
                return resolver.swiftLargeStringLiteral(
                    objectAddress: address, count: Int(countAndFlags & 0x0000_FFFF_FFFF_FFFF))
            }
            if let types = site.flatMap({ laidOutTypes[$0] }), types.count == values.count {
                var parts: [String] = []
                var index = 0
                while index < values.count {
                    // A String slot's two words, kept only when they spell a
                    // literal or are one String field's.
                    if case .aggregate(let words) = values[index], words.count == 2,
                       Self.twoWordStringTypes.contains(types[index]) {
                        parts.append(swiftStringLiteral(words[0], words[1])
                            ?? selfStringField(words[0], words[1])
                            ?? stringCallResult(words[0], words[1]).map { renderValue(.callResult($0), depth: depth + 1) }
                            ?? unknownRenderedValue())
                        index += 1
                        continue
                    }
                    // An Optional scalar's payload and tag: `nil`, or the payload
                    // as its own type.
                    if case .aggregate(let words) = values[index], words.count == 2,
                       let payload = Self.optionalScalarPayload(ofParameterType: types[index]) {
                        if words[1] == .immediate(1) {
                            parts.append("nil")
                        } else if case .immediate(let bits) = words[0],
                                  let constant = Self.renderTypedConstant(bits: bits, type: payload.type) {
                            parts.append(constant)
                        } else {
                            parts.append(renderValue(Self.floatingPointValue(words[0], type: payload.type), depth: depth))
                        }
                        index += 1
                        continue
                    }
                    if let literal = largeString(at: index) {
                        parts.append(literal)
                        index += 2
                        continue
                    }
                    if case .immediate(let bits) = values[index],
                       let constant = Self.renderTypedConstant(bits: bits, type: types[index]) {
                        parts.append(constant)
                    } else {
                        parts.append(renderValue(Self.floatingPointValue(values[index], type: types[index]), depth: depth))
                    }
                    index += 1
                }
                // A typed fixed part (a declared variadic's) is still followed
                // by variadic arguments no one counted.
                if let site, unprovenVariadicSites.contains(site) { parts.append("…") }
                return parts
            }
            var parts: [String] = []
            var index = 0
            while index < values.count {
                if let literal = largeString(at: index) {
                    parts.append(literal)
                    index += 2
                } else if index + 1 < values.count,
                   case .immediate(let lo) = values[index],
                   case .immediate(let hi) = values[index + 1],
                   let string = ValueTracer.decodeSmallString(lo: lo, hi: hi) {
                    parts.append("\"\(ReferenceResolver.escapedLiteralText(string))\"")
                    index += 2
                } else {
                    parts.append(renderValue(values[index], depth: depth))
                    index += 1
                }
            }
            if let site, unprovenVariadicSites.contains(site) { parts.append("…") }
            return parts
        }
        func renderArguments(_ values: [AbstractValue], depth: Int) -> String {
            renderArguments(values, depth: depth).joined(separator: ", ")
        }

        func callExpression(
            callee: String, values: [AbstractValue], depth: Int = 0, site: UInt64? = nil, selfText: String? = nil
        ) -> String {
            // Same rewrite as the nested path: a runtime helper that is an exact
            // lowering of a source send renders as that send, whether it is the
            // statement itself or an argument to one.
            if let idiom = objcRuntimeIdiom(callee: callee, arguments: values, depth: depth) {
                return idiom
            }
            let arguments: [String] = renderArguments(
                normalizedArguments(callee: callee, values: values, at: site), depth: depth, site: site
            )
            if let send = DisassembledFunction.MessageSend(callee: callee, arguments: arguments) {
                return send.rendered
            }
            // A value method's `self` words show on every path that renders
            // the call: the exits passed none, and the 9 in x2 vanished from
            // `return W.take(?)`. Only those words: an x20 `self` the tracer
            // records for a site stays on the paths that already showed it.
            let selfText = selfText ?? site.flatMap { valueSelfBySite[$0] }.map { renderValue($0, depth: depth + 1) }
            let parts = (selfText.map { ["self: \($0)"] } ?? []) + arguments
            return "\(site.map { displayCallee(callee, at: $0) } ?? DisassembledFunction.strippedCallee(callee))(\(parts.joined(separator: ", ")))"
        }

        func fieldWrite(
            _ access: SelfFieldAccess,
            field: (names: [String], type: String?)
        ) -> String {
            // A pair store writes a tuple of fields only when each register
            // fills one whole field: `stp x2, x3, [x0, #8]` over a 12-byte
            // `_e` and a 4-byte `_f` covers both exactly, yet x2 is only the
            // first 8 bytes of `_e`, and it rendered
            // `(self->_e, self->_f) = (arg0, arg1)`.
            if field.names.count > 1, let stored = access.storedValues, stored.count == field.names.count,
               let fieldMap, access.bytes % stored.count == 0,
               field.names.indices.allSatisfy({ index in
                   let width = access.bytes / stored.count
                   guard case .success(.whole(let name, _)) =
                           fieldMap.lookup(offset: access.offset + index * width, bytes: width)
                   else { return false }
                   return name == field.names[index]
               }) {
                let values = stored.map(sanitizeValue)
                if values.allSatisfy({ $0 != .unknown }) {
                    let paths = field.names.map(fieldPath).joined(separator: ", ")
                    let rendered = values.enumerated().map { index, value in
                        let width = access.bytes / values.count
                        if case .success(.whole(_, let type)) =
                            fieldMap.lookup(offset: access.offset + index * width, bytes: width) {
                            return renderValue(floatingFieldValue(value, mangledType: type) ?? value, depth: 0)
                        }
                        return unknownRenderedValue()
                    }.joined(separator: ", ")
                    return "(\(paths)) = (\(rendered))"
                }
            }
            let name = field.names.count == 1
                ? field.names[0] : "{\(field.names.joined(separator: ", "))}"
            let path = fieldPath(name)
            // A store into part of one field holds a piece of its value, and
            // one `stp` that fills a two-word field holds both words, so the
            // first word alone is not the field's value: `name = "a  b"`
            // (`stp x8, x9, [x20, #0x10]`) rendered `self.name = 0x62202061`.
            // A part is written to its byte range (`self.pair[0..<8] = x`); a
            // String's two words are shown only when they spell a literal.
            // A value this object's own fields held is shown as the range it
            // was read from: a struct copied in pieces reads
            // `self->fPrvPos[32..<48] = self->fCurPos[32..<48]`.
            func ownFieldRange(_ value: AbstractValue, bytes: Int) -> String? {
                guard case .selfFieldValue(let offset) = value, let fieldMap else { return nil }
                switch fieldMap.lookup(offset: offset, bytes: max(bytes, 1)) {
                case .success(.whole(let name, _)): return fieldPath(name)
                case .success(.part(let name, let partType, let subOffset, let bytes)):
                    return fieldPath(memberPath(name, type: partType, subOffset: subOffset, bytes: bytes))
                default: return nil
                }
            }
            if field.names.count == 1, let fieldMap {
                switch fieldMap.lookup(offset: access.offset, bytes: max(access.bytes, 1)) {
                case .success(.part(let partName, let partType, let subOffset, let bytes)):
                    let partPath = fieldPath(memberPath(partName, type: partType, subOffset: subOffset, bytes: bytes))
                    guard let rawValue = access.storedValue, sanitizeValue(rawValue) != .unknown
                    else { return "\(partPath) = …" }
                    let value = sanitizeValue(rawValue)
                    if let source = ownFieldRange(value, bytes: access.bytes) { return "\(partPath) = \(source)" }
                    guard access.bytes <= 8 else { return "\(partPath) = …" }
                    return "\(partPath) = \(renderValue(value, depth: 0))"
                case .success(.whole(_, let type)) where access.bytes > 8:
                    // An `stp` gives two words; one wide register (`str q0`) one value.
                    let words = (access.storedValues ?? access.storedValue.map { [$0] } ?? []).map(sanitizeValue)
                    // Every byte zeroed (`stp xzr, xzr`, or `str q0` after
                    // `movi v0.2d, #0`).
                    if !words.isEmpty, words.allSatisfy(Self.isAllZero),
                       !Self.twoWordStringMangledTypes.contains(type) {
                        return "\(path) = 0"
                    }
                    if Self.twoWordStringMangledTypes.contains(type), words.count == 2,
                       let literal = swiftStringLiteral(words[0], words[1]) {
                        return "\(path) = \(literal)"
                    }
                    // Both words read from consecutive words of one field.
                    if words.count == 2, case .selfFieldValue(let low) = words[0],
                       words[1] == .selfFieldValue(offset: low + 8),
                       let source = ownFieldRange(words[0], bytes: access.bytes) {
                        return "\(path) = \(source)"
                    }
                    if words.count == 1, let first = words.first,
                       let source = ownFieldRange(first, bytes: access.bytes) {
                        return "\(path) = \(source)"
                    }
                    return "\(path) = …"
                default:
                    break
                }
            }
            // A pair store over several fields that is no tuple of them holds
            // two values, and the first is not the span's: `stp x2, x9` over
            // `_c` and `_d`, x9 unknown, rendered `self->{_c, _d} = arg0`.
            // A store over several fields whose every byte is zero holds the
            // one value the whole span then holds: `movi v0.2d, #0; stur q0`
            // over four ints read `= (0, 0)`, the register's two words, and
            // a pair of them `= …`.
            if field.names.count > 1,
               let words = access.storedValues ?? access.storedValue.map({ [$0] }),
               !words.isEmpty, words.map(sanitizeValue).allSatisfy(Self.isAllZero) {
                return "\(path) = 0"
            }
            if field.names.count > 1, access.storedValues != nil { return "\(path) = …" }
            guard let rawValue = access.storedValue else { return "\(path) = …" }
            let value = sanitizeValue(rawValue)
            guard value != .unknown else { return "\(path) = …" }
            // A value this object's own fields held, forwarded through a
            // register from an earlier store, is as wide as this store: q0
            // forwarded from a 16-byte store into four ints read `self->_v`,
            // the 4-byte field at its offset.
            if case .selfFieldValue(let source) = value, let fieldMap {
                switch fieldMap.lookup(offset: source, bytes: max(access.bytes, 1)) {
                case .success(.whole(let name, _)): return "\(path) = \(fieldPath(name))"
                case .success(.part(let name, let partType, let subOffset, let bytes)):
                    return "\(path) = \(fieldPath(memberPath(name, type: partType, subOffset: subOffset, bytes: bytes)))"
                case .success(.spans(let names)):
                    return "\(path) = \(fieldPath("{\(names.joined(separator: ", "))}"))"
                case .failure:
                    return "\(path) = …"
                }
            }

            // The canonical compiler shape for `_count += delta` is load/add/
            // store. Preserve that source operator instead of spelling a noisy
            // self-assignment.
            if case .binary(let op, let lhs, let rhs) = value,
               case .selfFieldValue(let offset) = lhs, offset == access.offset,
               op == .add || op == .subtract {
                return "\(path) \(op == .add ? "+=" : "-=") \(renderValue(rhs, depth: 0))"
            }
            if objcFieldSyntax, field.type == "B", case .immediate(let raw) = value, raw <= 1 {
                return "\(path) = \(raw == 0 ? "NO" : "YES")"
            }
            let typed = field.type.flatMap { floatingFieldValue(value, mangledType: $0) } ?? value
            return "\(path) = \(renderValue(typed, depth: 0))"
        }

        /// A Swift function returning a struct of integer scalars of 9 to 16
        /// bytes, so in x0 and x1, whose two words at the `ret` are one whole
        /// field of self of that same type, returns that field:
        /// `FieldWrites.pairCopy` (`ldp x0, x1, [x20, #0x20]; ret`) is
        /// `return self.pair`. The field's type, resolved from its record,
        /// must be the return type, so a field of another two-word type is not
        /// claimed.
        func swiftTwoWordFieldReturn(at address: UInt64, type: String) -> String? {
            guard let returned = typeFieldMaps[type], Self.returnsInTwoIntegerRegisters(returned),
                  let low = analysis.exitValues[address].map(sanitizeValue),
                  let high = analysis.exitYieldValues[address].map(sanitizeValue),
                  case .selfFieldValue(let offset) = low, high == .selfFieldValue(offset: offset + 8),
                  let lookup = fieldMap?.lookup(offset: offset, bytes: 16),
                  case .success(.whole(let name, _)) = lookup,
                  fieldMap?.fieldTypeNames[name] == type
            else { return nil }
            return fieldPath(name)
        }

        /// A method that returns a struct of two words in x0 and x1, both
        /// words of one whole 16-byte field of self, returns that field:
        /// `ldp x8, x1, [x0, #0x30]; mov x0, x8; ret` in
        /// `-[TTLogicalScreen cursorPosition]` is `return
        /// self->_cursorPosition`. The return path otherwise proves x0 alone.
        func twoWordFieldReturn(at address: UInt64) -> String? {
            guard let encoding = function.objcMethod?.typeEncoding,
                  let type = ObjCArgumentABI.returnType(encoding: encoding),
                  case .composite(let size)? = ObjCArgumentABI.aggregate(type), size > 8,
                  let low = analysis.exitValues[address].map(sanitizeValue),
                  let high = analysis.exitYieldValues[address].map(sanitizeValue),
                  case .selfFieldValue(let offset) = low, high == .selfFieldValue(offset: offset + 8),
                  case .success(.whole(let name, _))? = fieldMap?.lookup(offset: offset, bytes: 16)
            else { return nil }
            return fieldPath(name)
        }

        /// A paired store that is no tuple of whole fields, as a tuple of what
        /// each register writes: `stp w3, w4, [x0, #0x10]` over the last four
        /// bytes of a 12-byte `_e` and all of `_f` named no field and was
        /// dropped; it is `(self->_e[8..<12], self->_f) = (…, arg1)`. Nil when
        /// the store is already a tuple of whole fields, or when a register's
        /// bytes name no field or part of one.
        func registerWrite(_ access: SelfFieldAccess) -> String? {
            // One 16-byte vector register is two eight-byte lanes, and a
            // store of it that starts inside one field and ends in the next
            // is written lane by lane the same way: `dup v0.2d, x2;
            // stur q0, [x0, #0x18]` over `_s.y` and `_t` printed nothing.
            let lanes: [AbstractValue]? = access.storedValues == nil && access.bytes == 16
                ? (access.storedValue.flatMap { value -> [AbstractValue]? in
                    if case .aggregate(let words) = value, words.count == 2 { return words }
                    return nil
                } ?? [.unknown, .unknown])
                : nil
            guard let stored = access.storedValues ?? lanes, stored.count == 2, access.bytes % 2 == 0, let fieldMap
            else { return nil }
            if let field = fieldInfo(at: access.offset, bytes: access.bytes),
               field.names.count == 1 || fieldWrite(access, field: field).hasPrefix("(") {
                return nil
            }
            let width = access.bytes / 2
            var targets: [String] = [], values: [String] = []
            for (index, stored) in stored.enumerated() {
                switch fieldMap.lookup(offset: access.offset + index * width, bytes: width) {
                case .success(.whole(let name, _)):
                    targets.append(fieldPath(name))
                case .success(.part(let name, let partType, let subOffset, let bytes)):
                    targets.append(fieldPath(memberPath(name, type: partType, subOffset: subOffset, bytes: bytes)))
                default:
                    return nil
                }
                // A value this object's own field held is named by the
                // register's width: x2 forwarded from an 8-byte store into the
                // 24-byte `_a` is `self->_a[0..<8]`, not `self->_a`.
                let value = sanitizeValue(stored)
                if case .selfFieldValue(let source) = value,
                   case .success(let hit) = fieldMap.lookup(offset: source, bytes: width) {
                    switch hit {
                    case .whole(let name, _):
                        values.append(fieldPath(name))
                        continue
                    case .part(let name, let partType, let subOffset, let bytes):
                        values.append(fieldPath(memberPath(name, type: partType, subOffset: subOffset, bytes: bytes)))
                        continue
                    case .spans:
                        break
                    }
                }
                values.append(value == .unknown ? "…" : renderValue(value, depth: 0))
            }
            return "(\(targets.joined(separator: ", "))) = (\(values.joined(separator: ", ")))"
        }

        /// Runtime helpers emitted as tail calls can express higher-level ivar
        /// operations more accurately than their low-level ABI argument list.
        func objcHelperStatement(callee: String, site: CallSite) -> String? {
            let args = site.arguments
            if callee.hasPrefix("objc_setProperty"), args.count >= 4,
               case .immediate(let rawOffset) = args[3],
               let offset = Int(exactly: rawOffset),
               let name = fieldName(at: offset, bytes: 1) {
                let value = renderValue(sanitizeValue(args[2]), depth: 0)
                let copied = callee.contains("copy") ? "[\(value) copy]" : value
                return "\(fieldPath(name)) = \(copied)"
            }
            if callee.hasPrefix("objc_storeStrong"), args.count >= 2,
               case .selfField(let offset) = args[0],
               case .immediate(0) = args[1],
               let name = fieldName(at: offset, bytes: 1) {
                return "\(fieldPath(name)) = nil"
            }
            return nil
        }

        let passthroughReturnHelpers = [
            "objc_autoreleaseReturnValue", "objc_retainAutoreleaseReturnValue",
            "objc_claimAutoreleasedReturnValue", "objc_retainAutoreleasedReturnValue",
        ]

        // The demangled result type, when it names a no-payload enum whose cases
        // this image publishes — so an immediate tag renders as `Type.case`.
        let returnTypeName: String? = Self.swiftReturnTypeName(of: function)

        func renderReturnValue(_ rawValue: AbstractValue, before address: UInt64) -> String {
            let initialUnknowns = unknownRenderCount
            defer {
                if trackReturnRendering { completeReturnRendering[address] = unknownRenderCount == initialUnknowns }
            }
            let value = sanitizeValue(rawValue)
            // An immediate returned from an enum-typed function is that enum's
            // case tag: name it (`return Color.green`) instead of printing the
            // raw discriminant. Declines — leaving the integer — for payload
            // enums, unknown/ambiguous enums, and out-of-range tags.
            if case .immediate(let tag) = value, let returnTypeName,
               tag <= UInt64(Int.max),
               let caseName = enumCaseIndex.caseName(ofEnum: returnTypeName, tag: Int(tag)) {
                return "\(returnTypeName).\(caseName)"
            }
            // A payload enum returned as a constant empty case: unlike a no-payload
            // enum, the discriminant is NOT this single register — x0 holds the
            // payload and the tag lives in x1 for a two-register direct return. The
            // tracer already captured x1 at the `ret` (as `exitYieldValues`), so
            // hand both to `PayloadEnumCaseIndex`, which names the case ONLY on an
            // exact byte-pattern match against the statically-resolved encoding and
            // declines otherwise — leaving the raw integer this method falls through
            // to. That decline is the important half: it is why a payload case, an
            // extra-inhabitant-encoded case, or an unknown enum never gets a name.
            if case .immediate(let x0) = value, let returnTypeName {
                let x1: UInt64? = {
                    guard case .immediate(let value)? = analysis.exitYieldValues[address].map(sanitizeValue)
                    else { return nil }
                    return value
                }()
                if let caseName = payloadEnumIndex.caseName(ofEnum: returnTypeName, x0: x0, x1: x1) {
                    return "\(returnTypeName).\(caseName)"
                }
            }
            // A constant returned from a Bool- or floating-point-typed function
            // reads per its type: `true`/`false`, or the float decimal instead of
            // the raw IEEE-754 bit pattern.
            if case .immediate(let bits) = value, let returnTypeName,
               let typed = Self.renderTypedConstant(bits: bits, type: returnTypeName) {
                return typed
            }
            // If this exact expression was just stored to a known ivar, return
            // the ivar's new value. This turns load/add/store/mov/ret into the
            // source-like `_count += delta; return _count` form.
            let matchingStore = analysis.selfFieldAccesses
                .filter { candidate, access in
                    candidate < address && access.isWrite
                        && access.storedValue.map(sanitizeValue) == value
                }
                .max(by: { $0.key < $1.key })?.value
            if let matchingStore,
               let name = fieldName(at: matchingStore.offset, bytes: matchingStore.bytes) {
                return fieldPath(name)
            }
            if let returnTypeName {
                return renderValue(Self.narrowedResult(Self.floatingPointValue(value, type: returnTypeName),
                                                      type: returnTypeName), depth: 0)
            }
            return renderValue(value, depth: 0)
        }

        // The return type's complete stored-property layout, when it is a struct
        // this image lays out in full: what an x8-indirect return is checked
        // against field by field.
        let returnLayout: FieldMap? = returnTypeName.flatMap {
            Self.completeValueLayout(of: $0, fieldMaps: typeFieldMaps, classTypeIndex: classTypeIndex)
        }

        func floatingFieldValue(_ value: AbstractValue, mangledType: String) -> AbstractValue? {
            guard case .select = value else { return nil }
            let code = objcFieldSyntax ? String(mangledType.drop(while: { "rnNoORVA".contains($0) })) : mangledType
            let type: String
            switch code {
            case "Sd", "d", "D": type = "Swift.Double"
            case "Sf", "f": type = "Swift.Float"
            case "s7Float16V": type = "Swift.Float16"
            default: return nil
            }
            return Self.floatingPointValue(value, type: type)
        }

        /// A stored field's value, read per the field's own type: a `Bool` or
        /// floating-point constant as its literal, anything else as the value.
        func renderFieldValue(_ value: AbstractValue, mangledType: String) -> String {
            let typeName: String? = switch mangledType {
            case "Sb": "Swift.Bool"
            case "Sd": "Swift.Double"
            case "Sf": "Swift.Float"
            default: nil
            }
            if case .immediate(let bits) = value, let typeName,
               let typed = Self.renderTypedConstant(bits: bits, type: typeName) {
                return typed
            }
            return renderValue(floatingFieldValue(value, mangledType: mangledType) ?? value, depth: 0)
        }

        /// The call whose indirect result the stores are, verbatim: every store is
        /// the word at its own offset of ONE call's result, in order, covering
        /// that result's whole size. The shape a `-Onone` body produces when it
        /// calls an initializer into a temporary and then copies the temporary
        /// into its own result buffer.
        func wholeCallResult(from stores: [Int: IndirectResultExit.Store]) -> UInt64? {
            var site: UInt64?
            for (offset, store) in stores {
                guard store.bytes == 8, case .indirectCallResultWord(let s, let wordOffset) = store.value,
                      wordOffset == offset, site == nil || site == s
                else { return nil }
                site = s
            }
            guard let site, case .indirect(let size?)? = calleeConventions[site],
                  stores.count == size / 8, stores.keys.allSatisfy({ $0 % 8 == 0 && $0 < size })
            else { return nil }
            return site
        }

        /// The rendered return of an x8-indirect function at this `ret`, with the
        /// values it embeds (so the calls they came from are consumed), or nil
        /// when nothing about the buffer is provable there.
        func indirectReturn(at address: UInt64) -> (rendered: String, consumedValues: [AbstractValue])? {
            guard let exit = analysis.exitIndirectResults[address], !exit.poisoned else { return nil }
            // The whole buffer is one callee's result: `return callee(args)`.
            let wholeSite: UInt64? = exit.whole != nil && exit.stores.isEmpty
                ? exit.whole : wholeCallResult(from: exit.stores)
            if let wholeSite {
                let value = AbstractValue.callResult(wholeSite)
                let rendered = renderValue(value, depth: 0)
                guard rendered != "?", !rendered.hasPrefix("/* unresolved") else { return nil }
                return (rendered, [value])
            }
            guard exit.whole == nil, let returnTypeName else { return nil }
            // A payload enum: the tag bytes name the case (exactly, or not at
            // all), and a payload case's words come from its declared type.
            if returnLayout == nil {
                var observed: [Int: (bytes: Int, immediate: UInt64?)] = [:]
                for (offset, store) in exit.stores {
                    let value = sanitizeValue(store.value)
                    if case .immediate(let bits) = value {
                        observed[offset] = (store.bytes, bits)
                    } else {
                        observed[offset] = (store.bytes, nil)
                    }
                }
                guard let enumCase = payloadEnumIndex.indirectCase(ofEnum: returnTypeName, stores: observed)
                else { return nil }
                if enumCase.payloadWordOffsets.isEmpty {
                    return ("\(returnTypeName).\(enumCase.name)", [])
                }
                let values = enumCase.payloadWordOffsets.compactMap { exit.stores[$0]?.value }.map(sanitizeValue)
                guard values.count == enumCase.payloadWordOffsets.count else { return nil }
                let rendered = values.map { renderValue($0, depth: 0) }
                guard rendered.contains(where: { $0 != "?" }) else { return nil }
                return ("\(returnTypeName).\(enumCase.name)(\(rendered.joined(separator: ", ")))", values)
            }
            guard let layout = returnLayout else { return nil }
            // Every store must land exactly on a field, and every field must be
            // stored: a partial set is declined, never padded.
            let fields = layout.fields
            for (offset, store) in exit.stores {
                guard fields.contains(where: { $0.offset == offset && $0.bytes == store.bytes }) else { return nil }
            }
            var parts: [String] = []
            var values: [AbstractValue] = []
            var known = 0
            for field in fields {
                guard let store = exit.stores[field.offset], store.bytes == field.bytes else { return nil }
                let value = sanitizeValue(store.value)
                let text = renderFieldValue(value, mangledType: field.typeMangledName)
                if text != "?" { known += 1 }
                parts.append("\(field.name): \(text)")
                values.append(value)
            }
            // Stores whose values are all unknown say nothing a bare `return ?`
            // does not; the field-wise form is kept for where it adds a value.
            guard known > 0 else { return nil }
            return ("\(returnTypeName)(\(parts.joined(separator: ", ")))", values)
        }

        /// The two words of the String a Swift function returns at this
        /// `ret`, x0 and x1. A String is never read from x0 alone.
        func swiftStringReturnWords(at address: UInt64) -> (low: AbstractValue, high: AbstractValue)? {
            guard returnTypeName == "Swift.String",
                  let low = analysis.exitValues[address].map(sanitizeValue),
                  // Alone, a String call's second word sanitizes to unknown;
                  // here it is read beside its first.
                  let high = analysis.exitYieldValues[address].map({ value in
                      if case .callResultHigh = value { return value }
                      return sanitizeValue(value)
                  })
            else { return nil }
            return (low, high)
        }

        /// The call whose whole String result a Swift function returns at
        /// this `ret`. A call whose result is some other two-word type (a
        /// struct holding a String) has the same bits, but is not the String.
        func swiftStringReturnCall(at address: UInt64) -> UInt64? {
            guard let (low, high) = swiftStringReturnWords(at: address),
                  let site = stringCallResult(low, high),
                  calleeByAddress[site].flatMap({ Self.swiftReturnTypeName(forDemangledName: $0) }) == "Swift.String"
            else { return nil }
            return site
        }

        /// Whether the body stores outside its own frame. A call needs no
        /// check: the tracer forgets a value read from memory across one.
        func writesMemory() -> Bool {
            function.instructions.contains { insn in
                (insn.controlFlow ?? .sequential) == .sequential && Self.isOrderingEffect(insn)
            }
        }

        /// The literal a String's two words spell, or the pick between two
        /// of them: x0 and x1 both selects on one condition, as a ternary
        /// lowers to a `csel` per word over the same flags. Each arm pairs
        /// the two words its own side selects. Selects on two conditions
        /// (two flag setters, or `ne` and `eq` of one) pick words that need
        /// not belong to one String, and are no pick. Two equal conditions
        /// that read memory are one condition only where nothing can write
        /// it: `self.flag != 0` before and after `*p = 1` spell the same
        /// and may differ.
        func swiftStringPick(_ low: AbstractValue, _ high: AbstractValue, depth: Int) -> String? {
            if let literal = swiftStringLiteral(low, high) { return literal }
            guard depth < 6,
                  case .select(let condition, let lowTrue, let lowFalse) = low,
                  case .select(condition, let highTrue, let highFalse) = high,
                  !Self.readsMemory(condition) || !writesMemory(),
                  let whenTrue = swiftStringPick(lowTrue, highTrue, depth: depth + 1),
                  let whenFalse = swiftStringPick(lowFalse, highFalse, depth: depth + 1)
            else { return nil }
            return "(\(renderValue(condition, depth: 0)) ? \(whenTrue) : \(whenFalse))"
        }

        /// The String a Swift function returns at this `ret`, read from both
        /// of its words: a literal they spell or a pick between literals,
        /// the whole result of a call that itself returns a String, or one
        /// String field of self. With the call it consumes, if any.
        func swiftStringReturn(at address: UInt64) -> (rendered: String, consumedSite: UInt64?)? {
            guard let (low, high) = swiftStringReturnWords(at: address) else { return nil }
            if let literal = swiftStringPick(low, high, depth: 0) { return (literal, nil) }
            if let site = swiftStringReturnCall(at: address) {
                let rendered = renderValue(.callResult(site), depth: 0)
                guard rendered != "?", !rendered.hasPrefix("/* unresolved") else { return nil }
                return (rendered, site)
            }
            if case .selfFieldValue(let offset) = low, high == .selfFieldValue(offset: offset + 8),
               case .success(.whole(let name, "SS"))? = fieldMap?.lookup(offset: offset, bytes: 16) {
                return (fieldPath(name), nil)
            }
            return nil
        }

        func collectCallResults(in value: AbstractValue, into consumed: inout Set<UInt64>) {
            switch value {
            case .callResult(let address) where multiWordResultSites.contains(address) || nonScalarObjCResultSites.contains(address):
                // One part of a multi-word result renders `?`, so the call
                // still needs its own statement.
                break
            case .aggregate(let words) where words.count == 2:
                if case .callResult(let site) = words[0], words[1] == .callResultHigh(site),
                   multiWordResultSites.contains(site) {
                    consumed.insert(site)
                } else {
                    for word in words { collectCallResults(in: word, into: &consumed) }
                }
            case .callResult(let address), .indirectCallResultWord(let address, _):
                consumed.insert(address)
            case .arrayLiteral(let site, _):
                // The `_allocateUninitializedArray` at `site` is folded into the
                // literal, so drop its standalone `[…]` statement.
                consumed.insert(site)
            case .binary(_, let lhs, let rhs):
                collectCallResults(in: lhs, into: &consumed)
                collectCallResults(in: rhs, into: &consumed)
            case .unary(_, let operand):
                collectCallResults(in: operand, into: &consumed)
            case .select(let condition, let whenTrue, let whenFalse):
                collectCallResults(in: condition, into: &consumed)
                collectCallResults(in: whenTrue, into: &consumed)
                collectCallResults(in: whenFalse, into: &consumed)
            case .aggregate(let values):
                for value in values { collectCallResults(in: value, into: &consumed) }
            default:
                break
            }
        }

        // The `ret`s of a throwing function that throw. Swift returns the error
        // in x21 and the caller tests it; a normal exit leaves x21 as it came in,
        // which the tracer never knows. So an exit throws only where x21 is
        // proven set: a non-zero constant (typed throws sets `w21 = 1`) or a
        // fresh `swift_allocError` box (untyped). A merged exit
        // (`csel x21, x21, x8, eq`) proves neither, and keeps its `return`.
        // Rendered as a return, a throw exit printed its x0 as the result: the
        // typed error's payload (`return 0` for `.bad`), or a dead call's.
        let throwsSignature = function.objcMethod == nil
            ? function.analysisName.flatMap(DisassembledFunction.splitSignature).map { signature in
                // A specialization that binds the thrown type to `Swift.Never`
                // cannot throw: its exits are plain returns.
                var signature = signature
                if signature.isThrowing && function.specializationBindsThrownTypeToNever {
                    signature.isThrowing = false
                    signature.thrownType = nil
                }
                return signature
            } : nil
        // An async throwing function returns through its context's
        // ResumeParent with the error in x20, zero for none: `swift_allocError`
        // then `mov x20, x0; br x0` throws, `mov x20, #0; br x1` returns. A
        // rethrow passes on the error an await-return funclet received in x20:
        // the exit is reached only through the non-zero edge of `cbz`/`cbnz
        // x20` with nothing writing x20 since. Both rendered as a bare
        // `return` (`if (x20 == 0) { return (awaited1 << 1) } else { return }`).
        let opaqueErrorProofTransfer = originalIndirectExitTransfers.contains { !asyncReturns.contains($0) }
        let asyncThrowExits: Set<UInt64> = {
            guard throwsSignature?.isThrowing == true, !asyncReturns.isEmpty else { return [] }
            var exits = Set<UInt64>()
            let blocks = cfg.basicBlocks(of: function, consumer: "async-throw-exits")
            let blockOf = Dictionary(blocks.flatMap { block in block.instructions.map { ($0.address, block) } },
                                     uniquingKeysWith: { a, _ in a })
            var predecessors: [UInt64: [BasicBlock]] = [:]
            for block in blocks { for successor in Set(block.successors) { predecessors[successor, default: []].append(block) } }
            // x20 is callee-saved: a call keeps it unless the callee's own body
            // proves otherwise (an outlined fragment, `calleeClobbers`).
            // Counting every call as a write turned a rethrow after a cleanup
            // `bl swift_release` into `return`, though the binary tests x20
            // right after such calls itself.
            func writesX20(_ insn: Instruction) -> Bool {
                if insn.controlFlow == .call {
                    return tracer.clobbers(atCall: insn).contains("x20")
                }
                return insn.detail?.writtenRegisterKeys.contains("x20") != false
            }
            /// Whether every path into `block` (up to `address`) leaves the
            /// non-zero edge of a test of x20 with x20 untouched since.
            func guardedNonZero(_ block: BasicBlock, before address: UInt64, depth: Int) -> Bool {
                guard depth < 8 else { return false }
                if block.instructions.contains(where: { $0.address < address && writesX20($0) }) { return false }
                guard let into = predecessors[block.startAddress], into.count == 1, let previous = into.first,
                      let test = previous.instructions.last, let detail = test.detail
                else { return false }
                if detail.id == AARCH64_INS_CBZ || detail.id == AARCH64_INS_CBNZ,
                   detail.operands.first?.operand.register?.key == "x20",
                   detail.operands.first?.operand.register?.widthBits == 64 {
                    let taken = test.branchTarget == block.startAddress
                    let nonZero = detail.id == AARCH64_INS_CBNZ ? taken : !taken
                    if previous.successors.count == 2 && Set(previous.successors).count == 2 { return nonZero }
                    return false
                }
                // An unconditional or fall-through hop: keep walking back.
                guard test.controlFlow != .conditionalBranch, !writesX20(test) else { return false }
                return guardedNonZero(previous, before: UInt64.max, depth: depth + 1)
            }
            for address in asyncReturns {
                switch analysis.exitAsyncErrorValues[address] {
                case .immediate(let value)?:
                    if value != 0 { exits.insert(address) }
                case .callResult(let site)?:
                    let callee = function.instructions.first { $0.address == site }
                        .flatMap(DisassembledFunction.calleeName(of:)) ?? ""
                    if callee.hasPrefix("swift_allocError") { exits.insert(address) }
                default:
                    if let block = blockOf[address], guardedNonZero(block, before: address, depth: 0) {
                        exits.insert(address)
                    }
                }
            }
            return exits
        }()
        /// Whether x21 at an exit is a proven thrown error: a non-zero flag
        /// (typed throws) or a fresh `swift_allocError` box.
        func isThrownError(_ value: AbstractValue) -> Bool {
            switch value {
            case .immediate(let flag): return flag != 0
            case .callResult(let site):
                let callee = function.instructions.first { $0.address == site }
                    .flatMap(DisassembledFunction.calleeName(of:)) ?? ""
                return callee.hasPrefix("swift_allocError")
            default: return false
            }
        }
        // A throw that falls into the normal epilogue shares its `ret` with
        // the return: `if (r0 < 0) { swift_willThrow(…) }; return r0` for a
        // function that throws on that path. Per path into the `ret`, a proven
        // error makes that path end in a throw, at the end of its predecessor
        // block; when every path throws, the `ret` itself does.
        var mergedThrowEnds = Set<UInt64>()
        var mergedThrowExits = Set<UInt64>()
        if throwsSignature?.isThrowing == true && !opaqueErrorProofTransfer {
            for (exit, paths) in analysis.exitErrorValuesByPredecessor {
                let throwing = paths.filter { isThrownError($0.value) }.map(\.key)
                guard !throwing.isEmpty else { continue }
                if throwing.count == paths.count {
                    mergedThrowExits.insert(exit)
                } else {
                    mergedThrowEnds.formUnion(throwing)
                    // The value returned is the normal paths' alone: the
                    // throwing one's x0 is what `swift_willThrow` left, and
                    // joined in, `plainThrow` read `return ((arg0 < 0) ? r1
                    // : …)`. Paths that disagree leave it unknown.
                    func normalValue(_ byPath: [UInt64: AbstractValue]?) -> AbstractValue {
                        let normal = (byPath ?? [:]).filter { !throwing.contains($0.key) }.map(\.value)
                        guard let first = normal.first, normal.allSatisfy({ $0 == first }) else { return .unknown }
                        return first
                    }
                    analysis.exitValues[exit] = normalValue(analysis.exitValuesByPredecessor[exit])
                    analysis.exitFloatValues[exit] = normalValue(analysis.exitFloatValuesByPredecessor[exit])
                }
            }
        }
        let throwExits: Set<UInt64> = {
            guard throwsSignature?.isThrowing == true, !opaqueErrorProofTransfer else { return [] }
            return asyncThrowExits.union(mergedThrowExits).union(analysis.exitErrorValues.compactMap { address, value in
                isThrownError(value) ? address : nil
            })
        }()

        // Which exits are proven normal (`SwiftErrorExitProof`). x21 arrives
        // as the caller's armed zero in a synchronous function, so a path that
        // never writes it has not thrown; an async function's x20 arrives
        // holding self and proves nothing. Paths a merged throw already ends
        // are not asked to be normal.
        let errorProofBlocks = throwsSignature?.isThrowing == true && !opaqueErrorProofTransfer
            ? cfg.basicBlocks(of: function, consumer: "error-proof") : []
        let mergedThrowEdges: Set<CFGEdge> = {
            guard !errorProofBlocks.isEmpty else { return [] }
            let blockStart = Dictionary(errorProofBlocks.flatMap { block in
                block.instructions.map { ($0.address, block.startAddress) }
            }, uniquingKeysWith: { a, _ in a })
            var edges = Set<CFGEdge>()
            for (exit, paths) in analysis.exitErrorValuesByPredecessor {
                guard let to = blockStart[exit] else { continue }
                for end in paths.keys where mergedThrowEnds.contains(end) {
                    edges.insert(CFGEdge(from: end, to: to))
                }
            }
            return edges
        }()
        // x21 is callee-saved: a call keeps it unless the callee may throw or
        // its own body does not restore it (an outlined fragment).
        func callPreservesX21(_ call: Instruction) -> Bool {
            if tracer.clobbers(atCall: call).contains("x21") { return false }
            return ValueTracer.provablyDoesNotThrow(call)
        }
        let syncNoErrorPoints = errorProofBlocks.isEmpty ? [] : SwiftErrorExitProof.noErrorPoints(
            blocks: errorProofBlocks, entry: function.startAddress, key: "x21",
            entryIsNoError: throwsSignature?.isAsync != true, excluding: mergedThrowEdges,
            callPreserves: callPreservesX21
        )
        // -Onone spills the incoming x21 and reloads it on the way out. The
        // saved-register proof follows that through the frame; it holds only
        // where every path hands the entry value back.
        let entryX21Exits: Set<UInt64> = {
            guard !errorProofBlocks.isEmpty, throwsSignature?.isAsync != true,
                  let exits = Preservation.entryValuesAtExits(
                      blocks: errorProofBlocks, entry: function.startAddress,
                      addresses: Set(function.instructions.map(\.address)), excluding: mergedThrowEdges,
                      callEffect: { call in
                          var clobbered = tracer.clobbers(atCall: call)
                          if !callPreservesX21(call) { clobbered.insert("x21") }
                          return CalleeEffect(clobbers: clobbered)
                      })
            else { return [] }
            // The saved-register proof follows only paths from the entry; an
            // exit some other way reaches is not covered by it.
            let modelled = SwiftErrorExitProof.modelledBlocks(blocks: errorProofBlocks, entry: function.startAddress)
            let blockOf = Dictionary(errorProofBlocks.flatMap { block in
                block.instructions.map { ($0.address, block.startAddress) }
            }, uniquingKeysWith: { a, _ in a })
            return Set(exits.filter { exit, preserved in
                preserved.contains("x21") && blockOf[exit].map(modelled.contains) == true
            }.keys)
        }()
        let asyncNoErrorPoints = errorProofBlocks.isEmpty || asyncReturns.isEmpty ? [] : SwiftErrorExitProof.noErrorPoints(
            blocks: errorProofBlocks, entry: function.startAddress, key: "x20", entryIsNoError: false
        ) { call in
            !tracer.clobbers(atCall: call).contains("x20")
        }

        func normalReturnIsProven(at address: UInt64) -> Bool {
            guard throwsSignature?.isThrowing == true else { return true }
            if opaqueErrorProofTransfer { return false }
            if asyncReturns.contains(address) {
                return analysis.exitAsyncErrorValues[address] == .immediate(0) || asyncNoErrorPoints.contains(address)
            }
            if analysis.exitErrorValues[address] == .immediate(0) { return true }
            if let paths = analysis.exitErrorValuesByPredecessor[address], !paths.isEmpty,
               paths.values.allSatisfy({ $0 == .immediate(0) }) { return true }
            return syncNoErrorPoints.contains(address) || entryX21Exits.contains(address)
        }

        // A synchronous throwing function whose `ret` ends a block that
        // ends in a throwing call, with nothing after the call writing x21,
        // and x21 proven zero going into the call: the callee leaves x21 as
        // its error, or as the zero it was handed, so the exit throws
        // exactly when the callee threw. It is neither a proven return nor
        // a throw but the callee's outcome handed on (`return try …`).
        // Without the zero into the call, a callee's success could leave a
        // stale x21 the caller reads as an error.
        let throwingForwardCalls: [UInt64: UInt64] = {
            guard let signature = throwsSignature, signature.isThrowing, !signature.isAsync,
                  function.objcMethod == nil, !opaqueErrorProofTransfer, !errorProofBlocks.isEmpty
            else { return [:] }
            var calls: [UInt64: UInt64] = [:]
            for block in errorProofBlocks {
                guard let last = block.instructions.last, last.controlFlow == .return,
                      !normalReturnIsProven(at: last.address), !throwExits.contains(last.address),
                      !mergedThrowExits.contains(last.address),
                      let callIndex = block.instructions.lastIndex(where: { $0.controlFlow == .call })
                else { continue }
                let after = block.instructions[(callIndex + 1)...].dropLast()
                guard after.allSatisfy({ insn in
                    (insn.controlFlow ?? .sequential) == .sequential && insn.detail.map { !$0.writtenRegisterKeys.contains("x21") } == true
                }) else { continue }
                let call = block.instructions[callIndex]
                guard syncNoErrorPoints.contains(call.address),
                      let callee = DisassembledFunction.calleeName(of: call),
                      let calleeSignature = DisassembledFunction.splitSignature(callee),
                      calleeSignature.isThrowing, !calleeSignature.isAsync,
                      // A typed error does not travel as an `any Error` in
                      // x21; forwarding one is a box or a rethrow of it.
                      calleeSignature.thrownType == nil, signature.thrownType == nil
                else { continue }
                calls[last.address] = call.address
            }
            return calls
        }()

        /// What a forwarding `ret` returns when the callee did not throw,
        /// as a value: the caller's result register built from the call's
        /// result (`count() + 1`), or a String's two words that are the
        /// call's whole String result. Nil when the value is not the call's
        /// (`mov x0, #7`), or the result does not travel in those registers.
        func throwingForwardValue(at address: UInt64) -> AbstractValue? {
            guard let site = throwingForwardCalls[address] else { return nil }
            // A result through x8 is not read here.
            guard returnsDirectly else { return nil }
            if let register = functionReturnRegister {
                guard let raw = (register == .floating ? analysis.exitFloatValues : analysis.exitValues)[address]
                else { return nil }
                var calls = Set<UInt64>()
                collectCallResults(in: sanitizeValue(raw), into: &calls)
                return calls.contains(site) ? raw : nil
            }
            if swiftStringReturnCall(at: address) == site { return .callResult(site) }
            return nil
        }

        /// A forwarding `ret`'s value rendered, or nil when it is `?` or an
        /// unresolved call.
        func throwingForward(at address: UInt64) -> String? {
            guard let value = throwingForwardValue(at: address) else { return nil }
            let rendered = functionReturnRegister != nil
                ? renderReturnValue(value, before: address) : renderValue(value, depth: 0)
            guard rendered != "?", !rendered.contains("/* unresolved") else { return nil }
            return rendered
        }

        // Which calls' indirect results are read back by word anywhere that
        // renders: a return value, a call argument, a condition, a field store,
        // or a field-wise indirect return. Each such call is bound once.
        func collectWordSites(in value: AbstractValue, into sites: inout Set<UInt64>) {
            switch value {
            case .indirectCallResultWord(let site, _):
                sites.insert(site)
            case .binary(_, let lhs, let rhs):
                collectWordSites(in: lhs, into: &sites)
                collectWordSites(in: rhs, into: &sites)
            case .unary(_, let operand):
                collectWordSites(in: operand, into: &sites)
            case .select(let condition, let whenTrue, let whenFalse):
                collectWordSites(in: condition, into: &sites)
                collectWordSites(in: whenTrue, into: &sites)
                collectWordSites(in: whenFalse, into: &sites)
            case .aggregate(let values):
                for value in values { collectWordSites(in: value, into: &sites) }
            default:
                break
            }
        }
        var wordSites = Set<UInt64>()
        for (address, value) in analysis.exitValues where returnsDirectly && normalReturnIsProven(at: address) { collectWordSites(in: value, into: &wordSites) }
        for (address, value) in analysis.exitFloatValues where returnsDirectly && normalReturnIsProven(at: address) { collectWordSites(in: value, into: &wordSites) }
        for value in analysis.branchConditions.values { collectWordSites(in: value, into: &wordSites) }
        for values in argumentsByAddress.values { for value in values { collectWordSites(in: value, into: &wordSites) } }
        // Context self is a value use too, including a field loaded from an
        // indirect result. Keep its producer at the original instruction even
        // for one adjacent use: a later presentation rewrite can hide the
        // consuming call, but must never hide the earlier evaluation with it.
        // The ABI-role map remains independent of presentation filtering.
        var contextSelfResultSites = Set<UInt64>()
        for value in selfValueBySite.values {
            collectWordSites(in: value, into: &wordSites)
            collectCallResults(in: value, into: &contextSelfResultSites)
        }
        for access in analysis.selfFieldAccesses.values {
            if let value = access.storedValue { collectWordSites(in: value, into: &wordSites) }
            for value in access.storedValues ?? [] { collectWordSites(in: value, into: &wordSites) }
        }
        for (address, exit) in analysis.exitIndirectResults where !returnsDirectly && !exit.poisoned && normalReturnIsProven(at: address) {
            // Words that reassemble one whole call result render as that call,
            // not field by field, so they bind nothing.
            guard exit.whole == nil, wholeCallResult(from: exit.stores) == nil else { continue }
            for store in exit.stores.values { collectWordSites(in: store.value, into: &wordSites) }
        }
        // Where the encoded return comes back: x0 for an integer, pointer
        // or object, v0 for one float or double. A struct of floats, one
        // of nine to sixteen bytes (`twoWordFieldReturn` aside) or one
        // returned through x8 is no one register: `-(double)scaled:` and
        // a 40-byte `-(S5)big` read `return self`.
        let objcReturnType = function.objcMethod.flatMap { ObjCArgumentABI.returnType(encoding: $0.typeEncoding) }
        let objcReturnsInX0 = objcReturnType.map(ObjCArgumentABI.takesOneXRegister) == true
        let objcReturnsOneFloat = function.objcMethod?.returnsOneFloat == true
        // An ARC method returning an object exits through a tail branch,
        // `b objc_autoreleaseReturnValue`, not a `ret`, and renders that
        // branch as `return <x0>`. The use counter and the renderer both
        // ask this one question (through `objcReturnValue`), so a return
        // the renderer prints is always a counted use: missed, the
        // configured object of
        // `f = [[X alloc] init]; f.limit = v; return f` had one use left,
        // inlined, and read as two allocations.
        func objcPassthroughReturnValue(at insn: Instruction) -> AbstractValue? {
            guard function.objcMethod.map({ !$0.returnsVoid }) == true,
                  objcReturnsInX0 || objcReturnsOneFloat,
                  insn.controlFlow == .branch,
                  let callee = calleeByAddress[insn.address],
                  insn.facts.arcIdentityContract,
                  passthroughReturnHelpers.contains(where: callee.hasPrefix),
                  let raw = analysis.exitValues[insn.address]
            else { return nil }
            let exit = sanitizeValue(raw)
            return exit == .unknown ? nil : exit
        }
        // What an Objective-C exit returns, read from the register the
        // encoding puts the result in: a `ret`'s x0 or v0, or a passthrough
        // branch's x0. Anything else is nil. x0 in a method that returns in
        // v0, v1.. or through x8 is whatever the last call left there, so
        // `sinkL(1); return 2.5` must not read that call as the result.
        func objcReturnValue(at insn: Instruction) -> AbstractValue? {
            guard insn.controlFlow == .return else { return objcPassthroughReturnValue(at: insn) }
            guard function.objcMethod.map({ !$0.returnsVoid }) == true,
                  objcReturnsInX0 || objcReturnsOneFloat,
                  let raw = (objcReturnsInX0 ? analysis.exitValues : analysis.exitFloatValues)[insn.address]
            else { return nil }
            let exit = sanitizeValue(raw)
            return exit == .unknown ? nil : exit
        }
        // A direct call result rendered in more than one place (a branch
        // condition and the return, two arguments) is one evaluation; spelled
        // out at each use it reads as the call running once per use:
        // `if ((sink(arg0) + …) < 0) { trap() } else { return (sink(arg0) << 1) }`
        // for one `bl sink`. Bound like a word-read result, it is `let rN`
        // once and `rN` everywhere. The idea is the pre-merge stash's
        // (983aa25, `let call_<addr>`); the binding is the existing one.
        var directUses: [UInt64: Int] = [:]
        var directConsumers: [UInt64: Set<UInt64>] = [:]
        func countDirectUses(_ value: AbstractValue, at consumer: UInt64) {
            switch value {
            case .callResult(let site):
                guard !nonScalarObjCResultSites.contains(site) else { return }
                directUses[site, default: 0] += 1
                directConsumers[site, default: []].insert(consumer)
            case .binary(_, let lhs, let rhs): countDirectUses(lhs, at: consumer); countDirectUses(rhs, at: consumer)
            case .unary(_, let operand): countDirectUses(operand, at: consumer)
            case .select(let condition, let whenTrue, let whenFalse):
                countDirectUses(condition, at: consumer); countDirectUses(whenTrue, at: consumer); countDirectUses(whenFalse, at: consumer)
            case .aggregate(let values): values.forEach { countDirectUses($0, at: consumer) }
            default: break
            }
        }
        // A call with no name (an unresolved `blr`) renders its arguments and
        // consumes the results in them like any other call, so it uses them:
        // skipped here, a result it took was neither bound nor shown, and
        // read as evaluated at the indirect call, after the calls between.
        for (address, values) in argumentsByAddress {
            let callee = calleeByAddress[address]
            // The runtime predicate renders its object even though the call
            // is bookkeeping. Its producer must stay before any intervening
            // effect, just like an argument of an ordinary rendered call.
            if let callee, DisassembledFunction.isUniquenessCheck(callee) {
                values.prefix(1).forEach { countDirectUses($0, at: address) }
                continue
            }
            if let callee, isRuntimeNoise(callee, at: address) { continue }
            (callee.map { normalizedArguments(callee: $0, values: values, at: address) } ?? values)
                .forEach { countDirectUses($0, at: address) }
            if let value = valueSelfBySite[address] { countDirectUses(value, at: address) }
        }
        for (address, value) in selfValueBySite { countDirectUses(value, at: address) }
        for (address, value) in analysis.branchConditions { countDirectUses(value, at: address) }
        // Declining a complete comparison does not erase a known operand's
        // producer. The text condition path may still use that saved result;
        // existing ordering checks must see it before deciding to inline.
        for (address, producers) in analysis.unresolvedBranchCallResults {
            for producer in producers { countDirectUses(.callResult(producer), at: address) }
        }
        for insn in function.instructions where insn.controlFlow == .branch && insn.branchTarget == nil
            && function.switchTargets[insn.address] == nil && !asyncReturns.contains(insn.address) {
            if let target = analysis.indirectControlFlowTargets[insn.address] { countDirectUses(target, at: insn.address) }
        }
        for (address, access) in analysis.selfFieldAccesses {
            if let values = access.storedValues { values.forEach { countDirectUses($0, at: address) } }
            else if let value = access.storedValue { countDirectUses(value, at: address) }
        }
        if function.objcMethod.map({ !$0.returnsVoid }) == true {
            for insn in function.instructions {
                objcReturnValue(at: insn).map { countDirectUses($0, at: insn.address) }
            }
        } else if function.objcMethod == nil, returnsDirectly,
                  let register = functionReturnRegister {
            for insn in function.instructions where isReturn(insn) && normalReturnIsProven(at: insn.address) && !throwExits.contains(insn.address) {
                (register == .floating ? analysis.exitFloatValues : analysis.exitValues)[insn.address]
                    .map { countDirectUses($0, at: insn.address) }
            }
        }
        // A String returned whole from a call uses that call, so one with an
        // effect between them is bound, not moved to the `return`.
        if function.objcMethod == nil, returnsDirectly {
            for insn in function.instructions where isReturn(insn) && normalReturnIsProven(at: insn.address) && !throwExits.contains(insn.address) {
                swiftStringReturnCall(at: insn.address).map { countDirectUses(.callResult($0), at: insn.address) }
            }
        }
        // A whole indirect result is also evaluated at its producer. Count
        // the same values the return later consumes, so a call/effect between
        // producer and return forces the existing binding at the original PC.
        // Otherwise `makePacket(); effect(); ret` rendered as
        // `effect(); return makePacket()` after suppressing the producer.
        if function.objcMethod == nil, !returnsDirectly {
            for insn in function.instructions where insn.controlFlow == .return && normalReturnIsProven(at: insn.address) {
                let values = Probe.muted { indirectReturn(at: insn.address)?.consumedValues } ?? []
                for value in values { countDirectUses(value, at: insn.address) }
            }
        }
        for address in throwingForwardCalls.keys {
            throwingForwardValue(at: address).map { countDirectUses($0, at: address) }
        }
        for address in asyncReturns where normalReturnIsProven(at: address) && !throwExits.contains(address) {
            let value = asyncReturnRegister == .floating ? analysis.exitFloatValues[address] : analysis.exitValues[address]
            if asyncReturnRegister != nil, let value { countDirectUses(value, at: address) }
        }
        // A single use may inline only inside the same basic block without
        // crossing another call, a memory access, or an unknown instruction.
        // Otherwise moving an evaluation to its use changes when (or whether)
        // it runs. Bind it at the original instruction instead.
        var location: [UInt64: (block: Int, index: Int)] = [:]
        let bindingBlocks = cfg.basicBlocks(of: function, consumer: "result-bindings")
        for (block, body) in bindingBlocks.enumerated() {
            for (index, insn) in body.instructions.enumerated() { location[insn.address] = (block, index) }
        }
        func crossesEffect(_ site: UInt64) -> Bool {
            guard let producer = location[site] else { return true }
            return (directConsumers[site] ?? []).contains { address in
                guard let consumer = location[address], consumer.block == producer.block,
                      consumer.index > producer.index else { return true }
                return bindingBlocks[producer.block].instructions[(producer.index + 1)..<consumer.index].contains(where: Self.isOrderingEffect)
            }
        }
        let reusedCalls = directUses.compactMap { site, uses -> UInt64? in
            // A query may itself hit the expression depth limit or have
            // no rendered use. Keep its effectful object producer at the call
            // site even then; consuming it inside the hidden query loses it.
            let feedsUniquenessCheck = (directConsumers[site] ?? []).contains {
                calleeByAddress[$0].map(DisassembledFunction.isUniquenessCheck) == true
            }
            guard uses > 1 || contextSelfResultSites.contains(site) || crossesEffect(site) || feedsUniquenessCheck,
                  let callee = calleeByAddress[site],
                  // A uniqueness predicate is a value read at this call, not
                  // a fresh query to repeat after a reference-count change.
                  (!isRuntimeNoise(callee, at: site) || DisassembledFunction.isUniquenessCheck(callee)),
                  !DisassembledFunction.isGenericPlumbingCallee(callee),
                  DisassembledFunction.arrayLiteralPlaceholder(callee: callee) == nil,
                  DisassembledFunction.castPassthroughIndex(of: callee) == nil,
                  // Rendered as `a == b` by renderBoolean before any binding is
                  // read: the synthesized equality is pure, and a `let` for it
                  // would never be used.
                  !callee.contains("__derived_enum_equals")
            else { return nil }
            // A literal-to-String conversion is pure compiler lowering. Keep
            // it visible to the interpolation folder; arbitrary String
            // initializers, including user conversions, are still bound.
            if callee.hasPrefix("Swift.String.init("),
               let values = argumentsByAddress[site], values.count == 3,
               case .address(let address) = values[0], case .immediate(let count) = values[1],
               case .immediate(1) = values[2],
               let literal = ReferenceResolver.rawCString(at: address, in: resolver.machO, ranges: resolver.fileRanges),
               UInt64(literal.utf8.count) == count { return nil }
            return site
        }
        reusedResultSites = Set(reusedCalls).subtracting(wordSites)
        for (index, site) in wordSites.union(reusedCalls).sorted().enumerated() { boundResultSites[site] = "r\(index)" }

        var consumedCallResults = Set<UInt64>()
        for insn in function.instructions where insn.controlFlow == .branch && insn.branchTarget == nil
            && function.switchTargets[insn.address] == nil && !asyncReturns.contains(insn.address) {
            if let target = analysis.indirectControlFlowTargets[insn.address] { collectCallResults(in: target, into: &consumedCallResults) }
        }
        for access in analysis.selfFieldAccesses.values {
            if let value = access.storedValue {
                collectCallResults(in: value, into: &consumedCallResults)
            }
            for value in access.storedValues ?? [] {
                collectCallResults(in: value, into: &consumedCallResults)
            }
        }
        for insn in function.instructions {
            // A call result is consumed by a call that renders it, so only
            // the arguments that render count. Read from the raw registers, a
            // result the callee does not take was marked consumed and printed
            // nowhere: `bump(void)` dropping a stale x0 erased `pick(twice(x))`.
            if sites[insn.address] != nil,
               DisassembledFunction.calleeName(of: insn)
                .map({ !isRuntimeNoise($0, at: insn.address) }) ?? true {
                let values = argumentsByAddress[insn.address] ?? []
                var rendered = calleeByAddress[insn.address]
                    .map { normalizedArguments(callee: $0, values: values, at: insn.address) } ?? values
                // A send prints its receiver and one argument per colon, and
                // a register past those only for a variadic selector: a call
                // whose result reached only x3 of an untyped `setSpan:` (an
                // NSRange in x2 and x3) was taken as printed and printed
                // nowhere.
                if let callee = calleeByAddress[insn.address],
                   let selector = selectorName(callee: callee, arguments: values)
                    ?? DisassembledFunction.MessageSend.directMethodSelector(callee),
                   !isVariadicObjCSelector(selector) {
                    rendered = Array(rendered.prefix(2 + selector.filter { $0 == ":" }.count))
                }
                for value in rendered {
                    collectCallResults(in: value, into: &consumedCallResults)
                }
                // A value method's `self` words render with the call, so a
                // call result among them is consumed there: left out,
                // `memcpy(local_48, ?, 40)` printed once as a statement and
                // again as `Circle.area.getter(self: memcpy(…))`.
                if let value = valueSelfBySite[insn.address] {
                    collectCallResults(in: value, into: &consumedCallResults)
                }
            }
            // A tail call's own arguments were taken above: x0 at the branch
            // is one of them or nothing, never the method's result.
            if let value = objcReturnValue(at: insn) {
                collectCallResults(in: value, into: &consumedCallResults)
            } else if function.objcMethod == nil, isReturn(insn),
                      normalReturnIsProven(at: insn.address),
                      !throwExits.contains(insn.address), returnsDirectly,
                      let returnRegister = functionReturnRegister {
                // A Swift return that is a call's result consumes it, so the call
                // isn't also printed as its own statement above the `return`.
                let value = returnRegister == .floating
                    ? analysis.exitFloatValues[insn.address]
                    : analysis.exitValues[insn.address]
                if let value { collectCallResults(in: value, into: &consumedCallResults) }
            } else if function.objcMethod == nil, isReturn(insn),
                      normalReturnIsProven(at: insn.address),
                      !throwExits.contains(insn.address), returnsDirectly,
                      let site = swiftStringReturn(at: insn.address)?.consumedSite {
                // A String return that is a call's whole result consumes it.
                consumedCallResults.insert(site)
            } else if let value = throwingForwardValue(at: insn.address) {
                // So does a forwarded throwing call.
                collectCallResults(in: value, into: &consumedCallResults)
            } else if asyncReturns.contains(insn.address), normalReturnIsProven(at: insn.address), !throwExits.contains(insn.address),
                      let returnRegister = asyncReturnRegister {
                let value = returnRegister == .floating
                    ? analysis.exitFloatValues[insn.address]
                    : analysis.exitValues[insn.address]
                if let value { collectCallResults(in: value, into: &consumedCallResults) }
            } else if function.objcMethod == nil, insn.controlFlow == .return, !returnsDirectly,
                      normalReturnIsProven(at: insn.address), let indirect = indirectReturn(at: insn.address) {
                // Likewise an indirect return built from a call's result (the
                // whole buffer, or its words) consumes that call, and the memory
                // helpers that copied or zeroed the result buffer are the return
                // statement's own plumbing, not statements of their own.
                for value in indirect.consumedValues { collectCallResults(in: value, into: &consumedCallResults) }
                for (address, site) in sites where address < insn.address {
                    guard let callee = calleeByAddress[address], Self.isMemoryHelper(callee),
                          let destination = site.arguments.first
                    else { continue }
                    switch destination {
                    case .indirectResultPointer, .indirectResultField: consumedCallResults.insert(address)
                    default: break
                    }
                }
            }
        }

        // A bound call is materialized by its `let` statement, never folded into
        // a use, so it stays out of the consumed set whatever referenced it.
        consumedCallResults.subtract(boundResultSites.keys)

        // The property a `_modify` accessor's ramp exposes, when this function is
        // one. A `yield_once` coroutine returns its yielded value in x1 (the ramp
        // result is `{ continuation, yields… }`, continuation first); for a stored
        // property that value is `&self.field`. The `.resume.N` continuation
        // yields nothing, so it is excluded. Only the ramp of a `_modify` (never a
        // `.read`, whose yield is a borrowed value, not an address) is recognized.
        let modifyProperty: String? = {
            guard let name = function.analysisName, !name.contains(".resume") else { return nil }
            let base = name.range(of: " : ").map { String(name[..<$0.lowerBound]) } ?? name
            guard base.hasSuffix(".modify") else { return nil }
            let property = base.dropLast(".modify".count)
            guard let dot = property.lastIndex(of: "."),
                  case let leaf = String(property[property.index(after: dot)...]), !leaf.isEmpty
            else { return nil }
            return leaf
        }()

        var observedReturnPaths: [UInt64: AbstractValue]?
        let scalarTailReturns = Self.scalarTailReturnSites(
            in: function, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex, cfg: cfg,
            provenSignature: { target, printed in
                guard case .proven(let layout) = resolver.specializationClause(at: target, printedName: printed)
                else { return nil }
                return layout.signature
            })
        func returnPath(at address: UInt64) -> ProbeValue {
            if observedReturnPaths == nil { observedReturnPaths = Probe.returnPathConditions(analysis, of: function, cfg: cfg) }
            return .abstractValue(observedReturnPaths?[address] ?? .unknown)
        }
        /// `mem64[base + 0x10] = value`, one per stored register, its width the
        /// bits the instruction stores. An assignment, not a call: a call's
        /// arguments are filtered as plumbing, and `store64(r0 + 0x38, type
        /// metadata for Swift.Int)` lost its value that way. A part the
        /// tracer did not prove names the instruction's register (`x0`, its
        /// value at the store); an indexed address is `base[?]`.
        func memoryWriteStatement(_ write: MemoryWrite) -> String {
            func rendered(_ value: AbstractValue, register: String?) -> String {
                // A call's result is named by its register here: spelled out,
                // `mem64[r0 + 0x28] = makeBox()` read as a second call.
                var calls = Set<UInt64>()
                collectCallResults(in: value, into: &calls)
                if !calls.isEmpty { return register ?? "?" }
                let text = renderValue(sanitizeValue(value), depth: 0)
                return text == "?" || text.isEmpty ? (register ?? "?") : text
            }
            var base = rendered(write.base, register: write.baseRegister)
            if let register = write.indexRegister {
                let index = rendered(write.index, register: register)
                base += write.indexShift == 0 ? " + \(index)" : " + (\(index) << \(write.indexShift))"
            }
            return zip(write.values, write.valueRegisters).enumerated().map { index, pair in
                let (value, register) = pair
                let offset = write.displacement + Int64(index * write.bytes)
                if let field = Self.classArgumentFieldTarget(of: write, offset: offset, maps: classArgumentFieldMaps) {
                    return "\(field) = \(rendered(value, register: register))"
                }
                let address = offset == 0 ? base
                    : offset > 0 ? "\(base) + 0x\(String(offset, radix: 16))" : "\(base) - 0x\(String(-offset, radix: 16))"
                return "mem\(write.bytes * 8)[\(address)] = \(rendered(value, register: register))"
            }.joined(separator: "; ")
        }

        let signatureKnown = DisassembledFunction.signatureKnown(
            displayName: function.analysisDisplayName, objcSignature: function.objcMethod?.signature)
        // Whether each exit's indirect result renders as its return value.
        let everyExitRendersResult = !analysis.exitIndirectResults.isEmpty
            && analysis.exitIndirectResults.keys.allSatisfy { indirectReturn(at: $0) != nil }
        let instructions = function.instructions.map { insn -> Instruction in
            var sourceNotes: [String] = []
            var sourceType = insn.sourceType
            // Each exit is a note and a fact, appended in step; the
            // instruction carries `Exit.carried(from:)` of them.
            var exits: [Instruction.Exit] = []
            func noteExit(_ exit: Instruction.Exit) {
                exits.append(exit)
                sourceNotes.append(exit.note)
            }
            // A `return …` or `throw …` note, not a throwing function's verdict.
            var notedReturnOrThrow: Bool { exits.contains { $0 != .unclassified && $0 != .normal(nil) } }
            var notedThrow: Bool { exits.contains { if case .throw = $0 { true } else { false } } }
            var notedForward: Bool { exits.contains { if case .forwarded = $0 { true } else { false } } }
            // Each statement is a note and a fact, appended in step; the
            // instruction carries the first, as the notes' order gave it.
            var statements: [Instruction.Statement] = []
            func noteStatement(_ statement: Instruction.Statement) {
                statements.append(statement)
                sourceNotes.append(statement.text)
            }
            var yields: Bool { statements.contains { if case .yield = $0 { true } else { false } } }
            // Every other fact is set beside its note. A fact the passes
            // before this one proved (a self dispatch) is kept.
            var facts = insn.facts

            // A `self` field access: the differentiator. `ldp x19, x20, [x20,
            // #0x20]` inside Dog.breed.getter is a 16-byte read of self.breed.
            if let access = analysis.selfFieldAccesses[insn.address] {
                if access.isWrite, !access.isAddressOf, let write = registerWrite(access) {
                    noteStatement(Self.fieldWriteStatement(write))
                } else if let field = fieldInfo(at: access.offset, bytes: access.bytes) {
                    sourceType = field.type
                    let name = field.names.count == 1
                        ? field.names[0] : "{\(field.names.joined(separator: ", "))}"
                    if access.isAddressOf {
                        sourceNotes.append("&\(fieldPath(name))")
                    } else if access.isWrite {
                        noteStatement(Self.fieldWriteStatement(fieldWrite(access, field: field)))
                    } else {
                        // A load of part of a field reads that byte range.
                        var readPath = fieldPath(name)
                        if field.names.count == 1, let fieldMap,
                           case .success(.part(let partName, let partType, let subOffset, let bytes)) =
                            fieldMap.lookup(offset: access.offset, bytes: max(access.bytes, 1)) {
                            readPath = fieldPath(memberPath(partName, type: partType, subOffset: subOffset, bytes: bytes))
                        }
                        facts.fieldRead = readPath
                        sourceNotes.append(readPath)
                    }
                }
            }

            // A store nothing above described still writes memory. Unshown,
            // a setter rendered as an empty body: the compiler-grounded audit
            // found 320 of 4,165 stripped swift-syntax functions empty or a
            // bare `return` while their code stored to memory.
            // An indirect-result write is the function's result: shown by its
            // return when a signature says what is returned and every exit
            // renders it, and only here otherwise. A return that could not
            // be rebuilt reads `return ?`, and the stores were all it said.
            if let detail = insn.detail, ValueTracer.plainStoreIDs.contains(detail.id.rawValue) {
                let level: String
                if let write = analysis.memoryWrites[insn.address] {
                    let shown = write.kind == "address"
                        || (write.kind == "result" && !(signatureKnown && everyExitRendersResult))
                    level = !shown ? write.kind : !statements.isEmpty ? "semantic"
                        : write.indexed ? "unresolved" : "address"
                    if level == "address" { noteStatement(.assignment(memoryWriteStatement(write))) }
                } else {
                    level = "unanalysed"
                }
                Probe.record(.memoryWrite, at: insn.address, ["level": .label(level)])
            }

            // Parsed once per call or branch above; nil for anything else,
            // where no use below applies.
            let callee = calleeByAddress[insn.address]
            let isObjCNonVoid = function.objcMethod.map { !$0.returnsVoid } == true
            if scalarTailReturns.contains(insn.address), let callee {
                noteExit(.normal(callExpression(callee: callee, values: argumentsByAddress[insn.address] ?? [], site: insn.address)))
            }
            if isObjCNonVoid, insn.controlFlow == .return, let field = twoWordFieldReturn(at: insn.address) {
                noteExit(.normal(field))
            } else if isObjCNonVoid, insn.controlFlow == .return, let exit = objcReturnValue(at: insn) {
                // A float constant is its value, not its bit pattern.
                if objcReturnsOneFloat {
                    let type = function.objcMethod?.typeEncoding.first { !"rnNoORVA".contains($0) } == "f"
                        ? "Swift.Float" : "Swift.Double"
                    noteExit(.normal(renderReturnValue(Self.floatingPointValue(exit, type: type), before: insn.address)))
                } else {
                    noteExit(.normal(renderReturnValue(exit, before: insn.address)))
                }
            } else if isObjCNonVoid, objcReturnsInX0 || objcReturnsOneFloat {
                if insn.controlFlow == .branch, let callee {
                    if let passthrough = objcPassthroughReturnValue(at: insn) {
                        noteExit(.normal(renderReturnValue(passthrough, before: insn.address)))
                    } else if insn.facts.arcIdentityContract, passthroughReturnHelpers.contains(where: callee.hasPrefix) {
                        // Its declared nonvoid exit remains a value exit even
                        // when the forwarded object is unknown or absent.
                        noteExit(.normal("?"))
                    } else if analysis.exitValues[insn.address] != nil,
                              !isRuntimeNoise(callee, at: insn.address),
                              !nonScalarObjCResultSites.contains(insn.address),
                              let values = argumentsByAddress[insn.address] {
                        noteExit(.normal(callExpression(callee: callee, values: values, site: insn.address)))
                    }
                }
            }
            // A struct of floats comes back in v0-v3, so a tail call to a C
            // function declared to return a struct forwards it whole:
            // `return CGRectInset(…)`.
            if isObjCNonVoid, exits.isEmpty, insn.controlFlow == .branch, let callee,
               function.objcMethod?.returnsFloatAggregate == true,
               DisassembledFunction.cPrototype(of: callee)?.result == "s",
               let values = argumentsByAddress[insn.address] {
                noteExit(.normal(callExpression(callee: callee, values: values, site: insn.address)))
            }
            if isObjCNonVoid, insn.controlFlow == .return, exits.isEmpty {
                noteExit(.normal("?"))
            }

            // A Swift function surfaces its return value too — the reason a pure
            // leaf like `Point.distance` otherwise shows nothing. Only a real
            // `ret` (a tail-call branch's x0/v0 hold the callee's arguments, not a
            // result) and only return types delivered in one value register, so a
            // stale register is never printed as a fabricated return.
            if mergedThrowEnds.contains(insn.address) {
                facts.thenThrows = true
                sourceNotes.append(DisassembledFunction.thenThrowNote)
            }
            if throwExits.contains(insn.address) {
                // A typed error small enough to travel in x0 names its case when
                // the error type is a no-payload enum; anything else is `?`.
                var thrown = "?"
                if let errorType = throwsSignature?.thrownType,
                   case .immediate(let tag)? = analysis.exitValues[insn.address].map(sanitizeValue),
                   tag <= UInt64(Int.max),
                   let caseName = enumCaseIndex.caseName(ofEnum: errorType, tag: Int(tag)) {
                    thrown = "\(errorType).\(caseName)"
                }
                noteExit(.throw(thrown))
            } else if function.objcMethod == nil, isReturn(insn), returnsDirectly,
               normalReturnIsProven(at: insn.address), let returnRegister = functionReturnRegister {
                let rawExit = returnRegister == .floating
                    ? analysis.exitFloatValues[insn.address]
                    : analysis.exitValues[insn.address]
                if let rawExit {
                    let exit = sanitizeValue(rawExit)
                    if exit != .unknown {
                        noteExit(.normal(renderReturnValue(exit, before: insn.address)))
                    }
                }
            } else if function.objcMethod == nil, isReturn(insn), returnsDirectly,
                      normalReturnIsProven(at: insn.address), let returnTypeName,
                      let field = swiftTwoWordFieldReturn(at: insn.address, type: returnTypeName) {
                noteExit(.normal(field))
            } else if function.objcMethod == nil, isReturn(insn), returnsDirectly,
                      normalReturnIsProven(at: insn.address),
                      let string = swiftStringReturn(at: insn.address) {
                noteExit(.normal(string.rendered))
            } else if function.objcMethod == nil, isReturn(insn), returnsDirectly,
                      normalReturnIsProven(at: insn.address), let returnTypeName,
                      case .immediate(let x0)? = analysis.exitValues[insn.address].map(sanitizeValue) {
                // Not a proven single-register type, but a payload enum returned
                // in x0/x1 is named by its exact byte pattern over both registers
                // (`PayloadEnumCaseIndex`), which proves its own layout. Nothing
                // else about x0 is read here.
                let x1: UInt64? = {
                    guard case .immediate(let value)? = analysis.exitYieldValues[insn.address].map(sanitizeValue)
                    else { return nil }
                    return value
                }()
                if let caseName = payloadEnumIndex.caseName(ofEnum: returnTypeName, x0: x0, x1: x1) {
                    noteExit(.normal("\(returnTypeName).\(caseName)"))
                }
            } else if asyncReturns.contains(insn.address), normalReturnIsProven(at: insn.address), let returnRegister = asyncReturnRegister {
                let rawExit = returnRegister == .floating
                    ? analysis.exitFloatValues[insn.address]
                    : analysis.exitValues[insn.address]
                if let rawExit {
                    let exit = sanitizeValue(rawExit)
                    if exit != .unknown {
                        noteExit(.normal(renderReturnValue(exit, before: insn.address)))
                    }
                }
            }

            // An x8-indirect function's return: the stores through the incoming
            // x8 that reach this `ret` on every path, rendered as the whole
            // callee result the buffer was filled with, or field by field when
            // they cover the result type's complete layout. Anything less
            // (an escaped pointer, a field missing on one path, a type with no
            // layout) prints nothing, and the structurer's `return ?` stands.
            if function.objcMethod == nil, insn.controlFlow == .return, !returnsDirectly,
               normalReturnIsProven(at: insn.address), let indirect = indirectReturn(at: insn.address) {
                noteExit(.normal(indirect.rendered))
            }

            // A suspension point. An executor hop names the executor only when
            // both operands prove it; an awaited call is marked for the pseudo
            // renderer, with the name its result gets when that is provable.
            if let suspension = asyncSuspensions[insn.address] {
                switch suspension {
                case .executorHop:
                    let executor: String = {
                        guard let values = sites[insn.address]?.arguments, values.count >= 3 else { return "?" }
                        if values[1] == .immediate(0), values[2] == .immediate(0) { return "generic" }
                        if case .callResult(let site) = values[1], values[2] == .callResult(site),
                           calleeByAddress[site] == "swift_task_getMainExecutor" {
                            return "MainActor"
                        }
                        return "?"
                    }()
                    noteStatement(.executorHop(executor))
                case .awaitedCall(let binding):
                    facts.awaitBinding = binding ?? ""
                    sourceNotes.append("await=\(binding ?? "")")
                }
            }

            // A `br` through a register that no jump table, tracer target or
            // async return explains: control leaves for an unknown place (a
            // tail call through a pointer, an awaited closure or witness, or a
            // jump table not recovered). Without a statement the path simply
            // ended: an `await` through a closure vanished, and a function
            // whose only call was `br x1` read as a leaf.
            if insn.controlFlow == .branch, insn.branchTarget == nil, callee == nil,
               function.switchTargets[insn.address] == nil,
               !asyncReturns.contains(insn.address) {
                // The tracer may have proven the register (`br x2` through a
                // function-pointer argument renders `indirect_jump(arg2)`).
                // A load from a slot the program can rewrite is not its
                // initial bind: `indirect_jump(puts)` named the callee that
                // `indirectCallTarget` declines.
                let target = analysis.indirectControlFlowTargets[insn.address]
                    .map { value -> AbstractValue in
                        if case .loaded(let slot) = value, !resolver.holdsFixedPointer(at: slot) { return .unknown }
                        return value
                    }
                    .map(sanitizeValue).map { renderValue($0, depth: 0) } ?? "?"
                facts.indirectJumpTarget = target
                sourceNotes.append(DisassembledFunction.indirectJumpNote + target)
            }

            // A `_modify` accessor's ramp yields `&self.field` (the mutable
            // storage) in x1. Surfacing it completes the get/set/modify trio and
            // replaces the misleading "pure computation" blank. Rendered ONLY when
            // the body-derived field (x1 at the yield) agrees with the accessor's
            // own property name; a mismatch means the field map is not to be
            // trusted here, so decline rather than name the wrong storage.
            if let modifyProperty, insn.controlFlow == .return,
               let rawYield = analysis.exitYieldValues[insn.address] {
                let offset: Int? = switch rawYield {
                case .selfField(let o): o
                case .selfPointer: 0
                default: nil
                }
                if let offset, let field = fieldInfo(at: offset, bytes: 1),
                   field.names == [modifyProperty] {
                    noteStatement(.yield("&\(fieldPath(modifyProperty))"))
                }
            }

            // A flags-based conditional branch whose comparison the value tracer
            // reconstructed with real operands — baked as a `cond:` note the
            // structurer prefers over its raw-register text back-substitution.
            // Only clean comparisons are baked: a call-result operand is left to
            // the structurer's text path, which inlines the send (`[x isKind…]`)
            // more readably than `([x isKind…] != 0)`.
            if insn.controlFlow == .conditionalBranch,
               let raw = analysis.branchConditions[insn.address] {
                let condition = sanitizeValue(raw)
                var callResults = Set<UInt64>()
                collectCallResults(in: condition, into: &callResults)
                if condition != .unknown, callResults.isEmpty,
                   !Self.isTruthinessTest(condition) {
                    let rendered = renderValue(condition, depth: 0)
                    facts.condition = rendered
                    sourceNotes.append("cond: \(rendered)")
                }
            }
            // Proven loop induction body updates (`total += i` | `i += 1`) on the
            // loop header's branch — the structurer emits them on its back-edge.
            // Joined with `|` (no update contains one).
            if let ordered = analysis.loopUpdates[insn.address], !ordered.isEmpty {
                facts.loopUpdates = ordered
                sourceNotes.append("loop-update: \(ordered.joined(separator: " | "))")
            }
            if let bindings = analysis.loopInitializations[insn.address], !bindings.isEmpty {
                let declarations = bindings.map(Self.loopDeclaration)
                facts.loopInitializations = declarations
                sourceNotes.append("loop-init: \(declarations.joined(separator: " | "))")
            }
            if let bindings = analysis.loopEntryDeclarations[insn.address], !bindings.isEmpty {
                let declarations = bindings.map(Self.loopDeclaration)
                facts.loopEntryDeclarations = declarations
                sourceNotes.append("loop-entry: \(declarations.joined(separator: " | "))")
            }

            if insn.controlFlow == .branch, let callee,
               let site = sites[insn.address],
               let helper = objcHelperStatement(callee: callee, site: site) {
                noteStatement(.assignment(helper))
            }

            // A vtable dispatch to one of `self`'s own setters is the assignment
            // it performs — `self.prop = value` — where the new value is the
            // call's first argument. Getters aren't baked here: their result is
            // consumed inline (rendered as `self.prop` where it's used), so a
            // statement note would duplicate them.
            // The value is the setter's parameter as its type travels: one
            // integer register, one floating-point register, or a String's
            // two words. Read as the first integer register alone, `label =
            // ""` (0, 0xe000000000000000) rendered `self.label = 0`.
            if let callee, let access = selfAccessors[callee], !access.isGetter,
               let site = sites[insn.address],
               let type = callee.range(of: " : ").map({ String(callee[$0.upperBound...]) }) {
                var rendered: String?
                switch SwiftLowering.of(type, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
                case .oneInteger:
                    rendered = site.arguments.first.map { renderValue(sanitizeValue($0), depth: 0) }
                case .oneFloat:
                    // A constant is the float its bits spell, at the type's width.
                    let bits = ["Swift.Float", "Swift.Float32"].contains(type) ? 32 : type == "Swift.Float16" ? 16 : 64
                    rendered = site.floatArguments.first.map { value in
                        let value = sanitizeValue(value)
                        return renderValue(ValueTracer.floatOperand(value, bits: bits), depth: 0)
                    }
                default:
                    if Self.twoWordStringTypes.contains(type), site.arguments.count >= 2 {
                        let (low, high) = (site.arguments[0], site.arguments[1])
                        rendered = swiftStringLiteral(low, high)
                            ?? stringCallResult(low, high).map { renderValue(.callResult($0), depth: 0) }
                            ?? selfStringField(low, high)
                    }
                }
                if let rendered, rendered != "?" {
                    noteStatement(.assignment("self.\(access.property) = \(rendered)"))
                }
            }

            if function.objcMethod?.isInitializer == true,
               insn.controlFlow == .call,
               let callee, callee.hasPrefix("objc_msgSendSuper"),
               let values = argumentsByAddress[insn.address] {
                noteStatement(.selfInitialization(callExpression(callee: callee, values: values)))
            }

            // The one place a call bound for its field reads is spelled out.
            // It is the call, so it names `self` as the statement would.
            if insn.controlFlow == .call, let name = boundResultSites[insn.address], let callee {
                let expression: String
                if reusedResultSites.contains(insn.address) {
                    // As each use would have spelled it (`? as? Dog`, a send).
                    definingSite = insn.address
                    expression = renderValue(.callResult(insn.address), depth: 0)
                    definingSite = nil
                } else {
                    expression = callExpression(
                        callee: callee, values: argumentsByAddress[insn.address] ?? [], site: insn.address,
                        selfText: selfValueBySite[insn.address].map { renderValue($0, depth: 0) })
                }
                let bound = Instruction.Binding(name: name, expression: expression)
                facts.binding = bound
                sourceNotes.append(bound.statement)
            }

            // Unknown facts do not mean the source result is absent. Keep the
            // exit visible even when there were no usable tracer facts at all.
            let valueContract = provenMachineValueReturn
                || (throwsSignature?.isThrowing == true && signatureReturnsValue && normalReturnIsProven(at: insn.address))
                || (asyncReturns.contains(insn.address) && signatureReturnsValue)
            if isReturn(insn), valueContract, normalReturnIsProven(at: insn.address), !throwExits.contains(insn.address),
               !mergedThrowEnds.contains(insn.address), !notedReturnOrThrow, !yields {
                noteExit(.normal("?"))
            }

            if isReturn(insn), let forwarded = throwingForward(at: insn.address) {
                noteExit(.forwarded(forwarded))
            }
            if isReturn(insn), throwsSignature?.isThrowing == true,
               !normalReturnIsProven(at: insn.address), !throwExits.contains(insn.address),
               !mergedThrowExits.contains(insn.address), !notedThrow, !notedForward {
                noteExit(.unclassified)
            }
            // A proven normal exit with no result to print still says so: with
            // no note, a renderer cannot tell it from an exit never classified.
            if isReturn(insn), throwsSignature?.isThrowing == true,
               normalReturnIsProven(at: insn.address), !throwExits.contains(insn.address),
               !mergedThrowExits.contains(insn.address), !notedReturnOrThrow, !yields {
                noteExit(.normal(nil))
            }
            facts.exit = Instruction.Exit.carried(from: exits)
            facts.statement = statements.first

            if Probe.isActive, isReturn(insn) || scalarTailReturns.contains(insn.address) {
                let renderedReturn = exits.lazy.compactMap { exit -> String? in
                    if case .normal(let value?) = exit { "return \(value)" } else { nil }
                }.first
                let returnsValue = signatureReturnsValue
                let status = scalarTailReturns.contains(insn.address) ? "tail-call"
                    : throwExits.contains(insn.address) ? "throw"
                    : notedForward ? "forwarded"
                    : renderedReturn == "return ?" ? "unknown"
                    : renderedReturn != nil ? (completeReturnRendering[insn.address] == false ? "partial" : "recovered")
                    : !returnsValue ? (DisassembledFunction.signatureKnown(displayName: function.analysisDisplayName,
                                          objcSignature: function.objcMethod?.signature) ? "void" : "no-signature")
                    : "unsupported-layout-or-value"
                Probe.record(.returnOutcome, at: insn.address, ["status": .label(status),
                    "type": .name(returnTypeName ?? function.objcMethod?.signature ?? "unknown"),
                    "path": returnPath(at: insn.address)])
                if status == "recovered", let renderedReturn {
                    let register = asyncReturns.contains(insn.address) ? asyncReturnRegister
                        : functionReturnRegister
                    let value: AbstractValue = if isObjCNonVoid {
                        analysis.exitValues[insn.address].map(sanitizeValue) ?? .unknown
                    } else if returnsDirectly, let register {
                        (register == .floating ? analysis.exitFloatValues : analysis.exitValues)[insn.address]
                            .map(sanitizeValue) ?? .unknown
                    } else { .unknown }
                    Probe.record(.returnValue, at: insn.address, ["value": .abstractValue(value),
                        "register": .label(register == .floating ? "v0" : register != nil || isObjCNonVoid ? "x0" : "indirect-or-aggregate"),
                        "type": .name(returnTypeName ?? "unknown"), "rendered": .name(renderedReturn),
                        "path": returnPath(at: insn.address)])
                }
            }

            // A proven async return is the function's `ret`; the structurer and
            // the CFG read it as one. Its nil-target BR and RET have the
            // same block boundary and no successors, so the retained graph
            // remains valid while every view reads these final instructions.
            let flow: ControlFlow? = asyncReturns.contains(insn.address) ? .return : insn.controlFlow
            let untouched = Instruction(
                address: insn.address, text: insn.text, annotation: insn.annotation,
                controlFlow: flow, branchTarget: insn.branchTarget,
                callArguments: insn.callArguments, callSelf: insn.callSelf,
                resultConsumed: insn.resultConsumed, sourceType: insn.sourceType, detail: insn.detail,
                callee: .kept(insn.callee), facts: insn.facts
            )
            guard let site = sites[insn.address] else {
                guard !sourceNotes.isEmpty || consumedCallResults.contains(insn.address) else { return untouched }
                let merged = ([insn.annotation] + sourceNotes).compactMap { $0 }.joined(separator: "  ")
                return Instruction(
                    address: insn.address, text: insn.text, annotation: merged,
                    controlFlow: flow, branchTarget: insn.branchTarget,
                    callArguments: insn.callArguments, callSelf: insn.callSelf,
                    resultConsumed: consumedCallResults.contains(insn.address),
                    sourceType: sourceType, detail: insn.detail, callee: .kept(insn.callee), facts: facts
                )
            }

            let selfText = selfValueBySite[insn.address].map { renderValue($0, depth: 0) }

            let rendered: [String] = (argumentsByAddress[insn.address]).map { values in
                // Clamp a fixed-ABI callee's arguments to its real arity before
                // rendering the top-level statement, so a stale live register does
                // not surface as a fabricated trailing argument (`abort([? x])`).
                let clamped = callee.map { normalizedArguments(callee: $0, values: values, at: insn.address) } ?? values
                return renderArguments(clamped, depth: 0, site: insn.address)
            } ?? []
            guard !rendered.isEmpty || selfText != nil || !sourceNotes.isEmpty
                    || consumedCallResults.contains(insn.address)
            else { return untouched }

            var notes = sourceNotes
            if let selfText { notes.append("self=\(selfText)") }
            if !rendered.isEmpty { notes.append("args(" + rendered.joined(separator: ", ") + ")") }
            let merged = ([insn.annotation] + notes).compactMap { $0 }.joined(separator: "  ")
            return Instruction(
                address: insn.address, text: insn.text, annotation: merged,
                controlFlow: flow, branchTarget: insn.branchTarget,
                callArguments: rendered.isEmpty ? nil : rendered,
                callSelf: selfText, resultConsumed: consumedCallResults.contains(insn.address),
                sourceType: sourceType, detail: insn.detail,
                calleeDisplayName: callee.map { demangleCache.presentation(of: $0) },
                callee: .kept(insn.callee), facts: facts
            )
        }
        return function.replacingInstructions(instructions).retainingCFG(cfg)
    }

    /// The `memN[...] = value` statements of a function the full enrichment
    /// skips (no calls, no other facts), by store address, with each plain
    /// store's level recorded. With no calls there is no call result to
    /// spell: a value is a constant, an argument, an address or, unproven,
    /// the instruction's register.
    static func leafMemoryWrites(_ function: DisassembledFunction, analysis: FunctionAnalysis) -> [UInt64: String] {
        func rendered(_ value: AbstractValue, register: String?) -> String {
            switch value {
            case .immediate(let bits): renderImmediate(bits)
            case .argument(let index): "arg\(index)"
            case .address(let address): "0x" + String(address, radix: 16)
            case .indirectResultPointer: "&result"
            default: register ?? "?"
            }
        }
        var statements: [UInt64: String] = [:]
        for insn in function.instructions {
            guard let detail = insn.detail, ValueTracer.plainStoreIDs.contains(detail.id.rawValue) else { continue }
            let level: String
            if let write = analysis.memoryWrites[insn.address] {
                // A result write leaves an indirect-result exit fact, which
                // takes the function down the full enrichment instead.
                level = write.kind != "address" ? write.kind : write.indexed ? "unresolved" : "address"
                if level == "address" {
                    var base = rendered(write.base, register: write.baseRegister)
                    if let register = write.indexRegister {
                        let index = rendered(write.index, register: register)
                        base += write.indexShift == 0 ? " + \(index)" : " + (\(index) << \(write.indexShift))"
                    }
                    statements[insn.address] = zip(write.values, write.valueRegisters).enumerated().map { index, pair in
                        let offset = write.displacement + Int64(index * write.bytes)
                        let address = offset == 0 ? base
                            : offset > 0 ? "\(base) + 0x\(String(offset, radix: 16))" : "\(base) - 0x\(String(-offset, radix: 16))"
                        return "mem\(write.bytes * 8)[\(address)] = \(rendered(pair.0, register: pair.1))"
                    }.joined(separator: "; ")
                }
            } else {
                level = "unanalysed"
            }
            Probe.record(.memoryWrite, at: insn.address, ["level": .label(level)])
        }
        return statements
    }

    /// The statement a field write makes. A tuple of Swift fields
    /// (`(self.a, self.b) = …`) is one as well as Objective-C's: it was only
    /// noted, so `FieldPQ.set`'s `stp x0, x1, [x20]` printed nothing.
    static func fieldWriteStatement(_ write: String) -> Instruction.Statement {
        .assignment(write)
    }

    /// `adrp x8, 12 ; 0x10000c000` (llvm-objdump) or `adrp x8, 0x10000c000`
    /// (Capstone) → ("x8", 0x10000c000). objdump keeps the resolved page in a
    /// trailing comment; Capstone puts it straight in the operand.
    private func parseAdrp(_ text: String) -> (register: String, page: UInt64)? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.first == "adrp", fields.count >= 2 else { return nil }
        let register = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        if let hashIndex = text.range(of: "; 0x")?.upperBound {
            let hex = text[hashIndex...].prefix { $0.isHexDigit }
            if let page = UInt64(hex, radix: 16) { return (register, page) }
        }
        if fields.count >= 3 {
            let operand = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "#, "))
            if operand.hasPrefix("0x"), let page = UInt64(operand.dropFirst(2), radix: 16) {
                return (register, page)
            }
        }
        return nil
    }

    /// For `add xN, xB, #0x170` or `ldr xT, [xB, #0x170]`, return (base xB, 0x170).
    private func parsePageOffset(_ text: String) -> (base: String, offset: UInt64)? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let mnemonic = fields.first else { return nil }
        func immediate(_ token: Substring) -> UInt64? {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "#[],"))
            guard cleaned.hasPrefix("0x"), let value = UInt64(cleaned.dropFirst(2), radix: 16) else { return nil }
            return value
        }
        func register(_ token: Substring) -> String {
            String(token).trimmingCharacters(in: CharacterSet(charactersIn: "[],"))
        }
        if mnemonic == "add", fields.count >= 4 {
            guard let offset = immediate(fields[3]) else { return nil }
            return (register(fields[2]), offset)
        }
        if mnemonic.hasPrefix("ldr") || mnemonic.hasPrefix("ldur"), fields.count >= 4 {
            // ldr xT, [xB, #imm]  → fields: ["ldr", "xT,", "[xB,", "#imm]"]
            guard let offset = immediate(fields[3]) else { return nil }
            return (register(fields[2]), offset)
        }
        return nil
    }

    /// The instruction's first operand register (its destination for the ops we
    /// track), e.g. `add x0, …` → "x0". Used only for page invalidation.
    private func firstRegister(_ text: String) -> String? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2 else { return nil }
        var token = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "[],"))
        guard let first = token.first, first == "x" || first == "w" else { return nil }
        // Normalize the 32-bit view (w0) to its 64-bit register (x0); a w-write
        // still clobbers the full register that held the adrp page.
        if first == "w" { token = "x" + token.dropFirst() }
        return token
    }

    // MARK: - objdump parsing

    /// Parse objdump output into a flat instruction list plus a map from each
    /// labeled function's start address to its raw label.
    private func parseObjdump(_ output: String) -> ([Instruction], [UInt64: String]) {
        var instructions: [Instruction] = []
        var labelByAddress: [UInt64: String] = [:]
        var pendingLabel: String?
        // objdump opens with the file's path and a colon, the shape of a
        // label. In an image whose first function has no symbol it named
        // that function: `disasm /usr/bin/true` titled it `/usr/bin/true`.
        // Labels count only inside a section's listing.
        var inSection = false

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasSuffix(") section") {
                inSection = true
                continue
            }
            if let (address, text) = parseInstruction(line) {
                if let label = pendingLabel {
                    labelByAddress[address] = label
                    pendingLabel = nil
                }
                instructions.append(
                    Instruction(address: address, text: text, annotation: annotate(text))
                )
            } else if inSection, let label = parseLabel(line) {
                pendingLabel = label
            }
        }
        return (instructions, labelByAddress)
    }

    /// Matches `100000e58:\tstp x29, x30, …` → (0x100000e58, "stp …").
    ///
    /// The address column is **right-aligned**, so it carries leading whitespace
    /// whenever the binary's `__text` addresses are shorter than objdump's widest
    /// one: an executable linked at `0x100000000` prints `100000e58:` flush left,
    /// but a dylib based near zero prints `     b60:`. Trimming is therefore
    /// mandatory, not cosmetic — without it every instruction line in such a
    /// binary fails the hex test, `parsed` comes back empty, and the unfiltered
    /// path reports "No functions matched" on a binary that disassembles fine
    /// under `--function`.
    private func parseInstruction(_ line: String) -> (UInt64, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let addrPart = line[line.startIndex..<colon].drop(while: { $0 == " " })
        guard !addrPart.isEmpty,
              addrPart.allSatisfy({ $0.isHexDigit }),
              let address = UInt64(addrPart, radix: 16)
        else { return nil }
        let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (address, rest)
    }

    /// Matches a function label line such as `_main:` or `_$s6sample3runyyF:`.
    private func parseLabel(_ line: String) -> String? {
        guard line.hasSuffix(":"),
              let first = line.first,
              !first.isWhitespace
        else { return nil }
        let name = String(line.dropLast())
        guard !name.contains(" "), !name.contains("(") else { return nil }
        return name
    }

    // MARK: - Demangling / annotation

    /// Demangle a Swift mangled symbol token to a readable name.
    func demangle(_ token: String) -> String? {
        var s = token
        if s.hasPrefix("_$s") || s.hasPrefix("_$S") || s.hasPrefix("_$e") {
            s.removeFirst()
        }
        // Fast-path reject before the cache: `annotate` calls this on every
        // operand token, most of which are not Swift-mangled at all.
        guard s.hasPrefix("$s") || s.hasPrefix("$S") || s.hasPrefix("$e") || s.hasPrefix("_T") else {
            return nil
        }
        // Memoized on the normalized symbol `s`. The same symbol is demangled
        // repeatedly across one run — a definition's own label, the names given
        // to calls that target it, xref edges — measured at ~2.5x redundancy on
        // the fixtures and higher on frameworks. Demangling is a pure function of
        // (symbol, preset), so the cache cannot change output; it is scoped to
        // this `Disassembler` instance, i.e. one run.
        return demangleCache.value(for: s) { s in
            // Sync context → the sync `print` overload is selected (no await).
            guard let node = try? demangleAsNode(s) else { return nil }
            demangleCache.rememberNominalTypes(from: node, options: .default)
            let printed = node.print(using: .default)
            if preset != .default {
                demangleCache.rememberPresentation(node.print(using: preset.options), for: printed)
            }
            return printed.isEmpty ? nil : printed
        }
    }

    /// The address a `-f 0x…` filter names, or nil for a name filter.
    static func filterAddress(_ filter: String) -> UInt64? {
        let text = filter.lowercased()
        guard text.hasPrefix("0x"), text.count > 2 else { return nil }
        return UInt64(text.dropFirst(2), radix: 16)
    }

    private func matchesName(_ semantic: String, needle: String) -> Bool {
        semantic.lowercased().contains(needle)
            || demangleCache.presentation(of: semantic).lowercased().contains(needle)
    }

    /// First Swift mangled token in an instruction's operands, demangled.
    private func annotate(_ text: String) -> String? {
        for token in text.split(whereSeparator: { " ,\t".contains($0) }) {
            if let demangled = demangle(String(token)) {
                return demangled
            }
        }
        return nil
    }
}
