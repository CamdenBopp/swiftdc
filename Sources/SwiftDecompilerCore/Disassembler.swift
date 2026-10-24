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
        /// For a read of a field of self: the field's path (`self.x`).
        public var fieldRead: String?
        /// For a call through self's own vtable slot (`dispatch=self`): an
        /// override in a subclass runs instead when self is one.
        public var isSelfDispatch: Bool

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
            isSelfDispatch: Bool = false
        ) {
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

        /// The annotation note that carries this exit.
        public var note: String {
            switch self {
            case .normal(let value?): "return \(value)"
            case .normal(nil): DisassembledFunction.normalSwiftExitNote
            case .throw(let error): "throw \(error)"
            case .unclassified: DisassembledFunction.unresolvedSwiftExitNote
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
    /// Named from an Objective-C class/category method record (survives
    /// stripping and carries selector, type encoding, and IMP).
    case objcMetadata = "objc-metadata"
    /// Boundary known (LC_FUNCTION_STARTS) but no name — synthesized `sub_<addr>`.
    case address
    /// Boundary known, but the symbol table lists two or more *distinct* symbols
    /// at this address. The release linker's identical-code-folding pass merged
    /// several unrelated declarations onto one instruction stream, and nothing in
    /// their mangled names records the merge — so no single symbol can be
    /// attributed. Rendered `sub_<addr>` with the candidates listed, never guessed.
    case foldedSymbols = "folded-symbols"
    /// Boundary known (LC_FUNCTION_STARTS) and no symbol, but the address is a
    /// resume funclet of an async function: it is stored as a resume pointer by
    /// that function's chain, so it is titled after its parent
    /// (`resume #N of <parent>`). See `AsyncFuncletIndex`.
    case asyncFunclet = "async-funclet"
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
        semanticName: String? = nil
    ) {
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
    }

    /// The same function with `instructions` replaced; every other field is
    /// carried over, so an enrichment pass cannot drop one by omission.
    func replacingInstructions(_ instructions: [Instruction]) -> DisassembledFunction {
        DisassembledFunction(
            symbol: symbol, demangledName: demangledName, startAddress: startAddress,
            instructions: instructions, source: source, objcMethod: objcMethod,
            foldedCandidates: foldedCandidates, asyncFunclet: asyncFunclet,
            switchTargets: switchTargets, semanticName: semanticName
        )
    }

    /// The same function with its recovered jump tables attached.
    func attachingSwitchTargets(_ tables: [UInt64: [UInt64]]) -> DisassembledFunction {
        DisassembledFunction(
            symbol: symbol, demangledName: demangledName, startAddress: startAddress,
            instructions: instructions, source: source, objcMethod: objcMethod,
            foldedCandidates: foldedCandidates, asyncFunclet: asyncFunclet,
            switchTargets: tables, semanticName: semanticName
        )
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
            switchTargets: switchTargets, semanticName: semanticName
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
    var analysisDisplayName: String { analysisName ?? symbol }

    /// Render this function as annotated assembly text.
    public func render() -> String {
        var lines: [String] = []
        lines.append("\(displayName):")
        let tag: String = switch source {
        case .metadata: "  [recovered from Swift metadata]"
        case .objcMetadata: "  [recovered from Objective-C metadata]"
        case .asyncFunclet: "  [titled from its async parent; boundary from LC_FUNCTION_STARTS]"
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
            lines.append("  // unnamed function  @ 0x\(String(startAddress, radix: 16))  [boundary from LC_FUNCTION_STARTS]")
        }
        if let asyncLine = asyncHeaderLine() { lines.append("  \(asyncLine)") }
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
        case parsedNothing(lines: Int, knownStarts: Int)
        public var description: String {
            switch self {
            case .toolFailed(let m): return "llvm-objdump failed: \(m)"
            case .parsedNothing(let lines, let starts):
                return """
                    disassembly parse failed: llvm-objdump produced \(lines) lines but no \
                    instruction was recognised, while LC_FUNCTION_STARTS lists \(starts) \
                    function(s). This is a parser defect, not an empty binary.
                    """
            }
        }
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
        var args = ["-d", "--macho", "--no-show-raw-insn"]
        if let architecture {
            args += ["--arch", architecture]
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
            functionFilter: nil
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
        if let filter = functionFilter, !filter.isEmpty {
            let ranges = await matchedRanges(filter: filter, in: machO, objcIndex: objcIndex)
            guard !ranges.isEmpty else { return [] }
            let matched = ranges.flatMap { capstoneInstructions(in: machO, span: $0) }
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
        guard !instructions.isEmpty else { return [] }
        return await assemble(
            instructions: instructions,
            labelByAddress: symbolLabels(in: machO),
            in: machO,
            functionFilter: functionFilter,
            objcIndex: objcIndex
        )
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
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        let labelByAddress = symbolLabels(in: machO)
        var foldedByAddress = foldedSymbolAddresses(in: machO)
        guard let text = textSectionBounds(in: machO) else { return [] }
        let textStart = text.address
        let textEnd = text.address + UInt64(text.size)

        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(labelByAddress.keys)
        boundarySet.formUnion(objcIndex.addresses)
        // `segment` starts the first function at the first decoded instruction
        // (the text start), even when that address is not itself a boundary.
        boundarySet.insert(textStart)
        let boundaries = boundarySet.filter { $0 >= textStart && $0 < textEnd }.sorted()
        guard !boundaries.isEmpty else { return [] }

        // Metadata names, on the same gate `assemble`/`matchedRanges` use.
        let unlabeled = Set(boundaries).subtracting(labelByAddress.keys)
        var metadataNames: [UInt64: String] = [:]
        if Double(unlabeled.count) > Double(max(boundaries.count, 1)) * 0.25 {
            let metadata = MetadataSymbolizer().functionNames(in: machO)
            metadataNames = metadata.unique
            Self.mergeMetadataFolds(metadata.folded, into: &foldedByAddress, labels: labelByAddress)
        }

        func span(_ index: Int) -> (start: UInt64, stop: UInt64) {
            (boundaries[index], index + 1 < boundaries.count ? boundaries[index + 1] : textEnd)
        }

        // Cross-function name index. `referenceIndex` and `swiftTargets` read only
        // name-level fields, so name-only stubs (no instructions) suffice.
        let stubs = boundaries.map {
            makeFunction(start: $0, instructions: [], labelByAddress: labelByAddress,
                         foldedByAddress: foldedByAddress,
                         metadataNames: metadataNames, objcIndex: objcIndex)
        }
        let cacheSymbols = CacheSymbolResolver(machO: machO)
        var names = referenceIndex(
            functions: stubs, labelByAddress: labelByAddress,
            metadataNames: metadataNames, objcIndex: objcIndex, in: machO
        )
        // Pass 1: gather cross-image call targets, one function's instructions at
        // a time, then resolve once — reproduces `crossImageNames` without holding
        // the whole image.
        var targets = Set<UInt64>()
        var indirectResultUses: [UInt64: IndirectResultUse] = [:]
        var registerSummaries: [UInt64: CalleeRegisterSummary] = [:]
        let functionStarts = Set(boundaries)
        let isFunction = { (target: UInt64) in functionStarts.contains(target) }
        let arity = { [names] target in
            self.knownArity(ofCallTarget: target, names: names, cacheSymbols: cacheSymbols, isFunction: isFunction)
        }
        let fileRanges = FileBackedRanges(standalone: machO)
        for index in boundaries.indices {
            // Muted: pass 2 decodes the same span again and records its events.
            let instructions = Probe.muted { capstoneInstructions(in: machO, span: span(index)) }
            collectUnnamedCallTargets(in: instructions, names: names, into: &targets)
            // The callee-side x8 fact every caller's analysis consults (see
            // `PerFunctionContext.indirectResultUses`); decoded here so pass 2
            // need not look ahead.
            if !instructions.isEmpty {
                let function = makeFunction(
                    start: boundaries[index], instructions: instructions,
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex
                )
                indirectResultUses[boundaries[index]] = Self.indirectResultUse(of: function)
                registerSummaries[boundaries[index]] = CalleeRegisterSummary.of(
                    Self.withJumpTables(function, machO: machO, ranges: fileRanges),
                    calleeArity: arity, isFunction: isFunction)
            }
        }
        // Reads first: whether a callee uses the caller's x29 is part of
        // the effect the clobber closure carries.
        CalleeRegisterSummary.closeOverReads(&registerSummaries)
        // Clobbers and reloads carried through calls; the few functions
        // whose callees change anything are decoded again.
        let spanIndex = Dictionary(boundaries.indices.map { (boundaries[$0], $0) }, uniquingKeysWith: { a, _ in a })
        CalleeRegisterSummary.closeOverCalls(&registerSummaries) { start, effects in
            guard let index = spanIndex[start] else { return nil }
            let instructions = Probe.muted { capstoneInstructions(in: machO, span: span(index)) }
            guard !instructions.isEmpty else { return nil }
            let function = makeFunction(
                start: start, instructions: instructions,
                labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                metadataNames: metadataNames, objcIndex: objcIndex
            )
            return Probe.muted {
                CalleeRegisterSummary.of(
                    Self.withJumpTables(function, machO: machO, ranges: fileRanges),
                    calleeEffects: effects, calleeArity: arity, isFunction: isFunction)
            }
        }
        names = resolveCrossImageNames(targets, into: names, resolver: cacheSymbols)
        CalleeRegisterSummary.closeOverFieldWrites(&registerSummaries) { names[$0] }
        let resolver = ReferenceResolver(
            names: names,
            stringRanges: stringSectionRanges(in: machO),
            machO: machO,
            demangleSymbol: { self.demangle($0) },
            selectors: ObjCSelectors.selectorTable(in: machO),
            cfStringRange: sectionRange(named: "__cfstring", in: machO),
            cacheSymbols: cacheSymbols,
            cacheReader: machO.fullCache.map { CacheReader(full: $0) },
            fileRanges: fileRanges,
            foldedCandidates: foldedByAddress,
            specializationSymbols: ReferenceResolver.specializationSymbols(
                labels: labelByAddress, names: names, folded: foldedByAddress)
        )

        var swiftTargets = Set(labelByAddress.compactMap { address, symbol in
            Self.isSwiftMangled(symbol) ? address : nil
        })
        swiftTargets.formUnion(metadataNames.keys)
        swiftTargets.formUnion(stubs.filter {
            $0.objcMethod == nil && (Self.isSwiftMangled($0.symbol) || $0.source == .metadata)
        }.map(\.startAddress))
        swiftTargets.formUnion(swiftStubAddresses(in: machO))
        swiftTargets.subtract(objcIndex.addresses)

        // Async funclet chains, from the hint sections plus a decode of just the
        // funclets' own spans, so the grouping costs no whole-image residency.
        let asyncIndex = asyncFuncletIndex(
            in: machO, boundaries: Set(boundaries),
            instructions: { self.decodeFunction(at: $0, boundaries: boundaries, in: machO) },
            nameOf: { names[$0] }
        )
        let enumCaseIndex = EnumCaseIndex.build(in: machO)
        let classTypeIndex = ClassTypeIndex.build(in: machO).adding(demangleCache.nominalTypes)
        // The chain pass decodes each chain's funclets once more, on demand, so
        // it still holds nothing beyond one chain at a time.
        let chainSlots = asyncChainSlots(
            index: asyncIndex,
            function: { address in
                let instructions = self.decodeFunction(at: address, boundaries: boundaries, in: machO)
                guard !instructions.isEmpty else { return nil }
                let function = makeFunction(
                    start: address, instructions: instructions,
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex
                )
                return asyncIndex.info(for: address, parentName: { names[$0] })
                    .map(function.attachingAsyncFunclet) ?? function
            },
            enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex
        )
        let context = PerFunctionContext(
            resolver: resolver, swiftTargets: swiftTargets, objcIndex: objcIndex,
            fieldMaps: (try? FieldMapBuilder.build(in: machO)) ?? [:],
            selfIndex: SelfTypeIndex.build(in: machO),
            vtableIndex: VTableIndex.build(in: machO),
            enumCaseIndex: enumCaseIndex,
            payloadEnumIndex: PayloadEnumCaseIndex.build(in: machO),
            classTypeIndex: classTypeIndex,
            indirectResultUses: indirectResultUses,
            registerSummaries: registerSummaries,
            asyncIndex: asyncIndex, asyncChainSlots: chainSlots
        )

        // Pass 2: decode each span, analyse, render, release. `segment` skips a
        // span that decodes to nothing, so this does too.
        var rendered: [T] = []
        rendered.reserveCapacity(boundaries.count)
        let total = boundaries.count
        for index in boundaries.indices {
            let instructions = capstoneInstructions(in: machO, span: span(index))
            if !instructions.isEmpty {
                let function = makeFunction(
                    start: boundaries[index], instructions: instructions,
                    labelByAddress: labelByAddress, foldedByAddress: foldedByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex
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

    /// Disassemble only the functions beginning at `addresses`, each decoded up
    /// to the next function boundary. Lets a caller classify a handful of
    /// Objective-C accessor IMPs without decoding the whole binary.
    public func disassembleFunctions(
        at addresses: Set<UInt64>,
        in machO: MachOFile
    ) async -> [DisassembledFunction] {
        guard !addresses.isEmpty else { return [] }
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(objcIndex.addresses)
        let boundaries = boundarySet.sorted()
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text" && $0.size > 0
        }) else { return [] }
        let textEnd = UInt64(text.address + text.size)

        let instructions = addresses.sorted().flatMap { start -> [Instruction] in
            let stop = boundaries.first(where: { $0 > start }) ?? textEnd
            guard stop > start else { return [] }
            return capstoneInstructions(in: machO, span: (start, stop))
        }
        guard !instructions.isEmpty else { return [] }
        return await assemble(
            instructions: instructions,
            labelByAddress: symbolLabels(in: machO),
            in: machO,
            functionFilter: nil,
            objcIndex: objcIndex
        )
    }

    // MARK: - Shared pipeline

    /// Segment the flat instruction stream into functions, name them, resolve
    /// operand references, and recover call arguments. Both front-ends — objdump
    /// (files) and Capstone (in-process/cache) — feed into this.
    private func assemble(
        instructions: [Instruction],
        labelByAddress: [UInt64: String],
        in machO: MachOFile,
        functionFilter: String?,
        objcIndex providedObjCIndex: ObjCMetadataIndex? = nil
    ) async -> [DisassembledFunction] {
        Probe.image(machO)
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

        // Addresses the linker folded multiple distinct symbols onto (see
        // `foldedSymbolAddresses`): computed from the symbol table, so it is the
        // same on both front-ends regardless of what labels either produced.
        var foldedByAddress = foldedSymbolAddresses(in: machO)
        Self.mergeMetadataFolds(metadataFolds, into: &foldedByAddress, labels: labelByAddress)

        var functions = segment(
            instructions,
            boundaries: boundaries,
            labelByAddress: labelByAddress,
            foldedByAddress: foldedByAddress,
            metadataNames: metadataNames,
            objcIndex: objcIndex
        )

        // Resolve adrp/add(+ldr) operand references to function, type-descriptor,
        // string, and Swift-symbol names, and name direct call/branch targets.
        let cacheSymbols = CacheSymbolResolver(machO: machO)
        let resolvedNames = crossImageNames(
            for: functions,
            names: referenceIndex(
                functions: functions, labelByAddress: labelByAddress,
                metadataNames: metadataNames, objcIndex: objcIndex, in: machO
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
            fileRanges: FileBackedRanges(standalone: machO),
            foldedCandidates: foldedByAddress,
            specializationSymbols: ReferenceResolver.specializationSymbols(
                labels: labelByAddress, names: resolvedNames, folded: foldedByAddress)
        )
        // Addresses whose callee uses the Swift calling convention, so `self` in
        // x20 is meaningful there.
        var swiftTargets = Set(labelByAddress.compactMap { address, symbol in
            Self.isSwiftMangled(symbol) ? address : nil
        })
        swiftTargets.formUnion(metadataNames.keys)
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
        let asyncIndex = asyncFuncletIndex(
            in: machO, boundaries: boundaries,
            instructions: { address in
                byStart[address]?.instructions
                    ?? self.decodeFunction(at: address, boundaries: sortedBoundaries, in: machO)
            },
            nameOf: { resolver.callTargetName(at: $0) }
        )
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
        let context = PerFunctionContext(
            resolver: resolver, swiftTargets: swiftTargets, objcIndex: objcIndex,
            fieldMaps: fieldMaps, selfIndex: selfIndex, vtableIndex: vtableIndex,
            enumCaseIndex: enumCaseIndex, payloadEnumIndex: payloadEnumIndex,
            classTypeIndex: classTypeIndex,
            indirectResultUses: Dictionary(
                functions.map { ($0.startAddress, Self.indirectResultUse(of: $0)) },
                uniquingKeysWith: { a, _ in a }
            ),
            registerSummaries: {
                let isFunction = { (target: UInt64) in boundaries.contains(target) }
                let arity = { target in
                    self.knownArity(
                        ofCallTarget: target, names: resolver.names, cacheSymbols: cacheSymbols, isFunction: isFunction)
                }
                // A summary reads a switch's `br` as the jump inside the body
                // it is, not as a tail call out of it.
                var bodies = Dictionary(
                    functions.map { ($0.startAddress, Self.withJumpTables($0, machO: machO, ranges: resolver.fileRanges)) },
                    uniquingKeysWith: { a, _ in a }
                )
                var summaries = Dictionary(
                    bodies.keys.sorted().compactMap { start in
                        bodies[start].flatMap { CalleeRegisterSummary.of($0, calleeArity: arity, isFunction: isFunction) }
                            .map { (start, $0) }
                    },
                    uniquingKeysWith: { a, _ in a }
                )
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
                        decoded += 1
                        let body = Self.withJumpTables(
                            DisassembledFunction(
                                symbol: "sub_\(String(target, radix: 16))", demangledName: nil,
                                startAddress: target, instructions: instructions, source: .address),
                            machO: machO, ranges: resolver.fileRanges)
                        bodies[target] = body
                        guard let summary = Probe.muted({
                            CalleeRegisterSummary.of(body, calleeArity: arity, isFunction: isFunction)
                        }) else { continue }
                        summaries[target] = summary
                        next.formUnion(summary.callees.filter { summaries[$0] == nil && boundaries.contains($0) })
                    }
                    level = next.sorted()
                }
                CalleeRegisterSummary.closeOverReads(&summaries)
                CalleeRegisterSummary.closeOverCalls(&summaries) { start, effects in
                    bodies[start].flatMap { function in
                        Probe.muted {
                            CalleeRegisterSummary.of(
                                function, calleeEffects: effects, calleeArity: arity, isFunction: isFunction)
                        }
                    }
                }
                CalleeRegisterSummary.closeOverFieldWrites(&summaries) { resolvedNames[$0] }
                return summaries
            }(),
            asyncIndex: asyncIndex, asyncChainSlots: chainSlots
        )
        functions = functions.map { analyzeFunction($0, context: context) }

        guard let needle = functionFilter?.lowercased(), !needle.isEmpty else {
            return functions
        }
        // A folded address declines to pick one of its symbols, so each of them
        // selects it: `-f` on any folded symbol printed "No function matched"
        // for a symbol the binary exports.
        return functions.filter {
            $0.symbol.lowercased().contains(needle)
                || ($0.demangledName?.lowercased().contains(needle) ?? false)
                || ($0.semanticName?.lowercased().contains(needle) ?? false)
                || ($0.foldedCandidates ?? []).contains { candidate in
                    candidate.lowercased().contains(needle)
                        || (self.demangle(candidate).map { self.matchesName($0, needle: needle) } ?? false)
                }
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
        /// Function start → whether its body reads the incoming x8, so a call to
        /// it is known to write (or not write) through the caller's x8.
        var indirectResultUses: [UInt64: IndirectResultUse] = [:]
        /// Function start → what its body proves about the registers a call to
        /// it reads and clobbers, for callees no signature describes.
        var registerSummaries: [UInt64: CalleeRegisterSummary] = [:]
        /// Async funclet chains and their suspension points.
        let asyncIndex: AsyncFuncletIndex
        /// Per resume funclet, the context-slot values definitely initialized
        /// before every entry suspension and stable throughout the chain.
        let asyncChainSlots: [UInt64: [Int: AbstractValue]]
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
    func decodeFunction(at address: UInt64, boundaries: [UInt64], in machO: MachOFile) -> [Instruction] {
        guard let text = textSectionBounds(in: machO) else { return [] }
        let textEnd = text.address + UInt64(text.size)
        guard address >= text.address, address < textEnd else { return [] }
        var low = 0, high = boundaries.count
        while low < high {
            let mid = (low + high) / 2
            if boundaries[mid] <= address { low = mid + 1 } else { high = mid }
        }
        let stop = low < boundaries.count ? boundaries[low] : textEnd
        return capstoneInstructions(in: machO, span: (address, stop))
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
        let tables = JumpTables.recognize(
            in: function, machO: context.resolver.machO, ranges: context.resolver.fileRanges)
        if !tables.isEmpty { function = function.attachingSwitchTargets(tables) }

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
            ? Self.selfType(of: function, selfIndex: context.selfIndex, fieldMaps: context.fieldMaps)
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
        } else if classSelfTypeName != nil {
            .swiftInstance(scalarArguments: Self.swiftScalarArgumentRegisters(of: function, enumCaseIndex: context.enumCaseIndex, classTypeIndex: context.classTypeIndex) ?? [:])
        } else if let scalarArgs = Self.swiftScalarArgumentRegisters(of: function, enumCaseIndex: context.enumCaseIndex, classTypeIndex: context.classTypeIndex) {
            .swiftFunction(scalarArguments: scalarArgs)
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
        let chainSlots = context.asyncChainSlots[function.startAddress] ?? [:]
        return enrichCallArguments(
            in: function, resolver: context.resolver, swiftTargets: context.swiftTargets,
            entry: asyncEntry ?? entry,
            fieldMap: fieldMap,
            objcFieldSyntax: objcMethod != nil || symbolEntry != nil,
            selfTypeName: selfTypeName, vtableIndex: context.vtableIndex,
            argumentFieldMaps: valueSelf?.argumentFieldMaps ?? [:],
            enumCaseIndex: context.enumCaseIndex,
            payloadEnumIndex: context.payloadEnumIndex,
            argumentEnumTypes: Self.swiftEnumArgumentTypes(of: function, enumCaseIndex: context.enumCaseIndex),
            boolArguments: Self.swiftBoolArgumentIndices(of: function).union(
                objcMethod.flatMap { ObjCArgumentABI.parameterTypes(encoding: $0.typeEncoding, argumentCount: $0.argumentCount) }
                    .map { types in Set(types.indices.filter { types[$0] == "B" }) } ?? []),
            classTypeIndex: context.classTypeIndex,
            indirectResultUse: context.indirectResultUses[function.startAddress]
                ?? Self.indirectResultUse(of: function),
            typeFieldMaps: context.fieldMaps,
            calleeConventions: Self.calleeResultConventions(
                in: function, indirectResultUses: context.indirectResultUses,
                resolver: context.resolver, fieldMaps: context.fieldMaps,
                classTypeIndex: context.classTypeIndex
            ),
            asyncContextSlots: chainSlots,
            asyncSuspensions: Self.asyncSuspensionNotes(in: function, index: context.asyncIndex),
            objcIndex: context.objcIndex,
            registerSummaries: context.registerSummaries
        )
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
        for (entry, chain) in index.chains {
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
                let analysis = tracer.analyze(funclet, entry: convention)
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
                    AsyncContextEscapes().lowestOffset(in: funclet, terminalBranches: terminalBranches)
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

    /// `(vmaddr, size)` of the `__text` section.
    private func textSectionBounds(in machO: MachOFile) -> (address: UInt64, size: Int)? {
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text"
        }) else { return nil }
        return (UInt64(text.address), text.size)
    }

    /// Decode `__text`, or just the `[start, stop)` slice of it, in-process with
    /// Capstone. Restricting to a span is what makes `disasm --function` fast on
    /// a large binary — only the matched function's code is decoded, not the
    /// whole text section.
    private func decodeText(
        in machO: MachOFile, span: (start: UInt64, stop: UInt64)?, includeText: Bool = true
    ) -> [DecodedInstruction] {
        guard let engine = CapstoneEngine(), let text = textSectionBounds(in: machO) else { return [] }
        let start: UInt64
        let size: Int
        if let span {
            let lo = max(span.start, text.address)
            let hi = min(span.stop, text.address + UInt64(text.size))
            guard hi > lo else { return [] }
            start = lo
            size = Int(hi - lo)
        } else {
            start = text.address
            size = text.size
        }
        guard let bytes = sectionBytes(address: start, size: size, in: machO) else { return [] }
        return engine.disassemble(bytes, address: start, includeText: includeText)
    }

    /// Decode `__text` (or `span`) into an ordered instruction stream carrying
    /// text, control-flow class, and branch target.
    private func capstoneInstructions(in machO: MachOFile, span: (start: UInt64, stop: UInt64)? = nil) -> [Instruction] {
        decodeText(in: machO, span: span).map { decoded in
            Instruction(
                address: decoded.address,
                text: decoded.text,
                annotation: nil,
                controlFlow: decoded.controlFlow,
                branchTarget: decoded.branchTarget,
                detail: decoded.detail
            )
        }
    }

    /// Raw bytes of an arbitrary section span (`__text`, `__objc_stubs`, …).
    ///
    /// For a plain file, read through the image reader. For a dyld-cache image
    /// the code usually lives in a *different* subcache file than the image
    /// header, and MachOKit's image reader only reaches the header's subcache —
    /// so locate the subcache that maps the section's VM address and read that
    /// subcache file directly.
    private func sectionBytes(address: UInt64, size: Int, in machO: MachOFile) -> Data? {
        if let full = machO.fullCache,
           let fullOffset = full.fileOffset(of: address),
           let subcache = full.cache(forFileOffset: fullOffset),
           let url = full.url(forFileOffset: fullOffset),
           let localOffset = subcache.fileOffset(of: address),
           let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: localOffset)
                return try handle.read(upToCount: size)
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
    private func knownArity(
        ofCallTarget target: UInt64, names: [UInt64: String], cacheSymbols: CacheSymbolResolver?,
        isFunction: (UInt64) -> Bool
    ) -> Int? {
        let name = names[target] ?? cacheSymbols?.name(forCallTarget: target).map {
            demangle($0) ?? Self.stripLeadingUnderscore($0)
        }
        guard let name else { return nil }
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
        guard let table = machO.indirectSymbols else { return [:] }
        let indirect = Array(table)
        let symbols = Array(machO.symbols)
        var names: [UInt64: String] = [:]

        for section in machO.sections where section.flags.type == .symbol_stubs {
            guard let first = section.indirectSymbolIndex,
                  let count = section.numberOfIndirectSymbols,
                  count > 0, first >= 0, first + count <= indirect.count
            else { continue }
            let stubSize = section.size / count
            guard stubSize > 0 else { continue }

            for slot in 0..<count {
                guard let symbolIndex = indirect[first + slot].index,
                      symbols.indices.contains(symbolIndex)
                else { continue }
                let raw = symbols[symbolIndex].name
                guard !raw.isEmpty else { continue }
                let address = UInt64(section.address + slot * stubSize)
                names[address] = raw
            }
        }
        return names
    }

    /// Function labels from the symbol table: `__text`-range defined symbols,
    /// keyed by VM address. Present even in dyld-cache images (exports), and a
    /// no-op when the symbol table is stripped.
    private func symbolLabels(in machO: MachOFile) -> [UInt64: String] {
        // Restrict to the __text VM range so a defined-symbol's offset that maps
        // outside code (a mis-typed symbol) can't mislabel a function.
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text"
        }) else { return [:] }
        let textRange = UInt64(text.address) ..< UInt64(text.address + text.size)

        // MachOKit's `Symbol.offset` is the nlist `n_value` — for a defined
        // symbol that's its (unslid) VM address, the same space as instruction
        // addresses and LC_FUNCTION_STARTS. (Undefined symbols have n_value 0,
        // which the __text-range filter drops.)
        var labels: [UInt64: String] = [:]
        for symbol in machO.symbols where !symbol.name.isEmpty {
            let address = UInt64(symbol.offset)
            if textRange.contains(address), labels[address] == nil {
                labels[address] = symbol.name
            }
        }
        return labels
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
    static func mergeMetadataFolds(
        _ folds: [UInt64: [String]], into folded: inout [UInt64: [String]], labels: [UInt64: String]
    ) {
        for (address, candidates) in folds where labels[address] == nil && folded[address] == nil {
            folded[address] = candidates
        }
    }

    private func foldedSymbolAddresses(in machO: MachOFile) -> [UInt64: [String]] {
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text"
        }) else { return [:] }
        let textRange = UInt64(text.address) ..< UInt64(text.address + text.size)

        var namesByAddress: [UInt64: Set<String>] = [:]
        for symbol in machO.symbols where !symbol.name.isEmpty {
            let address = UInt64(symbol.offset)
            guard textRange.contains(address) else { continue }
            namesByAddress[address, default: []].insert(symbol.name)
        }
        return namesByAddress
            .filter { $0.value.count >= 2 }
            .mapValues { $0.sorted() }
    }

    // MARK: - Segmentation

    private func segment(
        _ instructions: [Instruction],
        boundaries: Set<UInt64>,
        labelByAddress: [UInt64: String],
        foldedByAddress: [UInt64: [String]],
        metadataNames: [UInt64: String],
        objcIndex: ObjCMetadataIndex
    ) -> [DisassembledFunction] {
        var functions: [DisassembledFunction] = []
        var current: [Instruction] = []
        var start: UInt64 = instructions.first?.address ?? 0

        func flush() {
            guard !current.isEmpty else { return }
            functions.append(makeFunction(start: start, instructions: current,
                                           labelByAddress: labelByAddress,
                                           foldedByAddress: foldedByAddress,
                                           metadataNames: metadataNames,
                                           objcIndex: objcIndex))
            current = []
        }

        for insn in instructions {
            // A boundary (other than the very first instruction) cuts a function.
            if boundaries.contains(insn.address), !current.isEmpty {
                flush()
                start = insn.address
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
        objcIndex: ObjCMetadataIndex
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
            return DisassembledFunction(
                symbol: subName,
                demangledName: demangleCache.presentation(of: metaName),
                startAddress: start,
                instructions: instructions,
                source: .metadata,
                semanticName: metaName
            )
        }
        return DisassembledFunction(
            symbol: subName,
            demangledName: nil,
            startAddress: start,
            instructions: instructions,
            source: .address
        )
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
    private func functionStarts(of machO: MachOFile) -> [UInt64] {
        guard let starts = machO.functionStarts else { return [] }
        var seen: Set<UInt64> = []
        return starts.compactMap { entry in
            let address = UInt64(entry.offset)
            return seen.insert(address).inserted ? address : nil
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
    private func objdumpInstructions(
        _ args: [String], machO: MachOFile
    ) throws -> (instructions: [Instruction], labels: [UInt64: String]) {
        let result = try Shell.xcrun("llvm-objdump", args)
        guard result.status == 0 else {
            throw DisassembleError.toolFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        let (parsed, labelByAddress) = parseObjdump(result.stdout)
        if parsed.isEmpty {
            let knownStarts = functionStarts(of: machO).count
            guard knownStarts == 0 else {
                throw DisassembleError.parsedNothing(
                    lines: result.stdout.split(separator: "\n").count,
                    knownStarts: knownStarts
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
        guard let text = textSectionBounds(in: machO) else { return [] }
        let textEnd = text.address + UInt64(text.size)
        var targets = Set<UInt64>()
        // A tail branch to a function start is a call too: its callee's body
        // bounds the arguments it renders (`b bump` after `printf`).
        for insn in instructions where insn.controlFlow == .call || insn.controlFlow == .branch {
            guard let target = insn.branchTarget, boundarySet.contains(target),
                  target >= text.address, target < textEnd,
                  !covered.contains(where: { $0.start <= target && target < $0.stop })
            else { continue }
            targets.insert(target)
        }
        return targets.sorted().map { start in
            let next = boundaries.firstIndex(of: start).map { $0 + 1 }
            let stop = next.flatMap { $0 < boundaries.count ? boundaries[$0] : nil } ?? textEnd
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

        let textEnd = textSectionBounds(in: machO).map { $0.address + UInt64($0.size) }
            ?? (boundaries.last! + 0x4000)

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

        var selected = Set(boundaries.filter(matches))
        guard !selected.isEmpty else { return [] }
        for start in selected {
            if let chain = asyncIndex.chains[start] { selected.formUnion(chain) }
        }

        var ranges: [(start: UInt64, stop: UInt64)] = []
        for (index, start) in boundaries.enumerated() where selected.contains(start) {
            let stop = index + 1 < boundaries.count ? boundaries[index + 1] : textEnd
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
        in machO: MachOFile
    ) -> [UInt64: String] {
        var names: [UInt64: String] = [:]
        // Keep the whole image's lightweight symbol/metadata index even when a
        // filtered disassembly decoded only one function. Its direct and
        // indirect calls can still target any other known function.
        //
        // Folded addresses are intentionally still named here: a metadata-resolved
        // edge (a concrete witness-table or vtable dispatch) reaches its target
        // through a specific type, so one of the folded symbols is the right label
        // for that edge, and suppressing it loses a real call graph edge. The fold
        // is declined where it matters — the function *heading* (see `makeFunction`).
        for (address, symbol) in labelByAddress {
            names[address] = objcIndex.binding(for: address)?.displayName
                ?? demangle(symbol)
                ?? Self.stripLeadingUnderscore(symbol)
        }
        for (address, name) in metadataNames where names[address] == nil {
            names[address] = name
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
        for type in (try? machO.swift.types) ?? [] {
            let offset: Int
            let name: String?
            switch type {
            case .enum(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            case .struct(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            case .class(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            }
            if let name {
                names[machO.address(forOffset: offset)] = "type descriptor for \(name)"
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

        return function.replacingInstructions(updated)
    }

    /// Annotate direct call/branch instructions with their resolved target
    /// name (`→ Type.method`). objdump already names file-mode calls in the
    /// instruction text (via stubs); this fills the in-process (Capstone) path,
    /// where the operand is a bare `#0x…` address — so calls to another function
    /// in the same image read by name and flow into `--pseudo`.
    private func annotateCallTargets(
        in function: DisassembledFunction,
        resolver: ReferenceResolver
    ) -> DisassembledFunction {
        let branchFlows: Set<ControlFlow> = [.call, .branch, .conditionalBranch]
        let instructions = function.instructions.map { insn -> Instruction in
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
        return function.replacingInstructions(instructions)
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
        vtableIndex: VTableIndex = VTableIndex()
    ) -> DisassembledFunction {
        /// Resolve a `blr` target to a (name, address). A class vtable dispatch is
        /// resolved through the class's metadata layout; anything else through the
        /// generic indirect-target resolver.
        func resolve(_ value: AbstractValue) -> (address: UInt64?, name: String, isSelfDispatch: Bool)? {
            if case .selfVTableMethod(let offset) = value,
               let selfTypeName,
               let address = vtableIndex.methodAddress(type: selfTypeName, offset: offset),
               let name = resolver.name(at: address, ownedBy: selfTypeName) {
                return (address, name, true)
            }
            return resolver.indirectCallTarget(for: value).map { ($0.address, $0.name, false) }
        }
        let ownAddresses = Set(function.instructions.map(\.address))
        let instructions = function.instructions.map { insn -> Instruction in
            guard insn.branchTarget == nil,
                  insn.controlFlow == .call || insn.controlFlow == .branch,
                  let value = targets[insn.address],
                  let resolved = resolve(value)
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
            var facts = insn.facts
            facts.isSelfDispatch = resolved.isSelfDispatch
            return Instruction(
                address: insn.address, text: insn.text, annotation: annotation,
                controlFlow: insn.controlFlow, branchTarget: target,
                callArguments: insn.callArguments, callSelf: insn.callSelf,
                resultConsumed: insn.resultConsumed, sourceType: insn.sourceType,
                detail: insn.detail, callee: .kept(parsed == named ? named : parsed), facts: facts
            )
        }
        return function.replacingInstructions(instructions)
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
        /// File-backed byte ranges of a standalone image; nil inside a cache.
        var fileRanges: FileBackedRanges?
        /// Every name identical code folding put at an address (symbols or
        /// metadata candidates). `names` holds one of them; a consumer that knows
        /// which owner it reached the address through picks from these instead.
        var foldedCandidates: [UInt64: [String]] = [:]
        /// The mangled symbol of each generic specialization in the image, by
        /// address, so a call to one can be laid out from its substituted
        /// signature (`specializedSignature`). An address the linker folded
        /// several symbols onto has none: the bodies of `bump<Int>` and
        /// `bump<UInt>` can be one, and the symbol there names either.
        var specializationSymbols: [UInt64: String] = [:]

        /// The substituted signature of the specialization a call to `target`
        /// names, when its symbol proves one.
        func specializedSignature(at target: UInt64, printedName: String) -> String? {
            guard printedName.hasPrefix("generic specialization <"), let symbol = specializationSymbols[target]
            else { return nil }
            return DisassembledFunction.specializedSignature(symbol: symbol, printedName: printedName)
        }

        static func specializationSymbols(
            labels: [UInt64: String], names: [UInt64: String], folded: [UInt64: [String]]
        ) -> [UInt64: String] {
            var symbols: [UInt64: String] = [:]
            for (address, name) in names where name.hasPrefix("generic specialization <") {
                guard (folded[address]?.count ?? 0) <= 1, let symbol = labels[address] else { continue }
                symbols[address] = symbol
            }
            return symbols
        }

        /// The candidate at `address` that belongs to `typeName` (its simple
        /// name is a component of the member's qualified context), or nil. At a
        /// folded address `names` holds an arbitrary owner's symbol.
        func name(at address: UInt64, ownedBy typeName: String) -> String? {
            let candidates = (foldedCandidates[address] ?? []).map { demangleSymbol($0) ?? $0 }
                + [name(at: address)].compactMap { $0 }
            return candidates.first { Self.isMember($0, of: typeName) }
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
                    if let name = callTargetName(at: target)
                        ?? cacheSymbols?.name(forCallTarget: target) {
                        return (target, name)
                    }
                }
                return loadedName(at: slot).map { (nil, $0) }
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
            guard let mapping = machO.fullCache?.mappingAndSlideInfo(for: slot) else { return false }
            return !mapping.flags.isDisjoint(with: [.constData, .readOnlyData, .constTproData])
        }

        /// VM address held by a rebased pointer slot. Full-dyld-cache and
        /// standalone Mach-O resolvers intentionally return different spaces.
        private func pointerTarget(at slot: UInt64) -> UInt64? {
            if let full = machO.fullCache,
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

        /// A C string's text for a rendered literal: printable ASCII only,
        /// escaped, and cut after 48 characters with `…`, which no such string
        /// contains. Nil for an empty string or any other byte.
        static func printableLiteralText(_ s: String) -> String? {
            guard !s.isEmpty, s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7f }) else { return nil }
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
        private var rebases: [UInt64: UInt64] = [:]
        private var built = false

        func symbol(at fileOffset: UInt64, in machO: MachOFile) -> String? {
            lock.lock()
            defer { lock.unlock() }
            build(machO)
            return binds[fileOffset]
        }

        func rebaseTarget(at fileOffset: UInt64, in machO: MachOFile) -> UInt64? {
            lock.lock()
            defer { lock.unlock() }
            build(machO)
            return rebases[fileOffset]
        }

        private func build(_ machO: MachOFile) {
            guard !built else { return }
            built = true
            guard let fixups = machO.dyldChainedFixups, let startsInImage = fixups.startsInImage else { return }
            let imports = fixups.imports
            var seen: Set<UInt64> = []
            for segment in fixups.startsInSegments(of: startsInImage) {
                for pointer in fixups.pointers(of: segment, in: machO) {
                    let offset = UInt64(pointer.offset)
                    guard seen.insert(offset).inserted else { continue }
                    if pointer.fixupInfo.rebase != nil {
                        if let target = pointer.rebaseTargetRuntimeOffset(for: machO) { rebases[offset] = target }
                    } else if pointer.fixupInfo.bind != nil,
                              let (ordinal, _) = pointer.bindOrdinalAndAddend(for: machO),
                              imports.indices.contains(ordinal),
                              let name = fixups.symbolName(for: imports[ordinal].info.nameOffset) {
                        binds[offset] = name
                    }
                }
            }
        }
    }

    /// Run value tracking on a function and append recovered call arguments
    /// (`args(…)`) to each call instruction.
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
        fieldMaps: [String: FieldMap]
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
        guard let fromSymbol = selfTypeFromDemangledName(function.analysisName),
              resolves(fromSymbol)
        else { return nil }
        return fromSymbol
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
        let accessors: Set<String> = ["getter", "setter", "modify", "read", "init", "deinit"]
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
        guard function.objcMethod == nil, let name = function.analysisName else { return nil }
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
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> SwiftReturnRegister? {
        guard let returnType = Self.swiftReturnTypeName(of: function) else { return nil }
        // The printed type is not the ABI. A closure reabstracted to a generic
        // convention returns even a one-word value through the x8 buffer, and
        // its x0 at `ret` is then whatever the last call left there (measured:
        // a `Dictionary.Values` closure in libswiftObservation rendered
        // `return Dictionary.removeAll(0)`).
        if Self.readsIncomingIndirectResult(function) { return nil }
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
        enumCaseIndex: EnumCaseIndex = EnumCaseIndex(), classTypeIndex: ClassTypeIndex = ClassTypeIndex()
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
              let name = function.analysisName,
              let caller = DisassembledFunction.splitSignature(name), !caller.isAsync, !caller.isThrowing,
              ordinaryHead(caller.head),
              swiftReturnRegister(of: function, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) != nil
        else { return [] }
        return Set(function.instructions.compactMap { insn in
            guard insn.controlFlow == .branch,
                  insn.branchTarget.map({ $0 < first.address || $0 > last.address }) ?? true,
                  let name = DisassembledFunction.calleeName(of: insn),
                  let callee = DisassembledFunction.splitSignature(name), !callee.isAsync, !callee.isThrowing,
                  caller.result == callee.result, ordinaryHead(callee.head)
            else { return nil }
            return insn.address
        })
    }

    static func swiftReturnRegister(
        forReturnType returnType: String, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> SwiftReturnRegister? {
        // Double/Float come back in v0 (d0/s0).
        let floatingTypes: Set<String> = [
            "Swift.Double", "Swift.Float", "Swift.Float16", "Swift.Float32",
            "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat",
        ]
        if floatingTypes.contains(returnType) { return .floating }
        // An optional of a value type marks nil outside x0: a tag in x1 (`Int?`)
        // or an extra inhabitant of the payload (`3` for a three-case enum).
        // Read alone, x0 printed nil as `0`. Only a pointer or class payload,
        // whose nil is the null pointer, is the one register.
        if let payload = Self.optionalPayload(returnType) {
            return Self.isSingleRegisterPointer(payload) || classTypeIndex.isClass(payload)
                || payload == "Swift.AnyObject" ? .integer : nil
        }
        // A printed nominal type does not determine its register class: a
        // one-Double struct returns in v0, a two-word struct in x0 and x1, a
        // larger one through x8. Read x0 only for layouts the signature or the
        // image's metadata proves are one integer register. Defaulting every
        // other type to x0 rendered a stale register as the result
        // (`abiOneDoubleFromInt` returned its callee's Int; recovered from the
        // pre-merge stash 983aa25 with its ABISource execution oracle).
        let integerTypes: Set<String> = [
            "Swift.Bool", "Swift.Int", "Swift.UInt", "Swift.Int8", "Swift.UInt8",
            "Swift.Int16", "Swift.UInt16", "Swift.Int32", "Swift.UInt32",
            "Swift.Int64", "Swift.UInt64",
        ]
        if integerTypes.contains(returnType) || Self.isSingleRegisterPointer(returnType)
            || returnType == "Swift.AnyObject"
            // Array's native value is one storage pointer.
            || (returnType.hasPrefix("Swift.Array<") && returnType.hasSuffix(">"))
            || enumCaseIndex.isNoPayloadEnum(returnType) || classTypeIndex.isClass(returnType) {
            return .integer
        }
        return nil
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
    static func readsIncomingIndirectResult(_ function: DisassembledFunction) -> Bool {
        indirectResultUse(of: function) == .reads
    }

    /// The register→source-argument-index map to seed for a Swift free function
    /// or static method whose every parameter is a single-register scalar. In the
    /// Swift calling convention integer/pointer parameters fill x0… and
    /// floating-point ones fill v0… by independent counters, so the two are
    /// tracked separately. Nil for any signature with an aggregate, generic,
    /// `inout`, `String`, or otherwise multi-register parameter (or none), so a
    /// register is never mislabeled `arg k` when the real layout differs.
    static func swiftScalarArgumentRegisters(
        of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> [String: Int]? {
        guard function.objcMethod == nil, let name = function.analysisName,
              Self.isSwiftMangled(function.symbol),
              // A getter/setter/accessor or a name without a call signature has no
              // ordinary parameter list to seed.
              let signature = DisassembledFunction.splitSignature(name)?.head
        else { return nil }
        guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: signature)
        else { return nil }
        let parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        guard !parameters.isEmpty else { return nil }

        var registers: [String: Int] = [:]
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
            case nil:
                return nil // not provably single-register — seed nothing
            }
        }
        return registers
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

    /// Whether a property getter takes nothing in x0–x7: a static property's
    /// (the metatype rides in x20), a class instance property's (self in
    /// x20) or a global's. A value type's instance getter does not qualify,
    /// since a small struct's `self` travels in x0 onward. Subscripts take
    /// their index. Generic metadata, which a getter may also receive, is
    /// plumbing the renderer hides anyway.
    static func getterTakesNoArguments(_ callee: String, classTypeIndex: ClassTypeIndex) -> Bool {
        // A specialization of a qualifying getter only drops or re-owns
        // parameters (`<Arg[0] = Dead>` is the unused metatype).
        var name = callee
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
        guard !base.isEmpty, base.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
              let dot = base.lastIndex(of: "."), !base[base.index(after: dot)...].isEmpty
        else { return false }
        let context = String(base[..<dot])
        return isStatic || !context.contains(".") || classTypeIndex.isClass(context)
    }

    /// Each source parameter's register bank, how many registers of it the
    /// parameter takes, and its demangled type. A scalar takes one; so does an
    /// `inout` parameter of any type, which is passed as its address. A
    /// `String` takes two integer registers (count and flags, then the object),
    /// and so does a `String?`, whose nil is an extra inhabitant
    /// (`takeOptString(nil, 7)` passes 0 in x0 and x1, 7 in x2). Any other
    /// parameter declines the whole layout, and so does a typed throw, whose
    /// error may travel through an extra pointer parameter.
    static func swiftCallArgumentSlots(
        callee: String, enumCaseIndex: EnumCaseIndex, classTypeIndex: ClassTypeIndex
    ) -> [(kind: ScalarParameterClass, registers: Int, type: String)]? {
        guard let signature = DisassembledFunction.splitSignature(callee), !signature.isAsync,
              let range = DisassembledFunction.outermostArgumentListRange(of: signature.head)
        else { return nil }
        var name = Substring(Self.withoutPrivateDiscriminators(String(signature.head[..<range.lowerBound].dropLast())))
        let isStatic = name.hasPrefix("static ")
        if isStatic { name = name.dropFirst("static ".count) }
        // An ordinary qualified identifier only: no generic clause, no
        // `closure #1 in`, `specialization <…> of`, `(X in _HASH)` or thunk prose.
        guard !name.isEmpty,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
              let dot = name.lastIndex(of: ".")
        else { return nil }
        let context = String(name[..<dot]), member = name[name.index(after: dot)...]
        let isFreeFunction = !context.contains(".")
        guard isFreeFunction || isStatic || member == "init" || classTypeIndex.isClass(context)
        else { return nil }

        let parameters = DisassembledFunction.splitTopLevelArguments(signature.head[range])
        var layout: [(kind: ScalarParameterClass, registers: Int, type: String)] = []
        var integers = 0, floats = 0
        for parameter in parameters {
            let type = parameterType(parameter)
            let kind: ScalarParameterClass, registers: Int
            if let scalar = scalarParameterClass(parameter, enumCaseIndex: enumCaseIndex,
                                                 classTypeIndex: classTypeIndex) {
                (kind, registers) = (scalar, 1)
            } else if signature.thrownType == nil, let words = integerRegisterFootprint(ofParameterType: type) {
                (kind, registers) = (.integer, words)
            } else {
                return nil
            }
            switch kind {
            case .integer: integers += registers
            case .floating: floats += registers
            }
            guard integers <= 8, floats <= 8 else { return nil }
            layout.append((kind, registers, type))
        }
        return layout
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
    static let twoWordStringTypes: Set<String> = ["Swift.String", "Swift.Optional<Swift.String>", "Swift.String?"]
    /// The same types as a field record's mangled names spell them.
    static let twoWordStringMangledTypes: Set<String> = ["SS", "SSSg"]

    /// The integer registers a parameter that is not a scalar takes, for the
    /// shapes whose footprint the Swift ABI fixes whatever the image holds:
    /// an `inout` address, a String's two words and an Optional scalar's
    /// payload and tag. Nil for anything else.
    static func integerRegisterFootprint(ofParameterType type: String) -> Int? {
        if type.hasPrefix("inout "), type.count > "inout ".count { return 1 }
        if twoWordStringTypes.contains(type) { return 2 }
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
        guard function.objcMethod == nil, let name = function.analysisName,
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
        guard function.objcMethod == nil, let name = function.analysisName,
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
        guard function.objcMethod == nil, let name = function.analysisName,
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
    static func renderImmediate(_ v: UInt64) -> String {
        if v < 4096 { return String(v) }
        let signed = Int64(bitPattern: v)
        if signed < 0, signed >= -0x1_0000 { return String(signed) }
        return "0x" + String(v, radix: 16)
    }

    /// Name a loop-carried induction variable by id — `i`, `j`, `k`, then `i3`, …
    /// (skips `l`/`m`/`n`, which read poorly next to `1` and common loop bounds).
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
        if floatingSelfOffsets != nil {
            // Seeded after the formal arguments, below.
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
    private static func parameterType(_ parameter: String) -> String {
        if let colon = parameter.range(of: ": ", options: .backwards) {
            return String(parameter[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return parameter.trimmingCharacters(in: .whitespaces)
    }

    /// A field map for a demangled type name, trying the qualified name then its
    /// last (unqualified) component, since `FieldMap` is keyed unqualified.
    /// A qualified type name requires its own descriptor's map; simple keys
    /// serve genuinely unqualified names.
    private static func namedFieldMap(_ typeName: String, in fieldMaps: [String: FieldMap]) -> FieldMap? {
        fieldMaps[typeName]
    }

    enum ScalarParameterClass { case integer, floating }

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
        type = type.trimmingCharacters(in: .whitespaces)
        let floating: Set<String> = [
            "Swift.Double", "Swift.Float", "Swift.Float16", "Swift.Float32",
            "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat",
        ]
        if floating.contains(type) { return .floating }
        let integers: Set<String> = [
            "Swift.Int", "Swift.UInt", "Swift.Int8", "Swift.Int16", "Swift.Int32",
            "Swift.Int64", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
            "Swift.Bool", "Swift.OpaquePointer", "Swift.UnsafeRawPointer",
            "Swift.UnsafeMutableRawPointer",
        ]
        if integers.contains(type) { return .integer }
        if Self.isSingleRegisterPointer(type) { return .integer }
        // A pointer optional is nil-or-a-pointer in ONE register (nil == 0), so it
        // seeds like a scalar — which is what lets `x ?? f` over a pointer optional
        // reconstruct via the `cbz`/diamond select. A tagged optional (`Int?`,
        // multi-register) is deliberately NOT matched here.
        if type.hasPrefix("Swift.Optional<"), type.hasSuffix(">") {
            let inner = String(type.dropFirst("Swift.Optional<".count).dropLast())
            if Self.isSingleRegisterPointer(inner) { return .integer }
        }
        // A reference (class) optional is also nil-or-a-pointer in ONE register
        // (nil == 0), so it seeds like a scalar — which lets `r != nil` / `r ?? x`
        // reconstruct. A value-typed (tagged) optional is not a class and stays
        // unseeded here.
        if classTypeIndex.isClass(type) || classTypeIndex.referenceOptionalInner(type) != nil { return .integer }
        // A no-payload enum is a trivial integer tag in one register, so it seeds
        // like a scalar — which is what lets `c == .case` over an enum parameter
        // reconstruct. Payload enums are absent from the index and stay unseeded.
        if enumCaseIndex.isNoPayloadEnum(type) { return .integer }
        return nil
    }

    /// A single-register pointer type (nil-representable as 0).
    private static func isSingleRegisterPointer(_ type: String) -> Bool {
        ["Swift.OpaquePointer", "Swift.UnsafeRawPointer", "Swift.UnsafeMutableRawPointer"]
            .contains(type)
            || type.hasPrefix("Swift.UnsafePointer<")
            || type.hasPrefix("Swift.UnsafeMutablePointer<")
    }

    private func enrichCallArguments(
        in function: DisassembledFunction,
        resolver: ReferenceResolver,
        swiftTargets: Set<UInt64>,
        entry: MethodEntryConvention?,
        fieldMap: FieldMap?,
        objcFieldSyntax: Bool,
        selfTypeName: String? = nil,
        vtableIndex: VTableIndex = VTableIndex(),
        argumentFieldMaps: [Int: FieldMap] = [:],
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
        registerSummaries: [UInt64: CalleeRegisterSummary] = [:]
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

        /// Render a by-value struct argument's field — `arg1.y` — from the
        /// parameter's own field map, falling back to a byte offset.
        func argumentFieldName(argument: Int, offset: Int) -> String {
            if case .success(let hit)? = argumentFieldMaps[argument]?.lookup(offset: offset, bytes: 1) {
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
            return resolver.name(at: address, ownedBy: selfTypeName)
        }

        /// `self`'s own getters/setters, keyed by resolved method name, so a
        /// vtable dispatch to one renders as `self.property` (or `self.property =`)
        /// instead of `Type.property.getter(…)` with stale argument registers.
        let selfAccessors: [String: (property: String, isGetter: Bool)] = {
            guard let selfTypeName else { return [:] }
            var map: [String: (String, Bool)] = [:]
            for address in vtableIndex.methodAddresses(type: selfTypeName) {
                guard let name = resolver.name(at: address, ownedBy: selfTypeName),
                      let access = DisassembledFunction.swiftAccessorProperty(name)
                else { continue }
                map[name] = access
            }
            return map
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

        func sanitize(_ values: [AbstractValue]) -> [AbstractValue]? {
            ValueTracer.trimTrailingUnknown(values.map(sanitizeValue))
        }

        var tracer = ValueTracer(calleeConventions: calleeConventions, asyncContextSlots: asyncContextSlots)
        tracer.callFactsCache = callFactsCache
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
        /// The name a call's arguments are laid out by: for a generic
        /// specialization its substituted signature, which says what the
        /// printed `A` is. `bump<Double>(d)` passes d in d0, and read from its
        /// printed `(A)` it rendered `bump(arg1)`, the Int then in x0.
        func layoutName(at address: UInt64, callee: String) -> String {
            callTargets[address].flatMap { resolver.specializedSignature(at: $0, printedName: callee) } ?? callee
        }
        for insn in function.instructions where insn.controlFlow == .call || insn.controlFlow == .branch {
            guard let target = insn.branchTarget, registerSummaries[target] != nil else { continue }
            // A tail branch passes its arguments the same way a call does.
            callTargets[insn.address] = target
            if insn.controlFlow == .call, let clobbered = registerSummaries[target]?.clobberedCalleeSaved,
               !clobbered.isEmpty {
                tracer.calleeClobbers[target] = clobbered
            }
            if registerSummaries[target]?.writesNoFields == true { tracer.fieldPreservingCallees.insert(target) }
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
        var analysis = tracer.analyze(function, entry: entry)
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
        let function = annotateIndirectControlFlowTargets(
            in: function, targets: analysis.indirectControlFlowTargets,
            resolver: resolver, selfTypeName: selfTypeName, vtableIndex: vtableIndex
        )
        // Vtable targets become named only after the first trace. A newly
        // resolved setter must invalidate its result before downstream values
        // are recovered; rendering-time suppression leaves fabricated values
        // inside later expressions.
        let resolvedVoidCalls = Set(function.instructions.compactMap { insn -> UInt64? in
            guard insn.controlFlow == .call,
                  let callee = DisassembledFunction.calleeName(of: insn),
                  DisassembledFunction.swiftAccessorProperty(callee)?.isGetter == false
            else { return nil }
            return insn.address
        })
        if !resolvedVoidCalls.isEmpty {
            tracer.voidCallSites = resolvedVoidCalls
            analysis = Probe.muted { tracer.analyze(function, entry: entry) }
        }
        Probe.observe(analysis, of: function)
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
        func isReturn(_ insn: Instruction) -> Bool {
            insn.controlFlow == .return || asyncReturns.contains(insn.address)
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
        for insn in function.instructions
        where insn.controlFlow == .call || insn.controlFlow == .branch {
            guard sites[insn.address] == nil,
                  let callee = DisassembledFunction.calleeName(of: insn)
            else { continue }
            // So does an in-image callee whose body itself reads an
            // argument register: `readsFirst(?)`, not `readsFirst()`, when
            // its argument was loaded through an unknown pointer.
            guard DisassembledFunction.knownCArity(of: callee) != nil
                    || Self.swiftCallArgumentSlots(
                        callee: layoutName(at: insn.address, callee: callee),
                        enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex
                    )?.isEmpty == false
                    || (insn.branchTarget.flatMap { registerSummaries[$0] }?.provenArgumentCount ?? 0) > 0
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
            // Do not run unrelated enrichment when only this contract is known.
            guard function.hasProvenMachineValueReturn else { return function }
            let type = DisassembledFunction.splitSignature(function.analysisDisplayName)?.result
                ?? function.objcMethod?.signature ?? "unknown"
            let instructions = function.instructions.map { insn in
                guard insn.controlFlow == .return else { return insn }
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
            return function.replacingInstructions(instructions)
        }

        // Facts of the function's own signature, read once rather than at
        // every instruction: each parses the demangled name, and the return
        // register walks the CFG.
        let provenMachineValueReturn = function.hasProvenMachineValueReturn
        let signatureReturnsValue = DisassembledFunction.signatureReturnsValue(
            displayName: function.analysisDisplayName, objcSignature: function.objcMethod?.signature)
        let functionReturnRegister = Self.swiftReturnRegister(
            of: function, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex)

        // Callee name per call/tail-call address, for nesting result expressions.
        var calleeByAddress: [UInt64: String] = [:]
        for insn in function.instructions
        where insn.controlFlow == .call || insn.controlFlow == .branch {
            calleeByAddress[insn.address] = DisassembledFunction.calleeName(of: insn)
        }

        // x20 is `self` only under the Swift calling convention; for any
        // other callee it's a callee-saved register the caller happens to be
        // using, and calling it `self` would be a fabrication. Decided once
        // per call, so the call's statement, its binding and its spelling
        // inside another expression all name the same `self`.
        var selfValueBySite: [UInt64: AbstractValue] = [:]
        for insn in function.instructions {
            guard let site = sites[insn.address], Self.isSwiftCall(insn, swiftTargets: swiftTargets),
                  site.selfValue != .unknown
            else { continue }
            // A String result's second word moved into x20 is no receiver.
            if case .callResultHigh = site.selfValue { continue }
            if let callee = calleeByAddress[insn.address] {
                if DisassembledFunction.receivesThinMetatype(callee, classTypeIndex: classTypeIndex)
                    || DisassembledFunction.takesNoSelf(callee) { continue }
                if let signature = DisassembledFunction.splitSignature(callee),
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
        /// which v registers hold an argument. Any other function, a C
        /// function or a block, shows none, so its sends keep the integer
        /// layout.
        let ownFloatArgumentRegisters: Int = {
            guard let method = function.objcMethod else { return 0 }
            let colons = method.selector.filter { $0 == ":" }.count
            return ObjCArgumentABI.floatRegisterCount(encoding: method.typeEncoding, argumentCount: colons) ?? 0
        }()
        func setsFloatingPointArgument(before address: UInt64) -> Bool {
            guard let callIndex = instructionIndex[address] else { return false }
            var settled = Set<Int>()
            var stored = Set<Int>()
            var index = callIndex
            var reachedEntry = false
            while index > 0, !blockStarts.contains(function.instructions[index].address) {
                index -= 1
                let insn = function.instructions[index]
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
            return reachedEntry && (0 ..< min(ownFloatArgumentRegisters, 8)).contains { !settled.contains($0) }
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

        /// A call to an in-image function whose name is also a C library
        /// function's in the known-arity table: the table is no evidence for it.
        func isNameTwin(_ address: UInt64) -> Bool {
            guard callTargets[address] != nil, let callee = calleeByAddress[address] else { return false }
            return DisassembledFunction.knownArityNameMayHaveTwin(callee)
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
            // `swift_willThrow(SWIFT_CONTEXT void *, SWIFT_ERROR_RESULT
            // SwiftError **)` (swift/include/swift/Runtime/Error.h:71) takes
            // the thrown error in x21 and nothing in x0. Rendering x0 printed
            // a stale register as the thrown value (`swift_willThrow(0)`, 105
            // times in SwiftData); the error box is x21's.
            if calleeByAddress[address] == "swift_willThrow" {
                values = site.errorValue == .unknown ? [] : [site.errorValue]
                strategy = "will-throw"
            }
            // A getter that takes no explicit argument shows none, whatever
            // x0 held: `static DispatchQoS.unspecified.getter(r0)` was a stale
            // register (55 static getters in one app).
            if let callee = calleeByAddress[address],
               Self.getterTakesNoArguments(callee, classTypeIndex: classTypeIndex) {
                argumentsByAddress[address] = []
                strategy = "no-parameters"
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
            if let callee = calleeByAddress[address],
               let slots = Self.swiftCallArgumentSlots(
                   callee: layoutName(at: address, callee: callee),
                   enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex) {
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
                        if words.count == 2 {
                            if let site = stringCallResult(raw[0], raw[1]) {
                                return .aggregate([.callResult(site), .callResultHigh(site)])
                            }
                            return swiftStringLiteral(words[0], words[1]) != nil
                                || selfStringField(words[0], words[1]) != nil ? .aggregate(words) : .unknown
                        }
                        return words[0]
                    case .floating:
                        defer { floating += 1 }
                        return floating < site.floatArguments.count ? site.floatArguments[floating] : .unknown
                    }
                }
                if !laidOut.isEmpty {
                    argumentsByAddress[address] = laidOut.map(sanitizeValue)
                    laidOutTypes[address] = slots.map(\.type)
                }
                strategy = "swift-signature"
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
                if case .address(let format) = fixed[variadic.format] {
                    let text: String? = resolver.cfString(at: format)
                        ?? ReferenceResolver.rawCString(at: format, in: resolver.machO, ranges: resolver.fileRanges)
                            .map { "\"\($0)\"" }
                    kinds = text.flatMap(DisassembledFunction.MessageSend.formatArgumentKinds)
                }
                if let kinds {
                    let variadicValues = (0 ..< kinds.count).map {
                        $0 < site.stackArguments.count ? sanitizeValue(site.stackArguments[$0]) : AbstractValue.unknown
                    }
                    argumentsByAddress[address] = fixed.map(sanitizeValue) + variadicValues
                    if let types = Self.formatSlotTypes(kinds, values: variadicValues, storedBytes: site.stackArgumentWidths) {
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
                    if colons > 0, setsFloatingPointArgument(before: address) {
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
            // An in-image callee no signature describes passes what its body
            // reads: `bump(void)` after `printf` rendered `bump(printf(…))`,
            // and an outlined fragment that reads no argument register took
            // whatever x0 held.
            // A Swift signature names its parameters even where the -O body
            // ignores them (`gen<A>(arg0, arg1)`), so only a callee with none
            // (C, `sub_…`, an outlined fragment) is bounded by its body.
            if let target = callTargets[address], let summary = registerSummaries[target],
               calleeByAddress[address].flatMap({ DisassembledFunction.splitSignature($0) }) == nil,
               calleeByAddress[address].flatMap({ selectorName(callee: $0, arguments: values) }) == nil,
               calleeByAddress[address].flatMap(DisassembledFunction.knownCArity(of:)) == nil || isNameTwin(address) {
                // A register below the highest one read that the body never
                // reads holds whatever the caller left there, not an argument:
                // `useSecond` writes x0 before reading it, and
                // `useSecond(5, 7)` showed the stale 5. Every register
                // through the highest the body's own instructions read is a
                // parameter, so an unknown one is `?`, not absent:
                // `sink(long)` called with nothing tracked rendered `sink()`.
                // Past those, a register the body may read only by passing it
                // to a call is shown when its value is known, as before.
                let proven = summary.provenArgumentCount
                var bounded = (0 ..< max(summary.argumentCount, proven)).map {
                    $0 < values.count && summary.argumentReads.contains($0)
                        ? sanitizeValue(values[$0]) : AbstractValue.unknown
                }
                while bounded.count > proven, bounded.last == .unknown { bounded.removeLast() }
                if !bounded.isEmpty { argumentsByAddress[address] = bounded }
                strategy = "body-reads"
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
                guard let callee = calleeByAddress[addr],
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
        /// case, and an integer body never matches. A conversion to integer ends
        /// the float context below it.
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
            case .binary(_, let lhs, let rhs):
                return floatWidth(lhs) ?? floatWidth(rhs)
            case .unary(.toFloat(let bits), _):
                return bits
            case .unary(.toInteger, _):
                return nil
            case .unary(_, let operand):
                return floatWidth(operand)
            default:
                return nil
            }
        }

        func renderValue(_ value: AbstractValue, depth: Int) -> String {
            if depth < 8, case .binary(.bitAnd, let inner, .immediate(let mask)) = value,
               mask & 1 == 1, isBooleanValued(inner) {
                return renderValue(inner, depth: depth + 1)
            }
            if depth < 8, let boolean = renderBoolean(value, negated: false, depth: depth) {
                return boolean
            }
            switch value {
            case .unknown, .callResultHigh:
                // A String result's second word alone is no source value.
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
                return resolver.name(at: a) ?? "0x" + String(a, radix: 16)
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
            case .selfFieldValue(let offset):
                // Part of a field is not the field: a four-byte read at
                // `fCurPos + 80` rendered `self->fCurPos`. Every such value
                // starts at a load of this offset in this function, so when
                // those loads agree on a width it is the range read; when
                // they do not, the start alone is shown.
                if let fieldMap {
                    let widths = selfFieldReadWidths[offset] ?? []
                    if widths.count == 1, let width = widths.first,
                       case .success(.part(let name, _, let subOffset, let bytes)) =
                        fieldMap.lookup(offset: offset, bytes: width) {
                        return fieldPath("\(name)[\(subOffset)..<\(subOffset + bytes)]")
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
                case .squareRoot: return "sqrt(\(inner))"
                case .absoluteValue: return "abs(\(inner))"
                case .toFloat(let bits):
                    return "\(bits == 64 ? "Double" : bits == 32 ? "Float" : "Float\(bits)")(\(inner))"
                case .toInteger(let signed, let bits):
                    return "\(signed ? "Int" : "UInt")\(bits == 64 ? "" : String(bits))(\(inner))"
                }
            case .aggregate(let values):
                return "(" + values.map { renderValue($0, depth: depth + 1) }.joined(separator: ", ") + ")"
            case .callResult(let addr):
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
                if DisassembledFunction.returnsItsArgument(callee) {
                    return inner.first.map { renderValue($0, depth: depth + 1) } ?? unresolved()
                }
                if DisassembledFunction.isUniquenessCheck(callee) {
                    let object = inner.first.map { renderValue($0, depth: depth + 1) } ?? unknownRenderedValue()
                    return "isKnownUniquelyReferenced(\(object))"
                }
                // The rest of the runtime bookkeeping returns nothing a source
                // value could be (`swift_release`, `swift_beginAccess` are void):
                // x0 after one is not a value to name.
                if DisassembledFunction.isRuntimeNoise(callee) { return unknownRenderedValue() }
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
                            parts.append(renderValue(words[0], depth: depth))
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
                        parts.append(renderValue(values[index], depth: depth))
                    }
                    index += 1
                }
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
                    let rendered = values.map { renderValue($0, depth: 0) }.joined(separator: ", ")
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
                case .success(.part(let name, _, let subOffset, let bytes)):
                    return fieldPath("\(name)[\(subOffset)..<\(subOffset + bytes)]")
                default: return nil
                }
            }
            if field.names.count == 1, let fieldMap {
                switch fieldMap.lookup(offset: access.offset, bytes: max(access.bytes, 1)) {
                case .success(.part(let partName, _, let subOffset, let bytes)):
                    let partPath = fieldPath("\(partName)[\(subOffset)..<\(subOffset + bytes)]")
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
                case .success(.part(let name, _, let subOffset, let bytes)):
                    return "\(path) = \(fieldPath("\(name)[\(subOffset)..<\(subOffset + bytes)]"))"
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
            return "\(path) = \(renderValue(value, depth: 0))"
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
            guard let stored = access.storedValues, stored.count == 2, access.bytes % 2 == 0, let fieldMap
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
                case .success(.part(let name, _, let subOffset, let bytes)):
                    targets.append(fieldPath("\(name)[\(subOffset)..<\(subOffset + bytes)]"))
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
                    case .part(let name, _, let subOffset, let bytes):
                        values.append(fieldPath("\(name)[\(subOffset)..<\(subOffset + bytes)]"))
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
            return renderValue(value, depth: 0)
        }

        // The return type's complete stored-property layout, when it is a struct
        // this image lays out in full: what an x8-indirect return is checked
        // against field by field.
        let returnLayout: FieldMap? = returnTypeName.flatMap {
            Self.completeValueLayout(of: $0, fieldMaps: typeFieldMaps, classTypeIndex: classTypeIndex)
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
            return renderValue(value, depth: 0)
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

        func collectCallResults(in value: AbstractValue, into consumed: inout Set<UInt64>) {
            switch value {
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
            let blocks = function.basicBlocks()
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
                    return insn.branchTarget.flatMap { tracer.calleeClobbers[$0] }?.contains("x20") ?? false
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
            ? function.basicBlocks() : []
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
            if call.branchTarget.flatMap({ tracer.calleeClobbers[$0] })?.contains("x21") == true { return false }
            return ValueTracer.provablyDoesNotThrow(DisassembledFunction.calleeName(of: call) ?? "")
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
                          var clobbered = call.branchTarget.flatMap { tracer.calleeClobbers[$0] } ?? []
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
            call.branchTarget.flatMap { tracer.calleeClobbers[$0] }?.contains("x20") != true
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
            if let callee, DisassembledFunction.isRuntimeNoise(callee) { continue }
            (callee.map { normalizedArguments(callee: $0, values: values, at: address) } ?? values)
                .forEach { countDirectUses($0, at: address) }
        }
        for (address, value) in analysis.branchConditions { countDirectUses(value, at: address) }
        for insn in function.instructions where insn.controlFlow == .branch && insn.branchTarget == nil
            && function.switchTargets[insn.address] == nil && !asyncReturns.contains(insn.address) {
            if let target = analysis.indirectControlFlowTargets[insn.address] { countDirectUses(target, at: insn.address) }
        }
        for (address, access) in analysis.selfFieldAccesses {
            if let values = access.storedValues { values.forEach { countDirectUses($0, at: address) } }
            else if let value = access.storedValue { countDirectUses(value, at: address) }
        }
        if function.objcMethod.map({ !$0.returnsVoid }) == true {
            for insn in function.instructions where insn.controlFlow == .return {
                analysis.exitValues[insn.address].map { countDirectUses($0, at: insn.address) }
            }
        } else if function.objcMethod == nil, returnsDirectly,
                  let register = functionReturnRegister {
            for insn in function.instructions where isReturn(insn) && normalReturnIsProven(at: insn.address) && !throwExits.contains(insn.address) {
                (register == .floating ? analysis.exitFloatValues : analysis.exitValues)[insn.address]
                    .map { countDirectUses($0, at: insn.address) }
            }
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
        let bindingBlocks = function.basicBlocks()
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
            guard uses > 1 || crossesEffect(site), let callee = calleeByAddress[site],
                  !DisassembledFunction.isRuntimeNoise(callee),
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
                .map({ !DisassembledFunction.isRuntimeNoise($0) }) ?? true {
                let values = argumentsByAddress[insn.address] ?? []
                let rendered = calleeByAddress[insn.address]
                    .map { normalizedArguments(callee: $0, values: values, at: insn.address) } ?? values
                for value in rendered {
                    collectCallResults(in: value, into: &consumedCallResults)
                }
            }
            if function.objcMethod.map({ !$0.returnsVoid }) == true,
               let value = analysis.exitValues[insn.address] {
                if insn.controlFlow == .return {
                    collectCallResults(in: value, into: &consumedCallResults)
                } else if insn.controlFlow == .branch,
                          let callee = DisassembledFunction.calleeName(of: insn),
                          passthroughReturnHelpers.contains(where: callee.hasPrefix)
                            || !DisassembledFunction.isRuntimeNoise(callee) {
                    collectCallResults(in: value, into: &consumedCallResults)
                }
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
        let scalarTailReturns = Self.scalarTailReturnSites(in: function, enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex)
        func returnPath(at address: UInt64) -> ProbeValue {
            if observedReturnPaths == nil { observedReturnPaths = Probe.returnPathConditions(analysis, of: function) }
            return .abstractValue(observedReturnPaths?[address] ?? .unknown)
        }
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
                           case .success(.part(let partName, _, let subOffset, let bytes)) =
                            fieldMap.lookup(offset: access.offset, bytes: max(access.bytes, 1)) {
                            readPath = fieldPath("\(partName)[\(subOffset)..<\(subOffset + bytes)]")
                        }
                        facts.fieldRead = readPath
                        sourceNotes.append(readPath)
                    }
                }
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
            } else if isObjCNonVoid, let rawExit = analysis.exitValues[insn.address] {
                let exit = sanitizeValue(rawExit)
                if insn.controlFlow == .return, exit != .unknown {
                    noteExit(.normal(renderReturnValue(exit, before: insn.address)))
                } else if insn.controlFlow == .branch, let callee {
                    if passthroughReturnHelpers.contains(where: callee.hasPrefix), exit != .unknown {
                        noteExit(.normal(renderReturnValue(exit, before: insn.address)))
                    } else if !DisassembledFunction.isRuntimeNoise(callee),
                              let values = argumentsByAddress[insn.address] {
                        noteExit(.normal(callExpression(callee: callee, values: values, site: insn.address)))
                    }
                }
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
                let declarations = bindings.map { "var \($0.name) = \(Self.renderImmediate($0.value))" }
                facts.loopInitializations = declarations
                sourceNotes.append("loop-init: \(declarations.joined(separator: " | "))")
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
            if let callee, let access = selfAccessors[callee], !access.isGetter,
               let value = sites[insn.address]?.arguments.first {
                let rendered = renderValue(sanitizeValue(value), depth: 0)
                if rendered != "?" {
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

            if isReturn(insn), throwsSignature?.isThrowing == true,
               !normalReturnIsProven(at: insn.address), !throwExits.contains(insn.address),
               !mergedThrowExits.contains(insn.address), !notedThrow {
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
                let returnsValue = DisassembledFunction.signatureReturnsValue(
                    displayName: function.analysisDisplayName, objcSignature: function.objcMethod?.signature)
                let status = scalarTailReturns.contains(insn.address) ? "tail-call"
                    : throwExits.contains(insn.address) ? "throw"
                    : renderedReturn == "return ?" ? "unknown"
                    : renderedReturn != nil ? (completeReturnRendering[insn.address] == false ? "partial" : "recovered")
                    : !returnsValue ? "void" : "unsupported-layout-or-value"
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
            // the CFG read it as one (it had no successors either way).
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
        return function.replacingInstructions(instructions)
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

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let (address, text) = parseInstruction(line) {
                if let label = pendingLabel {
                    labelByAddress[address] = label
                    pendingLabel = nil
                }
                instructions.append(
                    Instruction(address: address, text: text, annotation: annotate(text))
                )
            } else if let label = parseLabel(line) {
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
    private func demangle(_ token: String) -> String? {
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
