import Ccapstone
import Foundation

/// Operators retained in source-level symbolic expressions. These are kept
/// deliberately small and side-effect free: when an instruction falls outside
/// this set, value tracking still degrades to `.unknown` rather than guessing.
public enum AbstractBinaryOperator: Equatable, Sendable {
    case add
    case subtract
    case multiply
    /// Signed integer division (`sdiv`), or float division.
    case divide
    case remainder
    /// `udiv` and its remainder. Kept apart from `divide` so an unsigned
    /// division is never rendered as the signed `/` it disagrees with at every
    /// negative input; the renderer marks it unless the operand is a proven UInt.
    case unsignedDivide
    case unsignedRemainder
    case bitAnd
    case bitOr
    case bitXor
    case shiftLeft
    case shiftRight
    case arithmeticShiftRight
    case multiplyHigh
    case unsignedMultiplyHigh
    // Comparisons, produced by a flag-setting compare + `cset`/`b.cond`.
    // `equal`/`notEqual` are sign-agnostic. The signed vs unsigned distinction is
    // preserved (not merged) because collapsing an unsigned machine comparison
    // onto a signed operator misreads a range check — see U1 in
    // docs/research/decompiler-comparison.md. The unsigned variants come from the
    // ARM64 condition code (LO/HS/HI/LS); the signed ones from LT/GE/GT/LE.
    case equal
    case notEqual
    case less
    case lessEqual
    case greater
    case greaterEqual
    case unsignedLess
    case unsignedLessEqual
    case unsignedGreater
    case unsignedGreaterEqual

    /// Whether this operator is any comparison (signed, unsigned, or equality).
    public var isComparison: Bool {
        switch self {
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual,
             .unsignedLess, .unsignedLessEqual, .unsignedGreater, .unsignedGreaterEqual:
            return true
        default:
            return false
        }
    }

    /// Whether this is an unsigned-only comparison (carries the machine's unsigned
    /// semantics; renders specially so a signed reading is never fabricated).
    public var isUnsignedComparison: Bool {
        switch self {
        case .unsignedLess, .unsignedLessEqual, .unsignedGreater, .unsignedGreaterEqual:
            return true
        default:
            return false
        }
    }

    /// The signed comparison with the same shape (`unsignedLess` → `less`), for
    /// rendering when the operands' signedness makes the signed reading correct.
    public var signedForm: AbstractBinaryOperator {
        switch self {
        case .unsignedLess: return .less
        case .unsignedLessEqual: return .lessEqual
        case .unsignedGreater: return .greater
        case .unsignedGreaterEqual: return .greaterEqual
        default: return self
        }
    }

    public var symbol: String {
        switch self {
        case .add: "+"
        case .subtract: "-"
        case .multiply: "*"
        case .divide, .unsignedDivide: "/"
        case .remainder, .unsignedRemainder: "%"
        case .bitAnd: "&"
        case .bitOr: "|"
        case .bitXor: "^"
        case .shiftLeft: "<<"
        case .shiftRight, .arithmeticShiftRight: ">>"
        case .multiplyHigh, .unsignedMultiplyHigh: "mulh"
        case .equal: "=="
        case .notEqual: "!="
        case .less: "<"
        case .lessEqual: "<="
        case .greater: ">"
        case .greaterEqual: ">="
        // Fallback symbols; the boolean-simplification path renders unsigned
        // comparisons via the type-aware decision (range idiom / UInt cast) and
        // rarely falls back here. These keep the operator honest if it does.
        case .unsignedLess: "<"
        case .unsignedLessEqual: "<="
        case .unsignedGreater: ">"
        case .unsignedGreaterEqual: ">="
        }
    }
}

/// Unary operators retained in symbolic expressions — the floating-point and
/// bitwise inversions the compiler emits as single instructions (`fneg`,
/// `fsqrt`, `fabs`, `mvn`), and the numeric conversions (`scvtf`, `fcvtzs`,
/// `fcvt`). Like the binary set this stays small and pure; an unmodelled
/// instruction still degrades to `.unknown`.
public enum AbstractUnaryOperator: Equatable, Sendable {
    case negate
    case squareRoot
    case absoluteValue
    case bitwiseNot
    /// An integer or a float converted to a float of `bits` width (`scvtf`,
    /// `ucvtf`, `fcvt`): `Double(x)` at 64, `Float(x)` at 32.
    case toFloat(bits: Int)
    /// A float truncated toward zero to an integer of `bits` width (`fcvtzs`,
    /// `fcvtzu`): `Int(x)`, `UInt32(x)`.
    case toInteger(signed: Bool, bits: Int)
}

/// A small abstract-value lattice for CFG-aware data-flow. Alongside constants
/// and addresses it retains bounded arithmetic expressions, which is enough to
/// turn common Objective-C ivar updates and scalar returns back into source-like
/// statements without pretending to recover arbitrary machine computation.
public indirect enum AbstractValue: Equatable, Sendable {
    case unknown
    case immediate(UInt64)
    case address(UInt64)
    /// The return value (x0) of the call at this instruction address — lets a
    /// result flow into a later call's argument as a nested expression.
    case callResult(UInt64)
    /// A named source-level method argument. Objective-C's explicit arguments
    /// begin in x2 (after `self` and `_cmd`), so metadata can seed these without
    /// guessing and keep `arg0` alive through register moves and stack spills.
    case argument(Int)
    /// The *contents* of the given address, loaded by an `ldr` from a known
    /// base. Only meaningful once something resolves what lives there (an
    /// `__objc_selrefs` slot, say); callers that can't resolve it should treat
    /// it as `.unknown`.
    case loaded(UInt64)
    /// The `self` pointer as it arrives at a Swift instance method — x20 under
    /// the Swift calling convention.
    ///
    /// Seeded at entry ONLY when the function is known to be an instance method
    /// of a known type. That is not a guess: x20 is an ordinary callee-saved
    /// register in a C or ObjC function, holds a metatype in a static method,
    /// and holds a heap-boxed capture context in a closure invocation function.
    /// Seeding it on any of those would attach a nominal type's field names to a
    /// pointer that is not that type.
    case selfPointer
    /// The address of a field of `self` — `add x0, x20, #0x20` forms
    /// `&self.breed`. Distinct from `.selfPointer` at offset 0 so that a
    /// zero-offset field access is still recognisable as one.
    case selfField(offset: Int)
    /// A value loaded from a field of `self`. Distinct from `selfField`, which
    /// is the field's address; this lets an ivar/object value flow into a later
    /// message-send argument as `self->_name`.
    case selfFieldValue(offset: Int)
    /// The function pointer at a byte offset into `self`'s class metadata vtable —
    /// the target of a `ldr x8,[x20]; ldr x8,[x8,#off]; blr x8` dispatch. Named
    /// against `self`'s type via `VTableIndex` at enrichment time.
    case selfVTableMethod(offset: Int)
    /// A field, at a byte offset, of a struct argument passed by value in
    /// registers (an HFA). Renders as `arg<n>.field`; seeded for a nonmutating
    /// method whose parameter is a small floating-point aggregate.
    case argumentField(argument: Int, offset: Int)
    /// A value merged from the two arms of a control-flow diamond — the phi at a
    /// join. Renders as `condition ? whenTrue : whenFalse`, reconstructing a
    /// ternary / nil-coalescing. Produced only when the deciding condition is
    /// itself recoverable; otherwise the join keeps dropping to `.unknown`.
    case select(condition: AbstractValue, whenTrue: AbstractValue, whenFalse: AbstractValue)
    /// The array `_allocateUninitializedArray` returns at this call address, with
    /// its element count. The caller then stores the elements into it; those are
    /// gathered (by store offset) so the literal renders as `[e0, e1, …]`.
    case arrayLiteral(site: UInt64, count: Int)
    /// A pure symbolic expression whose inputs are themselves proven values.
    /// Expression construction is bounded by `ValueTracer.expression` so loops
    /// and long instruction chains cannot create unbounded trees.
    case binary(AbstractBinaryOperator, AbstractValue, AbstractValue)
    /// A pure unary expression — `-x`, `sqrt(x)`, `abs(x)`, `~x`. Bounded by the
    /// same depth cap as `.binary`.
    case unary(AbstractUnaryOperator, AbstractValue)
    /// Consecutive eight-byte values packed into a wider SIMD register. Clang
    /// commonly moves two Objective-C stack arguments at once through `q0`.
    case aggregate([AbstractValue])
    /// A frame-relative address: the stack pointer on function entry, plus this
    /// (usually negative) offset.
    ///
    /// Keying stack slots off a symbolic frame base rather than a literal `sp`
    /// value is what lets them survive the prologue's `sub sp, sp, #k` and
    /// `stp …, [sp, #-k]!` — after those, the same local is at a different `sp`
    /// offset, but the same frame offset.
    case frame(Int64)
    /// A loop-carried induction variable, identified by a small id (rendered
    /// `i`, `j`, …). Seeded at a loop header by the induction-variable pass when a
    /// slot has a proven constant initial value and a proven `i ± c` recurrence
    /// across the back-edge; otherwise the slot stays `.unknown` (declined). This
    /// is the φ the earlier phases deferred, now with a consumer: it lets a loop
    /// header condition reconstruct with a name (`i < n`) instead of raw
    /// registers.
    case local(Int)
    /// The incoming x8: the address of the caller-owned buffer an indirectly
    /// returned value (a struct wider than four words, a large payload enum, a
    /// generic or existential result) is written into. Seeded at every entry,
    /// because x8 means exactly this in every ARM64 convention; it carries
    /// information only once the body reads it, and a body that writes x8 first
    /// simply overwrites the seed.
    case indirectResultPointer
    /// `x8 + constant`: the address of a byte offset inside the result buffer.
    case indirectResultField(offset: Int)
    /// The eight bytes at `offset` of the value the call at `site` returned
    /// indirectly into the caller's frame. Produced only when the callee is
    /// proven to read its incoming x8 and its result size is known, so a later
    /// load from that frame slot renders as a field of the call's result rather
    /// than as a stale local.
    case indirectCallResultWord(site: UInt64, offset: Int)
    /// The async context pointer of the function being analysed (x22 at an
    /// async entry or continuation funclet; the first word of x22 at an
    /// await-return funclet). Seeded only for a function the async funclet
    /// index placed in a chain with a known kind.
    case asyncContext
    /// At an await-return funclet, x22 holds the *callee's* context, whose
    /// first word is the caller's own (`asyncContext`).
    case asyncCalleeContext
    /// The continuation loaded from `asyncContext + 8` (ResumeParent): the
    /// address an async function returns to. A `br` through it is the
    /// function's return.
    case asyncResumeParent
    /// A pointer-width value loaded from a slot of the function's own async
    /// context whose stored value was not proven. Renders `?`.
    case asyncContextSlot(Int)
    /// The direct result of the await that the resume funclet numbered
    /// `ordinal` continues: x0 (or v0) at that funclet's entry, seeded only when
    /// the awaited callee's signature proves a single-register result.
    case awaitResult(Int)
}

/// What is known about how a callee delivers its result, keyed by call site.
/// Decides what a call does to the caller's frame when x8 points into it, and
/// whether a call that forwards the caller's own x8 fills the caller's result.
public enum CalleeResultConvention: Equatable, Sendable {
    /// The callee provably never reads its incoming x8 (its whole body was
    /// inspected, or it is a fixed-ABI runtime/libc entry point), so x8 at the
    /// call is a scratch value and nothing under it is written.
    case direct
    /// The callee provably reads its incoming x8 and writes its result through
    /// it; `sizeBytes` is the result's size when metadata gives it.
    case indirect(sizeBytes: Int?)
}

/// The result-buffer state reaching one `ret` of an x8-indirect function.
public struct IndirectResultExit: Equatable, Sendable {
    /// One store through the incoming x8 that reaches the exit on every path.
    public struct Store: Equatable, Sendable {
        public var bytes: Int
        public var value: AbstractValue
    }
    /// Set when the whole buffer was filled by the call at this site (the caller
    /// forwarded its own x8 to a callee proven to write through it).
    public var whole: UInt64? = nil
    /// Byte offset → the store reaching the exit. Partial on purpose: a field
    /// stored on only one path is absent, and the consumer must decline.
    public var stores: [Int: Store] = [:]
    /// The result pointer escaped (into a call argument, into memory, into
    /// untracked arithmetic), or a whole-buffer fill was partially overwritten,
    /// so nothing about the buffer's contents is provable at this exit.
    public var poisoned: Bool = false
}

/// Register state that metadata proves at a method's entry point.
public enum MethodEntryConvention: Sendable, Equatable {
    /// Swift instance method: `self` is x20, and each provably single-register
    /// scalar parameter occupies the register named in `scalarArguments`
    /// (register key → source argument index — integers in x0…, floats in v0…).
    /// The map is empty when any parameter isn't provably single-register (they
    /// are left unseeded rather than mislabeled).
    case swiftInstance(scalarArguments: [String: Int])
    /// Objective-C class or instance method: `self` is x0, `_cmd` is x1, and
    /// explicit selector arguments begin in x2.
    case objectiveC(argumentCount: Int, scalarArguments: [String: Int]? = nil)
    /// An Objective-C initializer has the same register convention, but a
    /// metadata-proven `init…` entry lets a super-initializer result become the
    /// method's new `self` for subsequent ivar accesses.
    case objectiveCInitializer(argumentCount: Int, scalarArguments: [String: Int]? = nil)
    /// A Swift free function or static method whose parameters are all
    /// single-register scalars, mapped by `scalarArguments` (register key →
    /// source argument index — integers in x0…, floats in v0…). Seeded only under
    /// that proof (see `swiftScalarArgumentRegisters`) so a multi-register
    /// parameter never shifts the mapping and mislabels a register.
    case swiftFunction(scalarArguments: [String: Int])
    /// A nonmutating instance method of a small homogeneous floating-point
    /// aggregate struct: `self` (and any HFA parameters) are passed by value in
    /// consecutive SIMD registers, so `seededRegisters` maps each register key to
    /// the field value it holds (`.selfFieldValue` for `self`, `.argumentField`
    /// for a parameter). Used ONLY when the body proves `self` is not the x20
    /// pointer form (mutating/indirect), so a register never gets a fabricated
    /// field.
    case swiftValueInstance(seededRegisters: [String: AbstractValue])
    /// An async funclet: `base` is the ordinary convention of the entry funclet
    /// (its parameters really are in registers there; nil for a resume
    /// funclet), and `seededRegisters` adds what the async ABI fixes: x22 as
    /// the context, and the awaited result at an await-return funclet.
    indirect case asyncFunclet(base: MethodEntryConvention?, seededRegisters: [String: AbstractValue])

    var isObjectiveCInitializer: Bool {
        if case .objectiveCInitializer = self { return true }
        return false
    }
}

/// The values reaching one call, snapshotted just before it executes.
public struct CallSite: Equatable, Sendable {
    /// x0–x7, trailing unknowns trimmed.
    public var arguments: [AbstractValue] = []
    /// v0–v7, untrimmed. Read only where the callee's signature lays a
    /// floating-point parameter out (see `swiftCallArgumentSlots`).
    public var floatArguments: [AbstractValue] = []
    /// Fresh contiguous scalar values written at the current stack pointer
    /// before the call. These are possible AAPCS64 stack arguments; consumers
    /// add them only when a resolved variadic call shape proves they belong to
    /// the source call.
    public var stackArguments: [AbstractValue] = []
    /// x20 — `self` under the Swift calling convention. Meaningless for a
    /// non-Swift callee, where x20 is just another callee-saved register, so
    /// only render it once the callee is known to be Swift.
    public var selfValue: AbstractValue = .unknown
    /// x21 — the Swift error result register.
    public var errorValue: AbstractValue = .unknown
    /// x8 — AAPCS64's indirect result buffer, used for returns too large for x0.
    public var indirectResult: AbstractValue = .unknown

    /// Whether nothing at all was inferred (so there's nothing worth showing).
    public var isEmpty: Bool {
        arguments.isEmpty && floatArguments.allSatisfy { $0 == .unknown }
            && stackArguments.isEmpty && selfValue == .unknown
            && errorValue == .unknown && indirectResult == .unknown
    }
}

/// A memory access into `self`, for field naming.
public struct SelfFieldAccess: Sendable, Equatable {
    /// Byte offset from the start of the instance.
    public var offset: Int
    /// Access width. Comes from the instruction id and register width —
    /// `aarch64_op_mem` carries no width at all.
    public var bytes: Int
    public var isWrite: Bool
    /// The value stored by a write, when the data-flow lattice can prove it.
    public var storedValue: AbstractValue? = nil
    /// Both values of a paired store (`stp`), in field order. Scalar stores
    /// leave this nil and continue to use `storedValue`.
    public var storedValues: [AbstractValue]? = nil
    /// True when the instruction forms the field's ADDRESS rather than loading
    /// it (`add x0, x20, #0x20` -> `&self.breed`).
    public var isAddressOf: Bool = false
}

/// Everything one pass over a function recovers.
public struct FunctionAnalysis: Sendable {
    public var callSites: [UInt64: CallSite] = [:]
    /// Register-derived call/tail-call targets at indirect control-flow sites.
    /// A value such as `.loaded(slot)` is still only an address provenance fact;
    /// the Mach-O enrichment pass decides whether that slot provably contains a
    /// known function pointer before publishing a target name or graph edge.
    public var indirectControlFlowTargets: [UInt64: AbstractValue] = [:]
    /// Unconditional branches with a register snapshot. Once symbolization
    /// proves that the target is outside the function, these become tail calls.
    public var branchSites: [UInt64: CallSite] = [:]
    /// The branch-taken comparison at a flags-based conditional branch (`b.eq`,
    /// `b.lt`, …), reconstructed from the tracked NZCV flags and the branch's
    /// condition code. Lets the structurer render a source-named condition
    /// (`arg0 >= arg1`) in place of raw registers. Compare-and-branch forms
    /// (`cbz`/`tbz`) carry no condition code and are absent here.
    public var branchConditions: [UInt64: AbstractValue] = [:]
    /// Proven loop induction body updates, keyed by the loop header's branch
    /// instruction — the statements (`total += i`, `i += 1`) the structurer
    /// appends, in order (accumulate then advance), inside a rotated
    /// `while (i < n) { … }`. Only set for proven linear/accumulator recurrences
    /// (see `resolveLoopInductions`).
    public var loopUpdates: [UInt64: [String]] = [:]
    /// x0 immediately before a return or unconditional branch. The enrichment
    /// pass uses Objective-C return types and resolved tail helpers to decide
    /// which of these are honest source-level returns.
    public var exitValues: [UInt64: AbstractValue] = [:]
    /// x21 at each `ret`: in a throwing Swift function, the error it returns.
    public var exitErrorValues: [UInt64: AbstractValue] = [:]
    /// For a `ret` whose block several paths reach: x21 at the `ret` along each
    /// path, keyed by the last instruction of the predecessor block it comes
    /// from. A throw that falls into the normal epilogue merges with the
    /// return there, and only the per-path value tells them apart.
    public var exitErrorValuesByPredecessor: [UInt64: [UInt64: AbstractValue]] = [:]
    /// x20 at each proven async return (a `br` through ResumeParent): an
    /// async throwing function hands its error back in x20, zero for none.
    public var exitAsyncErrorValues: [UInt64: AbstractValue] = [:]
    /// v0 (the d0/s0 floating-point return register) immediately before a
    /// return. A `Double`/`Float`-returning function delivers its result here,
    /// not in x0, so the enrichment pass reads this one for those return types.
    public var exitFloatValues: [UInt64: AbstractValue] = [:]
    /// x1 immediately before a return. A `yield_once` coroutine (a `_modify` or
    /// `_read` accessor) returns the continuation pointer in x0 and its first
    /// yielded value in x1 (Swift lowers the ramp result as `{ continuation,
    /// yields… }`, continuation first — see IRGen `expandCoroutineResult`). For a
    /// stored-property `_modify` that value is `&self.field`, so the enrichment
    /// pass reads this to render the yield.
    public var exitYieldValues: [UInt64: AbstractValue] = [:]
    /// Instruction address → the access it makes into `self`.
    public var selfFieldAccesses: [UInt64: SelfFieldAccess] = [:]
    /// Array-literal construction site → the values stored into it, by byte
    /// offset. Reconstructs `[e0, e1, …]` from the `_allocateUninitializedArray` +
    /// element-store + `_finalizeUninitializedArray` lowering.
    public var arrayElements: [UInt64: [Int: AbstractValue]] = [:]
    /// `ret` address → the stores through the incoming x8 that reach it. Only
    /// meaningful for a function that reads its incoming x8 (the enrichment pass
    /// checks that separately); for any other function the map is empty.
    public var exitIndirectResults: [UInt64: IndirectResultExit] = [:]
    /// Every pointer-width store into a slot of the function's own async
    /// context: slot byte offset → the values stored there, one per store site.
    /// The chain pass keeps a slot only when exactly one store reaches it.
    public var asyncSlotStores: [Int: [AbstractValue]] = [:]
}

/// An abstract interpreter over a function's basic blocks. Propagates constants,
/// addresses, frame-relative stack slots, and `self` through registers, and
/// snapshots the argument registers at each call.
public struct ValueTracer: Sendable {
    /// Per-call-site callee result conventions (see `CalleeResultConvention`).
    /// A site absent from the map has an unknown callee, which is treated
    /// pessimistically: a forwarded x8 poisons the result, and a frame slot
    /// under x8 is clobbered from that offset up.
    public var calleeConventions: [UInt64: CalleeResultConvention]

    /// Values proven to sit in slots of the function's own async context when
    /// a funclet is entered: slot byte offset → value. Built by a pass over the
    /// whole funclet chain (see `Disassembler.asyncChainSlots`) and consulted
    /// by a pointer-width load from `asyncContext + offset`.
    let asyncContextSlots: [Int: AbstractValue]

    /// Callee address → the callee-saved registers its body writes without
    /// saving (`CalleeRegisterSummary`): an outlined fragment reached by `bl`
    /// does not preserve them, so they are forgotten after a call to it.
    var calleeClobbers: [UInt64: Set<String>] = [:]

    public init(calleeConventions: [UInt64: CalleeResultConvention] = [:], asyncContextSlots: [Int: AbstractValue] = [:]) {
        self.calleeConventions = calleeConventions
        self.asyncContextSlots = asyncContextSlots
    }

    /// Register and stack-slot values. Register keys are canonical names
    /// (`x3`, `sp`); stack slots are keyed by frame offset (see `stackKey`), so
    /// both live in one map and flow through the same meet.
    private typealias State = [String: AbstractValue]

    /// Entry state: `sp` anchors the frame at offset 0. Receiver/argument
    /// registers are seeded only when runtime or Swift metadata establishes the
    /// method convention for this exact implementation address.
    private static func initialState(entry: MethodEntryConvention?) -> State {
        // x8 is the indirect-result address in every ARM64 convention, so the
        // seed is a fact about the ABI, not about this function; see
        // `AbstractValue.indirectResultPointer`.
        var state: State = ["sp": .frame(0), "x8": .indirectResultPointer]
        switch entry {
        case .swiftInstance(let scalarArguments):
            state["x20"] = .selfPointer
            // Parameters occupy x0…/v0… independently of the `self` register
            // (x20), so an instance method's scalar arguments are seeded the same
            // way a free function's are.
            for (register, argument) in scalarArguments { state[register] = .argument(argument) }
        case .objectiveC(let argumentCount, let typed), .objectiveCInitializer(let argumentCount, let typed):
            state["x0"] = .selfPointer
            // Metadata-typed locations: integer arguments in x2…, floating-point
            // ones in v0… on an independent counter, the rest on the entry stack
            // (only full 8-byte slots are supplied). A Double argument made every
            // later integer argument read one register early in the positional
            // layout below. An empty map seeds nothing: the layout is unproven.
            if let typed {
                for (location, argument) in typed {
                    if location.hasPrefix("stack@"), let offset = Int64(location.dropFirst("stack@".count)) {
                        state[Self.stackKey(offset)] = .argument(argument)
                    } else {
                        state[location] = .argument(argument)
                    }
                }
                break
            }
            // Untyped (an entry recovered from a symbol name): the all-integer
            // layout.
            // AAPCS64 has six argument registers left after self/_cmd. Further
            // ObjC arguments are stack-passed and intentionally remain unknown.
            for argument in 0 ..< min(max(argumentCount, 0), 6) {
                state["x\(argument + 2)"] = .argument(argument)
            }
            // For ordinary integer/pointer Objective-C parameters, AAPCS64
            // spills explicit arguments after x7 into consecutive 8-byte slots
            // at the entry stack pointer. Aggregate/vector ABI cases remain a
            // deliberate limitation, but this recovers the overwhelmingly
            // common long selector signatures found in Apple frameworks.
            for argument in 6 ..< max(6, min(max(argumentCount, 0), 32)) {
                state[Self.stackKey(Int64(argument - 6) * 8)] = .argument(argument)
            }
        case .swiftFunction(let scalarArguments):
            // No `self`/`_cmd` prefix: a Swift function's integer arguments occupy
            // x0…, its floating-point ones v0…. A proven all-scalar signature
            // never spills, so there is nothing past the eighth of each to recover.
            for (register, argument) in scalarArguments { state[register] = .argument(argument) }
        case .swiftValueInstance(let seededRegisters):
            // `self` (and HFA parameters) arrive decomposed across SIMD registers;
            // each holds a field's value directly, so they read as `self.field` /
            // `arg<n>.field` with no x20 pointer.
            for (register, value) in seededRegisters { state[register] = value }
        case .asyncFunclet(let base, let seededRegisters):
            state = initialState(entry: base)
            for (register, value) in seededRegisters { state[register] = value }
        case nil:
            break
        }
        return state
    }

    /// Map of call-instruction address → the values reaching that call.
    /// Calls where nothing could be inferred are omitted.
    ///
    /// A forward data-flow fixpoint over the CFG carries values across basic
    /// blocks (e.g. callee-saved x19–x28 holding `self`/locals), so an argument
    /// set before a branch is still recovered at a call after it.
    /// Recover call sites and `self` field accesses in one pass.
    ///
    /// - Parameter hasSelf: seed x20 with `self`. Pass true ONLY when the
    ///   function is known to be an instance method of a known type — see
    ///   `AbstractValue.selfPointer`.
    public func analyze(_ function: DisassembledFunction, hasSelf: Bool = false) -> FunctionAnalysis {
        analyze(function, entry: hasSelf ? .swiftInstance(scalarArguments: [:]) : nil)
    }

    /// Analyze with a metadata-proven Swift or Objective-C method entry state.
    public func analyze(
        _ function: DisassembledFunction,
        entry: MethodEntryConvention?
    ) -> FunctionAnalysis {
        let blocks = function.basicBlocks()
        guard !blocks.isEmpty else { return FunctionAnalysis() }
        let blockByStart = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        let addressTaken = Self.addressTakenFrameOffsets(function.instructions)

        var predecessors: [UInt64: [UInt64]] = [:]
        for block in blocks {
            for successor in block.successors where blockByStart[successor] != nil {
                predecessors[successor, default: []].append(block.startAddress)
            }
        }

        // Forward fixpoint: block entry state = meet of predecessors' exit states.
        var inState: [UInt64: State] = [:]
        var outState: [UInt64: State] = [:]
        var worklist = blocks.map(\.startAddress)
        var queued = Set(worklist)
        var iterations = 0
        let cap = blocks.count * 64 + 16 // safety bound; the analysis is monotone
        while let addr = worklist.first {
            worklist.removeFirst()
            queued.remove(addr)
            iterations += 1
            if iterations > cap {
                Probe.record(.tracerFixpointCap, ["blocks": .int(blocks.count), "cap": .int(cap)])
                break
            }
            guard let block = blockByStart[addr] else { continue }
            let preds = predecessors[addr] ?? []
            // Only the function's entry receives the caller's ABI state. A block
            // with no predecessor may be an exception landing pad: its x0 is the
            // exception and its frame is the prologue's, not the entry's, so it
            // starts with nothing proven. And the entry keeps the caller as an
            // incoming edge when a loop branches back to it; met only with its
            // back edges, it lost its arguments and self.
            var incoming = preds.compactMap { outState[$0] }
            if addr == function.startAddress { incoming.append(Self.initialState(entry: entry)) }
            let blockEntry = Self.meet(incoming)
            inState[addr] = blockEntry
            var registers = blockEntry
            for insn in block.instructions {
                transfer(
                    insn, into: &registers, record: nil, recordAccess: nil,
                    initializerEntry: entry?.isObjectiveCInitializer == true,
                    addressTaken: addressTaken
                )
            }
            if outState[addr] != registers {
                outState[addr] = registers
                for successor in block.successors
                where blockByStart[successor] != nil && !queued.contains(successor) {
                    worklist.append(successor)
                    queued.insert(successor)
                }
            }
        }

        // Value merging: a value that diverges across the two arms of a
        // conditional-branch diamond is that branch's select (`cond ? a : b`),
        // reconstructing a ternary / nil-coalescing. Enrich the merge blocks'
        // entry states before the snapshot pass replays them.
        resolveDiamondSelects(
            blocks: blocks, predecessors: predecessors,
            blockByStart: blockByStart, inState: &inState, outState: outState
        )
        // The N-way generalization: a switch over a tag, whose merge has more
        // than the two predecessors a diamond does.
        resolveSwitchSelects(
            blocks: blocks, predecessors: predecessors,
            blockByStart: blockByStart, inState: &inState, outState: outState
        )
        // Loop-carried induction variables: a header slot with a proven constant
        // initial value and a proven `i ± c` recurrence across the back-edge is
        // named `.local(i)`, so the loop's exit comparison reconstructs with a
        // name (`i < n`) instead of raw registers, and its body update `i += c` is
        // recorded. Declines anything unproven.
        let loopUpdates = resolveLoopInductions(
            blocks: blocks, predecessors: predecessors,
            blockByStart: blockByStart, inState: &inState, outState: outState,
            addressTaken: addressTaken
        )

        // Snapshot pass: replay from each block's fixed entry state, recording
        // call arguments and self-field accesses.
        var result = FunctionAnalysis()
        result.loopUpdates = loopUpdates
        for block in blocks {
            var registers = inState[block.startAddress] ?? [:]
            for insn in block.instructions {
                if insn.branchTarget == nil,
                   insn.controlFlow == .call || insn.controlFlow == .branch,
                   let target = Self.indirectTarget(of: insn, in: registers),
                   target != .unknown {
                    result.indirectControlFlowTargets[insn.address] = target
                }
                if insn.controlFlow == .return || insn.controlFlow == .branch,
                   let value = registers["x0"], value != .unknown {
                    result.exitValues[insn.address] = value
                }
                if insn.controlFlow == .return,
                   let value = registers["x21"], value != .unknown {
                    result.exitErrorValues[insn.address] = value
                }
                // Also at a proven async return (a `br` through the context's
                // ResumeParent): a Double-returning async function delivers in
                // v0 there. Not at other branches: a recorded v0 would make the
                // enrichment pass run on a function it otherwise skips, and v0
                // before an ordinary tail call is the callee's argument.
                let isAsyncReturn = insn.controlFlow == .branch
                    && Self.indirectTarget(of: insn, in: registers) == .asyncResumeParent
                if isAsyncReturn, let value = registers["x20"], value != .unknown {
                    result.exitAsyncErrorValues[insn.address] = value
                }
                if insn.controlFlow == .return || isAsyncReturn,
                   let value = registers["v0"], value != .unknown {
                    result.exitFloatValues[insn.address] = value
                }
                // x1 at a return is the first yielded value of a `yield_once`
                // coroutine (`_modify`/`_read`); meaningless for an ordinary
                // return, so the enrichment reads it only for those accessors.
                if insn.controlFlow == .return,
                   let value = registers["x1"], value != .unknown {
                    result.exitYieldValues[insn.address] = value
                }
                if insn.controlFlow == .return {
                    let exit = Self.indirectResultExit(registers)
                    if exit.poisoned || exit.whole != nil || !exit.stores.isEmpty {
                        result.exitIndirectResults[insn.address] = exit
                    }
                }
                if insn.controlFlow == .branch {
                    let site = Self.snapshot(registers)
                    if !site.isEmpty { result.branchSites[insn.address] = site }
                }
                // A flags-based conditional branch: reconstruct its branch-taken
                // comparison from the tracked NZCV flags and the condition code.
                if insn.controlFlow == .conditionalBranch,
                   let condition = branchTakenCondition(insn, in: registers),
                   condition != .unknown {
                    // `branchTakenCondition` reconstructs cbz/cbnz/tbz (which carry
                    // no condition code) from the tested register's tracked value,
                    // as well as the flag-based `b.cond` forms — so a compare-and-
                    // branch on a named value (`cbnz x8` where x8 is `self.next`)
                    // reconstructs like the flag branches, not just as raw `x8`.
                    result.branchConditions[insn.address] = condition
                }
                let before = Probe.isActive ? registers : nil
                let writes = before == nil ? nil : TracerWriteLog()
                TracerWriteLog.$current.withValue(writes) { transfer(
                    insn, into: &registers,
                    record: { result.callSites[$0] = $1 },
                    recordAccess: { result.selfFieldAccesses[$0] = $1 },
                    recordArrayElement: { result.arrayElements[$0, default: [:]][$1] = $2 },
                    recordSlotStore: { result.asyncSlotStores[$0, default: []].append($1) },
                    initializerEntry: entry?.isObjectiveCInitializer == true,
                    addressTaken: addressTaken
                ) }
                if let before, let writes { Self.checkWritesModelled(insn, before: before, written: writes.keys) }
            }
        }
        for block in blocks where block.instructions.contains(where: { $0.controlFlow == .return }) {
            let preds = predecessors[block.startAddress] ?? []
            guard preds.count > 1 else { continue }
            for predecessor in preds {
                guard var registers = outState[predecessor],
                      let end = blockByStart[predecessor]?.instructions.last?.address else { continue }
                for insn in block.instructions {
                    if insn.controlFlow == .return {
                        // Every path is recorded, unknown included, so a
                        // consumer can tell "all paths throw" from "some do".
                        result.exitErrorValuesByPredecessor[insn.address, default: [:]][end] = registers["x21"] ?? .unknown
                        break
                    }
                    transfer(insn, into: &registers, record: nil, recordAccess: nil,
                             initializerEntry: entry?.isObjectiveCInitializer == true, addressTaken: addressTaken)
                }
            }
        }
        return result
    }

    /// The frame offsets of every local whose address the function computes
    /// (`add xN, sp|x29, #k`, `sub xN, x29, #k`, `mov xN, sp`), sorted. Each is
    /// a distinct variable, so it bounds how far a write through an earlier
    /// escaped address can reach. A linear scan, tracking sp and x29 through
    /// the prologue the way the tracer does; a base it misses only widens the
    /// invalidation, the safe direction.
    static func addressTakenFrameOffsets(_ instructions: [Instruction]) -> [Int64] {
        func immediate(_ text: Substring) -> Int64? {
            var t = text.trimmingCharacters(in: CharacterSet(charactersIn: " #]!"))
            let negative = t.hasPrefix("-")
            if negative { t.removeFirst() }
            let value = t.hasPrefix("0x") ? Int64(t.dropFirst(2), radix: 16) : Int64(t)
            return value.map { negative ? -$0 : $0 }
        }
        var sp: Int64 = 0
        var fp: Int64?
        var offsets = Set<Int64>()
        for instruction in instructions {
            let parts = instruction.text.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            let mnemonic = parts[0].lowercased()
            let operandText = parts[1].split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let ops = operandText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            // sp writeback: `[sp, #-0x20]!` and `[sp], #0x20`.
            if let bracket = ops.firstIndex(where: { $0.hasPrefix("[sp") }) {
                if ops[bracket].hasSuffix("]!") == false, ops.count > bracket + 1,
                   operandText.contains("!"), let delta = immediate(Substring(ops[bracket + 1])) {
                    sp += delta
                } else if ops[bracket] == "[sp]", ops.count > bracket + 1,
                          let delta = immediate(Substring(ops[bracket + 1])) {
                    sp += delta
                }
                continue
            }
            guard ops.count >= 2 else { continue }
            let (dest, source) = (ops[0], ops[1])
            let delta = ops.count >= 3 ? immediate(Substring(ops[2])) : nil
            switch (mnemonic, dest, source) {
            case ("sub", "sp", "sp"): if let delta { sp -= delta }
            case ("add", "sp", "sp"): if let delta { sp += delta }
            case ("add", "x29", "sp"): fp = sp + (delta ?? 0)
            case ("mov", "x29", "sp"): fp = sp
            case ("mov", _, "sp") where dest != "sp": offsets.insert(sp)
            case ("add", _, "sp") where dest != "sp": offsets.insert(sp + (delta ?? 0))
            case ("add", _, "x29") where dest != "sp" && dest != "x29":
                if let fp { offsets.insert(fp + (delta ?? 0)) }
            case ("sub", _, "x29") where dest != "sp" && dest != "x29":
                if let fp, let delta { offsets.insert(fp - delta) }
            default: break
            }
        }
        return offsets.sorted()
    }

    /// Whether a call cannot return a Swift error in x21: a C-level symbol (no
    /// `.` in its name: libc, the ObjC and Swift runtimes), or a demangled
    /// Swift function signature without `throws`. Everything else may throw:
    /// an unnamed callee (`sub_`, an indirect `blr`), a metadata-derived label
    /// with no signature (`Module.Type.method`), and an accessor, whose
    /// demangling never shows `throws` (`T.p.getter : Swift.Int` is printed
    /// the same for `get throws(E)`). Compiler-emitted value-witness helpers
    /// (`outlined copy of`, `outlined destroy of`, …) and metadata accessors
    /// cannot throw.
    /// Callees that read through the frame addresses they receive and never
    /// write them.
    private static let readOnlyPointerCallees: Set<String> = [
        "__swift_project_boxed_opaque_existential_1",
    ]

    private static let nonThrowingHelperPrefixes = [
        "outlined ", "merged outlined ", "type metadata accessor for ",
        "lazy protocol witness table accessor for ",
    ]

    static func provablyDoesNotThrow(_ callee: String) -> Bool {
        guard !callee.isEmpty, !callee.hasPrefix("sub_") else { return false }
        guard callee.contains(".") else { return true }
        if nonThrowingHelperPrefixes.contains(where: callee.hasPrefix) { return true }
        guard let signature = DisassembledFunction.splitSignature(callee) else { return false }
        return !signature.isThrowing
    }

    /// The abstract value in the register an indirect `blr`/`br`/pointer-auth
    /// variant branches through. Direct branches have an immediate operand and
    /// therefore return nil here.
    private static func indirectTarget(of insn: Instruction, in registers: State) -> AbstractValue? {
        guard let register = insn.detail?.operands.first?.operand.register,
              register.kind != .zero
        else { return nil }
        return registers[register.key] ?? .unknown
    }

    /// Call sites only — the common case.
    public func callSites(in function: DisassembledFunction) -> [UInt64: CallSite] {
        analyze(function).callSites
    }

    /// Run the transfer function over a short, straight-line instruction
    /// sequence from an empty state and return the resulting registers. Used to
    /// decode stub bodies, which are branch-free by construction.
    public func finalState(of instructions: [Instruction]) -> [String: AbstractValue] {
        var registers: State = [:]
        for insn in instructions {
            transfer(
                insn, into: &registers, record: nil, recordAccess: nil,
                initializerEntry: false
            )
        }
        return registers
    }


    /// One instruction's effect on the register state. At a call, snapshot the
    /// argument registers (via `record`) then apply AAPCS64 clobbering.
    private func transfer(
        _ insn: Instruction,
        into registers: inout State,
        record: ((UInt64, CallSite) -> Void)?,
        recordAccess: ((UInt64, SelfFieldAccess) -> Void)?,
        recordArrayElement: ((UInt64, Int, AbstractValue) -> Void)? = nil,
        recordSlotStore: ((Int, AbstractValue) -> Void)? = nil,
        initializerEntry: Bool = false,
        addressTaken: [Int64] = []
    ) {
        if insn.controlFlow == .call {
            let site = Self.snapshot(registers)
            if let record {
                if !site.isEmpty { record(insn.address, site) }
            }
            let incomingX0 = registers["x0"] ?? .unknown
            // `memcpy`/`memset` and the outlined value-witness copies are modelled
            // as the stores they perform (see `applyMemoryHelper`): their source
            // must be read before the invalidation below forgets it, and their
            // destination is written exactly, so the generic invalidation does
            // not apply to them.
            let calleeName = DisassembledFunction.calleeName(of: insn) ?? ""
            let handledAsMemoryHelper = applyMemoryHelper(callee: calleeName, site: site, into: &registers)
            // A local whose address the call receives may be written by it: an
            // NSError out-parameter (`str xzr, [sp]; mov x3, sp; bl …error:`),
            // an `inout` struct, an x8 result buffer, a `mutating` self in x20.
            // Keeping the pre-call value rendered the error a failed call
            // reported as the `nil` stored before it
            // (`_convertNSErrorToError(0)`, SwiftData). The callee may write a
            // whole aggregate through the pointer, of a size the binary does
            // not record, so each escaped local is forgotten up to the next
            // local whose address the function takes separately (a distinct
            // variable; `addressTakenFrameOffsets`), or to the frame top.
            // Incoming stack arguments (offsets >= 0) sit in the caller's area,
            // which a pointer into this frame cannot reach (`[super init…]`
            // passes `&objc_super`, and `self->_count = arg6` must survive it).
            let escapedOffsets: [Int64] = (["x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x20"]
                .compactMap { registers[$0] }
                + registers.filter { $0.key.hasPrefix(Self.outgoingPrefix) }.map(\.value))
                .compactMap { if case .frame(let offset) = $0 { return offset } else { return nil } }
            // A helper that only reads through its pointer leaves the local
            // intact: projecting an existential container yields a pointer to
            // its payload and must not erase the container's type and witness
            // words, or the witness-table call through them goes unresolved
            // (guarded by `resolvesConcreteWitnessTableDispatchIfPresent`).
            let readsOnly = DisassembledFunction.calleeName(of: insn)
                .map(Self.readOnlyPointerCallees.contains) ?? false
            for escaped in (readsOnly || handledAsMemoryHelper) ? [] : Set(escapedOffsets) {
                let end = escaped >= 0 ? Int64.max : (addressTaken.first { $0 > escaped } ?? 0)
                for key in registers.keys where key.hasPrefix("stack@") {
                    if let offset = Int64(key.dropFirst("stack@".count)), escaped <= offset, offset < end {
                        registers[key] = nil
                    }
                }
            }
            if !handledAsMemoryHelper { applyCallToResultBuffers(insn, site: site, into: &registers) }
            // AAPCS64: x0–x17 are caller-saved, so a call clobbers them. x18 is
            // reserved, x19–x28 are callee-saved — and preserving those is what
            // carries `self` and locals across a call.
            for index in 1...17 { registers["x\(index)"] = .unknown }
            registers["x30"] = .unknown
            // A callee handed the context (in an argument register; a call
            // reached with `bl` gets x22 only as callee-saved state) may write
            // it. `site` is the argument snapshot taken above.
            if site.arguments.contains(.asyncContext) || site.selfValue == .asyncContext {
                for key in registers.keys where key.hasPrefix(Self.contextSlotPrefix) { registers[key] = nil }
            }
            if let target = insn.branchTarget, let clobbered = calleeClobbers[target] {
                for key in clobbered { registers[key] = .unknown }
            }
            // The vector/floating-point bank: v0–v7 and v16–v31 are caller-saved
            // (only the low 64 bits of v8–v15 survive a call). Clobbering them is
            // what stops a stale `d0` from before the call being read as the
            // call's floating-point result after it.
            for index in 0...7 { registers["v\(index)"] = nil }
            for index in 16...31 { registers["v\(index)"] = nil }
            let outgoingKeys = registers.keys.filter { $0.hasPrefix(Self.outgoingPrefix) }
            for key in outgoingKeys { registers[key] = nil }
            let callee = DisassembledFunction.calleeName(of: insn) ?? ""
            // Swift error convention: a throwing callee returns its error in x21
            // (swifterror), so the call *redefines* x21 even though AAPCS64 marks
            // it callee-saved. Without invalidating it, a pre-call `mov x21, #0`
            // is read as a live value in the post-call error check and fabricates
            // an always-false `(0 != 0)` — a wrong render, the top severity. Gated
            // to a throwing callee (the demangled name carries ` throws`), so a C
            // or Objective-C call, where x21 is an ordinary callee-saved register
            // carrying a live value across the call, is untouched.
            if callee.contains(" throws") {
                registers["x21"] = .unknown
            }
            // The same convention when the name cannot say. Zeroing x21 right
            // before a call is how a caller arms swifterror, so unless the
            // callee provably does not throw, the post-call x21 is its error,
            // not that 0. Measured in SwiftData: an `@objc` thunk calling a
            // stripped throwing method rendered its error check `if (0 != 0)`
            // and its result `return 1`.
            if registers["x21"] == .immediate(0), !Self.provablyDoesNotThrow(callee) {
                registers["x21"] = .unknown
            }
            if Self.identityRuntimeCalls.contains(where: callee.hasPrefix) {
                registers["x0"] = incomingX0
            } else if callee.contains("_allocateUninitializedArray") {
                // Returns the array in x0 (and its element buffer in x1); the
                // caller fills it next, so tag it with this site and its count —
                // the first argument — so those element stores can be gathered.
                let count: Int = { if case .immediate(let n) = incomingX0 { return Int(n) } else { return -1 } }()
                registers["x0"] = .arrayLiteral(site: insn.address, count: count)
            } else if DisassembledFunction.splitSignature(callee)?.result == "()" {
                // A Swift callee returning Void leaves x0 holding whatever it
                // last computed. As a result, it rendered a value flowing on:
                // `OUTLINED_FUNCTION_35(Swift.Hasher._combine(0))` for a fragment
                // that takes nothing after `_combine(Swift.UInt) -> ()`.
                registers["x0"] = .unknown
                registers["v0"] = nil
            } else if initializerEntry, callee.hasPrefix("objc_msgSendSuper") {
                // `self = [super init…]`: after the assignment, the returned
                // object is the initializer's current self even if the runtime
                // chose a different allocation.
                registers["x0"] = .selfPointer
            } else {
                // The result register — x0 for integer/pointer/reference returns,
                // v0 for a floating-point one. The callee delivers into one; only
                // the register the caller actually reads next carries it forward,
                // so modelling the result in both is faithful.
                registers["x0"] = .callResult(insn.address)
                registers["v0"] = .callResult(insn.address)
            }
            registers[Self.selfFreshKey] = nil
            // AAPCS64 does not preserve NZCV across a call.
            registers[Self.flagsKey] = nil
            return
        }
        let hadSelf = registers[Self.selfFreshKey]
        apply(insn, into: &registers, recordAccess: recordAccess,
              recordArrayElement: recordArrayElement, recordSlotStore: recordSlotStore)
        if Self.writesSwiftSelf(insn) {
            registers[Self.selfFreshKey] = .immediate(1)
        } else {
            registers[Self.selfFreshKey] = hadSelf
        }
    }

    private static var identityRuntimeCalls: [String] {
        [
            "objc_retain", "objc_claimAutoreleasedReturnValue",
            "objc_retainAutoreleasedReturnValue", "objc_autoreleaseReturnValue",
        ]
    }

    /// AAPCS64 register snapshot shared by normal calls and possible tail-call
    /// branches. Keeping the construction identical prevents the two output
    /// paths from disagreeing about the same register state.
    private static func snapshot(_ registers: State) -> CallSite {
        let args = (0...7).map { registers["x\($0)"] ?? .unknown }
        var stackArguments: [AbstractValue] = []
        if case .frame(let stackBase)? = registers["sp"] {
            for slot in 0..<16 {
                let offset = stackBase + Int64(slot * 8)
                guard let value = registers[outgoingKey(offset)] else { break }
                stackArguments.append(value)
            }
        }
        return CallSite(
            arguments: trimTrailingUnknown(args) ?? [],
            floatArguments: (0...7).map { registers["v\($0)"] ?? .unknown },
            stackArguments: stackArguments,
            // Only when freshly set for *this* Swift call — see selfFreshKey.
            // The result pointer parked in callee-saved x20 (`mov x20, x8`) is
            // never a receiver, however fresh the write.
            selfValue: registers[selfFreshKey] != nil && !isResultPointer(registers["x20"])
                ? (registers["x20"] ?? .unknown) : .unknown,
            errorValue: registers["x21"] ?? .unknown,
            indirectResult: registers["x8"] ?? .unknown
        )
    }

    /// Marks that x20 was written since the last call, i.e. that the caller set
    /// it up *for the upcoming call*.
    ///
    /// x20 is callee-saved, so a value placed there for one call survives into
    /// later ones. Without this, a Swift callee whose `self` isn't in x20 at all
    /// — `Double.write(to:)`, whose self is a Double in d0 — would inherit the
    /// previous call's x20 and report it as its own `self`. Requiring a fresh
    /// write trades a missed `self` (when the compiler doesn't re-materialise an
    /// unchanged x20) for never inventing one.
    private static let selfFreshKey = "swiftself.fresh"

    private static func writesSwiftSelf(_ insn: Instruction) -> Bool {
        guard let detail = insn.detail else { return false }
        // Branches write no general register.
        if let flow = insn.controlFlow, flow != .sequential { return false }
        switch detail.id {
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP, AARCH64_INS_STNP,
             AARCH64_INS_ALIAS_CMP, AARCH64_INS_ALIAS_CMN, AARCH64_INS_ALIAS_TST, AARCH64_INS_CCMP, AARCH64_INS_CCMN:
            // These name a register first but read it.
            return false
        case AARCH64_INS_LDP, AARCH64_INS_LDNP:
            return detail.operands.prefix(2).contains { $0.operand.register?.key == "x20" }
        default:
            return detail.operands.first?.operand.register?.key == "x20"
        }
    }

    /// Meet (∧) of predecessor states: a register keeps its value only when all
    /// predecessors agree; otherwise it becomes unknown (absent).
    ///
    /// The one exception is the result-buffer poison marker, which is a union:
    /// a result pointer that escaped on ANY incoming path leaves the buffer
    /// unprovable at the join, even where the other paths agree on its contents.
    private static func meet(_ states: [State]) -> State {
        guard var accumulator = states.first else { return [:] }
        for state in states.dropFirst() {
            accumulator = accumulator.filter { state[$0.key] == $0.value }
        }
        if states.contains(where: { $0[resultPoisonKey] != nil }) {
            accumulator[resultPoisonKey] = .immediate(1)
        }
        return accumulator
    }

    // MARK: - Indirect result buffers

    /// The buffer-contents keys: `result@<offset>/<bytes>` for a store through the
    /// incoming x8, plus the whole-buffer and poison markers. They live in the
    /// register map so the block meet treats them like any other slot.
    private static let resultPrefix = "result@"
    private static let resultWholeKey = "result.whole"
    private static let resultPoisonKey = "result.poison"
    private static func resultKey(_ offset: Int, bytes: Int) -> String { "\(resultPrefix)\(offset)/\(bytes)" }
    private static func resultOffset(from key: String) -> (offset: Int, bytes: Int)? {
        guard key.hasPrefix(resultPrefix) else { return nil }
        let parts = key.dropFirst(resultPrefix.count).split(separator: "/")
        guard parts.count == 2, let offset = Int(parts[0]), let bytes = Int(parts[1]) else { return nil }
        return (offset, bytes)
    }

    /// Whether a value is (an alias of) the incoming result pointer.
    private static func isResultPointer(_ value: AbstractValue?) -> Bool {
        switch value {
        case .indirectResultPointer?, .indirectResultField?: return true
        default: return false
        }
    }

    private static func poisonResult(_ registers: inout State) {
        registers[resultPoisonKey] = .immediate(1)
    }

    /// Record a store of `bytes` bytes at `offset` of the result buffer. A store
    /// wider than a word (a `q` register) is split into words; one whose value is
    /// not word-decomposable fills its words with `.unknown`, which still counts
    /// as covering the field (its VALUE is unknown, the write is not). A store
    /// over a whole-buffer call fill is a partial overwrite: the buffer is then
    /// neither the call's result nor a complete set of stores, so it poisons.
    private static func storeResult(_ value: AbstractValue, at offset: Int, bytes: Int, into registers: inout State) {
        if registers[resultWholeKey] != nil {
            registers[resultWholeKey] = nil
            poisonResult(&registers)
        }
        // An overlapping earlier store is superseded (a word store over a byte
        // store, or the reverse).
        let range = offset ..< (offset + bytes)
        for key in registers.keys {
            guard let existing = resultOffset(from: key),
                  (existing.offset ..< (existing.offset + existing.bytes)).overlaps(range)
            else { continue }
            registers[key] = nil
        }
        if bytes > 8 {
            let words: [AbstractValue]
            if case .aggregate(let packed) = value { words = packed } else { words = [] }
            for index in 0 ..< (bytes / 8) {
                registers[resultKey(offset + index * 8, bytes: 8)] = index < words.count ? words[index] : .unknown
            }
        } else {
            registers[resultKey(offset, bytes: bytes)] = value
        }
    }

    /// The buffer state at a `ret`.
    private static func indirectResultExit(_ registers: State) -> IndirectResultExit {
        var exit = IndirectResultExit()
        exit.poisoned = registers[resultPoisonKey] != nil
        if case .callResult(let site)? = registers[resultWholeKey] { exit.whole = site }
        for (key, value) in registers {
            guard let location = resultOffset(from: key) else { continue }
            exit.stores[location.offset] = IndirectResultExit.Store(bytes: location.bytes, value: value)
        }
        return exit
    }

    /// Whether this instruction uses a result-pointer register in a role the
    /// tracker does not model: anything other than a copy (`mov`), a constant
    /// offset (`add`/`sub` immediate), a memory base with a constant
    /// displacement, or a spill of the pointer itself to the stack. Any other
    /// use (`csel`, a register-indexed address, arithmetic with a register, a
    /// shifted operand, …) derives an alias the tracker then cannot see stores
    /// through, so the buffer must be treated as unprovable from here on.
    private func derivesUntrackedResultAlias(_ detail: StructuredInsn, in registers: State) -> Bool {
        let holdsPointer: (StructuredOperandInfo) -> Bool = { operand in
            guard let register = operand.operand.register else { return false }
            return Self.isResultPointer(registers[register.key])
        }
        let operands = detail.operands
        // Memory operands: a result-pointer base is modelled only with no index
        // register; a result pointer as the INDEX is never modelled.
        for operand in operands {
            if case .memory(let base, let index, _) = operand.operand {
                if let index, Self.isResultPointer(registers[index.key]) { return true }
                if let base, Self.isResultPointer(registers[base.key]) {
                    if index != nil { return true }
                    if detail.writeback { return true } // pre/post-index rewrites the pointer
                }
            }
        }
        let registerSources = operands.enumerated().filter { $0.element.operand.register != nil }
        guard registerSources.contains(where: { holdsPointer($0.element) }) else { return false }
        switch detail.id {
        case AARCH64_INS_MOV:
            return false
        case AARCH64_INS_ADD, AARCH64_INS_SUB:
            // `add xd, xptr, #imm` is a field address (modelled); the destination
            // merely having held the pointer is an overwrite. A register addend
            // or a pointer on the right-hand side derives an untracked alias.
            guard operands.count >= 3 else { return true }
            if operands[2].shiftedImmediate != nil { return false }
            return holdsPointer(operands[1]) || holdsPointer(operands[2])
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP, AARCH64_INS_STNP,
             AARCH64_INS_STRB, AARCH64_INS_STURB, AARCH64_INS_STRH, AARCH64_INS_STURH:
            // Storing the pointer itself is fine only into a stack slot (a spill
            // the tracker reloads by key); into any other memory it escapes.
            // A pointer used only as the base is the modelled case.
            let storesPointerValue = operands.prefix(detail.id == AARCH64_INS_STP || detail.id == AARCH64_INS_STNP ? 2 : 1)
                .contains(where: holdsPointer)
            guard storesPointerValue else { return false }
            if case .stackSlot? = memoryTarget(detail, in: registers) { return false }
            return true
        case AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDP, AARCH64_INS_LDNP,
             AARCH64_INS_LDRB, AARCH64_INS_LDURB, AARCH64_INS_LDRH, AARCH64_INS_LDURH,
             AARCH64_INS_LDRSB, AARCH64_INS_LDURSB, AARCH64_INS_LDRSH, AARCH64_INS_LDURSH,
             AARCH64_INS_LDRSW, AARCH64_INS_LDURSW:
            // A load through the pointer is modelled; the destination register
            // merely having held the pointer is an overwrite.
            return false
        case AARCH64_INS_ALIAS_CMP, AARCH64_INS_ALIAS_CMN, AARCH64_INS_ALIAS_TST, AARCH64_INS_CCMP, AARCH64_INS_CCMN:
            // Comparing the pointer derives nothing stored through.
            return false
        default:
            // Any other instruction reading the pointer (a `csel`, `orr`, `lsl`,
            // `madd`, …) derives an alias; one that only WRITES a register that
            // held it is an overwrite and harmless.
            let reads = registerSources.dropFirst()
            if detail.id == AARCH64_INS_LDP || detail.id == AARCH64_INS_LDNP { return false }
            return reads.contains(where: { holdsPointer($0.element) })
        }
    }

    /// What a call does to the result buffers in play:
    ///
    /// - The caller's OWN result pointer in an argument register escapes (the
    ///   callee may write anything through it), except for the fixed-ABI memory
    ///   helpers, which are modelled as the copies they are.
    /// - The caller's own result pointer forwarded in x8 means the callee writes
    ///   the caller's result: the whole buffer becomes that call's result, but
    ///   only for a callee proven to write through x8. A callee proven direct
    ///   ignores x8; an unknown callee poisons, since x8 may be a scratch value
    ///   or a real forward and the two cannot be told apart.
    /// - x8 pointing into the caller's frame means a proven indirect callee
    ///   writes its result there: those slots become words of the call's result
    ///   when the size is known. (The escaped-local invalidation in `transfer`
    ///   has already forgotten the slots any callee could have written.)
    private func applyCallToResultBuffers(_ insn: Instruction, site: CallSite, into registers: inout State) {
        // Only the argument registers can hand the pointer to a callee: Swift
        // never passes an indirect-result address on the stack, so a spill of
        // it at `[sp]` (which the snapshot speculatively lists as a possible
        // stack argument) is a frame slot, not an escape.
        if site.arguments.contains(where: { Self.isResultPointer($0) }) { Self.poisonResult(&registers) }

        let convention = calleeConventions[insn.address]
        switch registers["x8"] {
        case .indirectResultPointer?:
            switch convention {
            case .indirect?:
                for key in registers.keys where Self.resultOffset(from: key) != nil { registers[key] = nil }
                registers[Self.resultWholeKey] = .callResult(insn.address)
            case .direct?:
                break
            case nil:
                Self.poisonResult(&registers)
            }
        case .indirectResultField?:
            // A callee filling only part of the buffer is not reconstructed.
            if convention != .direct { Self.poisonResult(&registers) }
        case .frame(let base)?:
            switch convention {
            case .direct?:
                break
            case .indirect(let size?)?:
                Self.clearStack(from: base, to: base + Int64(size), in: &registers)
                for offset in stride(from: 0, to: size, by: 8) {
                    registers[Self.stackKey(base + Int64(offset))] =
                        .indirectCallResultWord(site: insn.address, offset: offset)
                }
            case .indirect(nil)?, nil:
                break // already forgotten by the escaped-local invalidation above
            }
        default:
            break
        }
    }

    /// Drop the stack slots in `[from, to)` (`to == nil`: every slot at or above
    /// `from`), the region a callee may have written through x8.
    private static func clearStack(from: Int64, to: Int64?, in registers: inout State) {
        for key in registers.keys {
            guard let offset = stackOffset(from: key), offset >= from else { continue }
            if let to, offset >= to { continue }
            registers[key] = nil
        }
    }

    /// Model `memcpy`/`memmove`/`memset` (and the compiler's outlined
    /// `__swift_memcpyN_M` value-witness copies) as the stores they perform, so a
    /// result assembled in a local and then copied into the x8 buffer, or a
    /// buffer zeroed with `memset`, is tracked rather than lost. Only a constant
    /// length is modelled; anything else falls through to the generic call
    /// handling, where a result pointer in an argument poisons the buffer.
    private func applyMemoryHelper(callee: String, site: CallSite, into registers: inout State) -> Bool {
        let name = callee.hasPrefix("_") ? String(callee.drop(while: { $0 == "_" })) : callee
        guard site.arguments.count >= 2 else { return false }
        let destination = site.arguments[0]
        let length: Int?
        let isCopy: Bool
        if name == "memcpy" || name == "memmove" {
            guard site.arguments.count >= 3, case .immediate(let n) = site.arguments[2] else { return false }
            length = Int(exactly: n); isCopy = true
        } else if name == "memset" {
            guard site.arguments.count >= 3, case .immediate(let n) = site.arguments[2] else { return false }
            length = Int(exactly: n); isCopy = false
        } else if name.hasPrefix("swift_memcpy"),
                  let n = Int(name.dropFirst("swift_memcpy".count).split(separator: "_").first ?? "") {
            length = n; isCopy = true
        } else {
            return false
        }
        guard let length, length >= 0, length <= 4096 else { return false }

        // The bytes being written, as (offsetInRegion, bytes, value).
        var chunks: [(offset: Int, bytes: Int, value: AbstractValue)] = []
        var offset = 0
        while offset < length {
            let bytes = min(8, length - offset)
            let value: AbstractValue
            if isCopy {
                switch site.arguments[1] {
                case .frame(let source):
                    value = registers[Self.stackKey(source + Int64(offset))] ?? .unknown
                case .indirectResultPointer:
                    value = registers[Self.resultKey(offset, bytes: bytes)] ?? .unknown
                case .indirectResultField(let base):
                    value = registers[Self.resultKey(base + offset, bytes: bytes)] ?? .unknown
                default:
                    value = .unknown
                }
            } else if case .immediate(let byte) = site.arguments[1] {
                let pattern = (byte & 0xFF) &* 0x0101_0101_0101_0101
                value = .immediate(bytes == 8 ? pattern : pattern & ((1 << (UInt64(bytes) * 8)) - 1))
            } else {
                value = .unknown
            }
            chunks.append((offset, bytes, value))
            offset += bytes
        }

        switch destination {
        case .indirectResultPointer:
            for chunk in chunks { Self.storeResult(chunk.value, at: chunk.offset, bytes: chunk.bytes, into: &registers) }
        case .indirectResultField(let base):
            for chunk in chunks { Self.storeResult(chunk.value, at: base + chunk.offset, bytes: chunk.bytes, into: &registers) }
        case .frame(let base):
            Self.clearStack(from: base, to: base + Int64(length), in: &registers)
            for chunk in chunks {
                Self.storeStack(chunk.value, at: base + Int64(chunk.offset), bytes: chunk.bytes,
                                outgoing: false, into: &registers)
            }
        default:
            // An untracked destination: if the SOURCE is the result buffer the
            // contents merely leak out (harmless to provability); a result
            // pointer anywhere else in the arguments already escaped.
            if Self.isResultPointer(destination) { Self.poisonResult(&registers) }
            return false
        }
        return true
    }

    /// Reconstruct the select at each control-flow diamond: a join with two
    /// predecessors that are the two arms of one conditional branch. A register
    /// or stack slot that differs across the arms is `cond ? taken : fall` — the
    /// shape of a ternary or nil-coalescing. Enriches the join's entry state so
    /// the snapshot pass carries the select to its use (usually a return).
    ///
    /// Deliberately conservative: only a clean 2-arm diamond whose deciding
    /// condition is itself recoverable produces a select; a loop back-edge, a
    /// three-way join, or an unrecoverable condition leaves the value dropping to
    /// `.unknown` as before, rather than inventing a merge.
    private func resolveDiamondSelects(
        blocks: [BasicBlock],
        predecessors: [UInt64: [UInt64]],
        blockByStart: [UInt64: BasicBlock],
        inState: inout [UInt64: State],
        outState: [UInt64: State]
    ) {
        // The chain of blocks above `start` reachable by single-predecessor
        // hops — the straight-line run of one diamond arm up to the split.
        func ancestorChain(from start: UInt64) -> [UInt64] {
            var chain = [start], current = start
            while let preds = predecessors[current], preds.count == 1,
                  blockByStart[preds[0]] != nil, chain.count < 32 {
                current = preds[0]
                chain.append(current)
            }
            return chain
        }

        for block in blocks {
            guard let preds = predecessors[block.startAddress], preds.count == 2 else { continue }
            let (p1, p2) = (preds[0], preds[1])
            let chain1 = ancestorChain(from: p1), chain2 = ancestorChain(from: p2)
            let chain2Set = Set(chain2)
            // The decider is the first block common to both arms' chains.
            guard let decider = chain1.first(where: chain2Set.contains),
                  let deciderBlock = blockByStart[decider],
                  let terminator = deciderBlock.instructions.last,
                  let deciderOut = outState[decider],
                  let out1 = outState[p1], let out2 = outState[p2],
                  let taken = terminator.branchTarget
            else { continue }
            // A clean diamond: the two arms are disjoint before the decider.
            let arm1 = chain1.prefix(while: { $0 != decider })
            let arm2 = chain2.prefix(while: { $0 != decider })
            guard Set(arm1).isDisjoint(with: Set(arm2)) else { continue }
            // Which arm the branch-taken edge reaches.
            let takenInArm1 = chain1.contains(taken), takenInArm2 = chain2.contains(taken)
            guard takenInArm1 != takenInArm2 else { continue }
            let takenOut = takenInArm1 ? out1 : out2
            let fallOut = takenInArm1 ? out2 : out1
            guard let condition = branchTakenCondition(terminator, in: deciderOut) else { continue }

            var enriched = inState[block.startAddress] ?? [:]
            for key in Set(out1.keys).union(out2.keys) where out1[key] != out2[key] {
                guard let whenTrue = takenOut[key], whenTrue != .unknown,
                      let whenFalse = fallOut[key], whenFalse != .unknown,
                      Self.expressionDepth(whenTrue) < 6, Self.expressionDepth(whenFalse) < 6
                else { continue }
                enriched[key] = .select(condition: condition, whenTrue: whenTrue, whenFalse: whenFalse)
            }
            inState[block.startAddress] = enriched
        }
    }

    /// Value merging for a **switch over a tag** — the N-way generalization of a
    /// diamond. A `switch e { case .a: v0; case .b: v1; … }` lowers to a cascade
    /// of `tag == k` tests, each branching to a block that stores its case value
    /// and jumps to a common merge; the merge's value is the nested select
    /// `tag == k0 ? v0 : (tag == k1 ? v1 : … : default)`.
    ///
    /// Gated to the provably-correct shape: every case arm is reached by the
    /// TAKEN edge of a distinct decider whose condition is `X == const` for one
    /// common `X` and pairwise-distinct constants, plus exactly one fall-through
    /// (default) arm. Distinct-constant equality guarantees the cases are
    /// mutually exclusive, so the nested select is order-independent and faithful
    /// regardless of block layout. Anything else — a mixed-operator cascade
    /// (`x < 0` then `x == 0`), a shared decider, no clean default — declines,
    /// leaving the value unmerged rather than guessing an ordering.
    private func resolveSwitchSelects(
        blocks: [BasicBlock],
        predecessors: [UInt64: [UInt64]],
        blockByStart: [UInt64: BasicBlock],
        inState: inout [UInt64: State],
        outState: [UInt64: State]
    ) {
        /// The nearest ancestor of `arm` whose terminator is a conditional branch,
        /// reached by single-predecessor hops, plus whether `arm`'s chain leaves
        /// that decider on its taken (branch-target) or fall-through edge.
        func immediateDecider(of arm: UInt64) -> (decider: UInt64, viaTaken: Bool)? {
            var current = arm, hops = 0
            while let preds = predecessors[current], preds.count == 1, hops < 32 {
                let pred = preds[0]
                guard let predBlock = blockByStart[pred],
                      let terminator = predBlock.instructions.last else { return nil }
                if terminator.controlFlow == .conditionalBranch {
                    return (pred, terminator.branchTarget == current)
                }
                current = pred
                hops += 1
            }
            return nil
        }

        /// The `(comparedValue, constant)` of an `X == const` condition, immediate
        /// on either side; nil for any other shape.
        func equalityTest(_ condition: AbstractValue) -> (value: AbstractValue, constant: UInt64)? {
            guard case .binary(.equal, let lhs, let rhs) = condition else { return nil }
            if case .immediate(let k) = rhs { return (lhs, k) }
            if case .immediate(let k) = lhs { return (rhs, k) }
            return nil
        }

        /// The condition under which an arm is actually reached: the decider's
        /// taken condition directly for a taken arm, negated for a fall-through
        /// arm. This unifies the two switch lowerings — `case k` reached by
        /// `tag == k` taken (enums) or by `tag != k` fall-through (integers) —
        /// into one `tag == k` reaching condition.
        func reachingCondition(_ taken: AbstractValue, viaTaken: Bool) -> AbstractValue {
            if viaTaken { return taken }
            guard case .binary(let op, let lhs, let rhs) = taken else { return taken }
            let inverse: AbstractBinaryOperator?
            switch op {
            case .equal: inverse = .notEqual
            case .notEqual: inverse = .equal
            case .less: inverse = .greaterEqual
            case .lessEqual: inverse = .greater
            case .greater: inverse = .lessEqual
            case .greaterEqual: inverse = .less
            default: inverse = nil
            }
            return inverse.map { .binary($0, lhs, rhs) } ?? taken
        }

        for block in blocks {
            guard let preds = predecessors[block.startAddress], preds.count >= 3,
                  preds.count <= 16
            else { continue }

            // Classify each predecessor arm as a taken case (with its `X == k`
            // condition and value source) or the single fall-through default.
            struct CaseArm { let condition: AbstractValue; let comparedValue: AbstractValue; let constant: UInt64; let out: State }
            var caseArms: [CaseArm] = []
            var defaultArm: State?
            var deciders = Set<UInt64>()
            var comparedValue: AbstractValue?
            var constants = Set<UInt64>()
            var wellFormed = true

            for pred in preds {
                guard let decided = immediateDecider(of: pred),
                      let deciderBlock = blockByStart[decided.decider],
                      let terminator = deciderBlock.instructions.last,
                      let deciderOut = outState[decided.decider],
                      let out = outState[pred]
                else { wellFormed = false; break }

                // An arm is a `case k` when its reaching condition is `X == k`;
                // the one arm that isn't is the `default`. This subsumes both the
                // taken-edge (`tag == k`) and fall-through (`tag != k`) lowerings.
                let reach = (branchTakenCondition(terminator, in: deciderOut))
                    .map { reachingCondition($0, viaTaken: decided.viaTaken) }
                if let reach, let test = equalityTest(reach) {
                    // Distinct decider per case, one shared `X`, a fresh constant.
                    guard deciders.insert(decided.decider).inserted,
                          constants.insert(test.constant).inserted
                    else { wellFormed = false; break }
                    if let existing = comparedValue, existing != test.value { wellFormed = false; break }
                    comparedValue = test.value
                    caseArms.append(CaseArm(condition: reach, comparedValue: test.value,
                                            constant: test.constant, out: out))
                } else {
                    guard defaultArm == nil else { wellFormed = false; break } // one default only
                    defaultArm = out
                }
            }

            guard wellFormed, let defaultOut = defaultArm, caseArms.count >= 2,
                  caseArms.count == preds.count - 1
            else { continue }

            // Smallest constant outermost, matching source case order.
            let ordered = caseArms.sorted { $0.constant < $1.constant }
            var enriched = inState[block.startAddress] ?? [:]
            let allKeys = ordered.reduce(into: Set(defaultOut.keys)) { $0.formUnion($1.out.keys) }
            for key in allKeys {
                let values = ordered.map { $0.out[key] ?? .unknown } + [defaultOut[key] ?? .unknown]
                // Only a key that actually diverges across the arms is a merge.
                guard values.contains(where: { $0 != values[0] }) else { continue }
                guard let defaultValue = defaultOut[key], defaultValue != .unknown,
                      Self.expressionDepth(defaultValue) < 6
                else { continue }
                var merged = defaultValue
                var ok = true
                for arm in ordered.reversed() {
                    guard let value = arm.out[key], value != .unknown,
                          Self.expressionDepth(value) < 6
                    else { ok = false; break }
                    merged = .select(condition: arm.condition, whenTrue: value, whenFalse: merged)
                }
                if ok { enriched[key] = merged }
            }
            inState[block.startAddress] = enriched
        }
    }

    // MARK: - Loop induction variables

    /// Name loop-carried induction variables so a loop's exit comparison
    /// reconstructs (`i < n`) instead of raw registers. For each back-edge
    /// `u → h`, a stack slot with a proven constant value on loop entry that the
    /// header's `meet` dropped (i.e. loop-carried) and that has a proven
    /// `slot = i ± c` recurrence across the back-edge is seeded `.local(id)` at
    /// the header. Hard-gated: single-back-edge reducible loops, a linear
    /// `± constant` step only; anything unproven is left `.unknown` (declined).
    private func resolveLoopInductions(
        blocks: [BasicBlock],
        predecessors: [UInt64: [UInt64]],
        blockByStart: [UInt64: BasicBlock],
        inState: inout [UInt64: State],
        outState: [UInt64: State],
        addressTaken: [Int64]
    ) -> [UInt64: [String]] {
        var updates: [UInt64: [String]] = [:]
        var sourcesByHeader: [UInt64: [UInt64]] = [:]
        for (from, header) in Self.backEdges(blocks: blocks, blockByStart: blockByStart) {
            sourcesByHeader[header, default: []].append(from)
        }
        var displayId = 0
        for header in sourcesByHeader.keys.sorted() {
            guard let sources = sourcesByHeader[header], sources.count == 1,
                  let backFrom = sources.first else { continue }  // simple reducible loop only
            let preds = predecessors[header] ?? []
            let preLoopPreds = preds.filter { $0 != backFrom }
            guard !preLoopPreds.isEmpty else { continue }
            let preLoopEntry = Self.meet(preLoopPreds.compactMap { outState[$0] })
            guard let body = Self.naturalLoopBody(
                header: header, backFrom: backFrom,
                predecessors: predecessors, blockByStart: blockByStart
            ) else { continue }
            let headerIn = inState[header] ?? [:]
            // Candidate slots (deterministic by key): a constant value on loop
            // entry that `meet` dropped at the header (loop-carried / divergent).
            let candidateKeys = preLoopEntry.keys.filter { key in
                guard key.hasPrefix("stack@"), case .immediate = preLoopEntry[key] else { return false }
                return (headerIn[key] ?? .unknown) == .unknown
            }.sorted()
            guard !candidateKeys.isEmpty else { continue }
            // Seed each candidate with a fresh placeholder and re-transfer the loop
            // body so the back-edge value is expressed in terms of the placeholder.
            var seed = preLoopEntry
            var placeholderId: [Int: String] = [:]
            for (offset, key) in candidateKeys.enumerated() {
                seed[key] = .local(offset)
                placeholderId[offset] = key
            }
            let bodyOut = retransferBody(
                body: body, header: header, headerSeed: seed,
                blockByStart: blockByStart, predecessors: predecessors,
                addressTaken: addressTaken
            )
            guard let backOut = bodyOut[backFrom] else { continue }
            // The compared slot is the one the header's loop test references — the
            // `.local` placeholder in the re-transferred compare flags. It is the
            // primary induction variable `i`; naming from it (not the `-Onone`
            // redundant copies) keeps phantom variables out and matches the body
            // updates to the condition. A genuine loop variable is a SELF-recurrence
            // (its back-edge value references its own placeholder); the copies
            // reference other placeholders and are ignored.
            guard let comparedPid = Self.comparedInductionId(in: bodyOut[header]?[Self.flagsKey]),
                  let comparedKey = placeholderId[comparedPid],
                  let comparedRec = backOut[comparedKey],
                  Self.isInductionRecurrence(comparedRec, id: comparedPid)
            else { continue }
            // Only the primary induction variable is named in `inState` (the loop
            // condition reads it); accumulators/secondaries are unread at the
            // header and only contribute a baked body-update statement.
            var names: [Int: String] = [comparedPid: Disassembler.inductionVariableName(displayId)]
            inState[header, default: [:]][comparedKey] = .local(displayId)
            displayId += 1
            // Loop-carried accumulators / secondary counters: other self-recurrence
            // slots whose per-iteration addend renders in terms of already-named
            // variables (`total += i`, `seen += 1`). Rendered BEFORE the primary
            // increment (accumulate, then advance).
            var accumulatorId = 0
            var bodyUpdates: [String] = []
            for pid in placeholderId.keys.sorted() where pid != comparedPid {
                guard let key = placeholderId[pid], let rec = backOut[key],
                      let (symbol, addend, isAccumulator) = Self.selfRecurrenceUpdate(rec, ownId: pid, names: names)
                else { continue }
                let varName: String
                if isAccumulator { varName = Self.accumulatorName(accumulatorId); accumulatorId += 1 }
                else { varName = Disassembler.inductionVariableName(displayId); displayId += 1 }
                names[pid] = varName
                bodyUpdates.append("\(varName) \(symbol) \(addend)")
            }
            if let primary = Self.inductionUpdate(comparedRec, id: comparedPid, name: names[comparedPid]!) {
                bodyUpdates.append(primary)
            }
            if let branchAddr = blockByStart[header]?.instructions.last?.address, !bodyUpdates.isEmpty {
                updates[branchAddr] = bodyUpdates
            }
        }
        return updates
    }

    /// The placeholder id of the induction operand in a header's compare flags
    /// (`i - n`), or nil when neither side is a seeded induction placeholder.
    private static func comparedInductionId(in flags: AbstractValue?) -> Int? {
        guard case .binary(.subtract, let a, let b)? = flags else { return nil }
        if case .local(let id) = a { return id }
        if case .local(let id) = b { return id }
        return nil
    }

    /// Render a proven linear recurrence as the body update `name += c` / `-= c`.
    private static func inductionUpdate(_ recurrence: AbstractValue, id: Int, name: String) -> String? {
        guard case .binary(let op, let a, let b) = recurrence else { return nil }
        func isLocal(_ v: AbstractValue) -> Bool { if case .local(let x) = v { return x == id }; return false }
        func constOf(_ v: AbstractValue) -> UInt64? { if case .immediate(let c) = v { return c }; return nil }
        let step: UInt64?
        let add: Bool
        switch op {
        case .add: add = true; step = isLocal(a) ? constOf(b) : (isLocal(b) ? constOf(a) : nil)
        case .subtract: add = false; step = isLocal(a) ? constOf(b) : nil
        default: return nil
        }
        guard let c = step, c != 0 else { return nil }
        return "\(name) \(add ? "+=" : "-=") \(c)"
    }

    /// A loop-carried accumulator / secondary counter as `(op, addend, isAccumulator)`
    /// for a slot whose back-edge value is a SELF-recurrence `own ± addend`, where
    /// the addend is either a constant (a secondary counter, `seen += 1`) or a
    /// single already-named loop variable (an accumulator, `total += i`). Anything
    /// else — a non-self recurrence (a copy), a complex addend (`i * 2`), or an
    /// addend referencing an unnamed placeholder — returns nil (declined).
    private static func selfRecurrenceUpdate(
        _ recurrence: AbstractValue, ownId: Int, names: [Int: String]
    ) -> (symbol: String, addend: String, isAccumulator: Bool)? {
        guard case .binary(let op, let a, let b) = recurrence else { return nil }
        func isOwn(_ v: AbstractValue) -> Bool { if case .local(let x) = v { return x == ownId }; return false }
        let symbol: String
        let addend: AbstractValue
        switch op {
        case .add:
            symbol = "+="
            if isOwn(a) { addend = b } else if isOwn(b) { addend = a } else { return nil }
        case .subtract:
            symbol = "-="
            if isOwn(a) { addend = b } else { return nil }  // `own - x` only
        default:
            return nil
        }
        switch addend {
        case .immediate(let c) where c != 0:
            return (symbol, Disassembler.renderImmediate(c), false)
        case .local(let pid):
            guard let name = names[pid] else { return nil }  // decline an unnamed placeholder
            return (symbol, name, true)
        default:
            return nil   // decline a complex addend (`i * 2`, a call result, …)
        }
    }

    /// Name a loop-carried accumulator — `sum`, `acc`, then `sum2`, …
    private static func accumulatorName(_ id: Int) -> String {
        ["sum", "acc"].indices.contains(id) ? ["sum", "acc"][id] : "sum\(id)"
    }

    /// Back-edges `(from, header)`: DFS edges to a node still on the recursion
    /// stack (gray). Iterative, so a deep CFG can't overflow the stack.
    private static func backEdges(
        blocks: [BasicBlock], blockByStart: [UInt64: BasicBlock]
    ) -> [(UInt64, UInt64)] {
        guard let entry = blocks.first?.startAddress else { return [] }
        var color: [UInt64: Int] = [:]  // 0/absent white, 1 gray, 2 black
        var result: [(UInt64, UInt64)] = []
        var stack: [(node: UInt64, next: Int)] = [(entry, 0)]
        color[entry] = 1
        while let top = stack.last {
            let u = top.node
            let succs = blockByStart[u]?.successors.filter { blockByStart[$0] != nil } ?? []
            if top.next < succs.count {
                stack[stack.count - 1].next += 1
                let v = succs[top.next]
                if color[v] == 1 { result.append((u, v)) }
                else if (color[v] ?? 0) == 0 { color[v] = 1; stack.append((v, 0)) }
            } else {
                color[u] = 2
                stack.removeLast()
            }
        }
        return result
    }

    /// The natural loop of back-edge `backFrom → header`: `{header}` plus every
    /// node that can reach `backFrom` without passing through `header`.
    private static func naturalLoopBody(
        header: UInt64, backFrom: UInt64,
        predecessors: [UInt64: [UInt64]], blockByStart: [UInt64: BasicBlock]
    ) -> Set<UInt64>? {
        var body: Set<UInt64> = [header]
        var work: [UInt64] = []
        if backFrom != header { body.insert(backFrom); work.append(backFrom) }
        while let n = work.popLast() {
            for p in predecessors[n] ?? [] where !body.contains(p) && blockByStart[p] != nil {
                body.insert(p); work.append(p)
            }
        }
        return body
    }

    /// Re-run the transfer over just the loop body, with the header's entry state
    /// FIXED to `headerSeed` (so the seeded induction placeholders are not merged
    /// away by the back-edge). Bounded mini-fixpoint; internal joins meet over
    /// body predecessors. Returns each body block's exit state.
    private func retransferBody(
        body: Set<UInt64>, header: UInt64, headerSeed: State,
        blockByStart: [UInt64: BasicBlock], predecessors: [UInt64: [UInt64]],
        addressTaken: [Int64]
    ) -> [UInt64: State] {
        var outS: [UInt64: State] = [:]
        var worklist = [header]
        var queued: Set<UInt64> = [header]
        var iterations = 0
        let cap = body.count * 8 + 8
        while let addr = worklist.first {
            worklist.removeFirst(); queued.remove(addr)
            iterations += 1
            if iterations > cap {
                Probe.record(.tracerLoopBodyCap, at: header, ["blocks": .int(body.count), "cap": .int(cap)])
                break
            }
            guard let block = blockByStart[addr] else { continue }
            let entry: State
            if addr == header {
                entry = headerSeed
            } else {
                let bodyPreds = (predecessors[addr] ?? []).filter { body.contains($0) }
                entry = Self.meet(bodyPreds.compactMap { outS[$0] })
            }
            var registers = entry
            for insn in block.instructions {
                transfer(insn, into: &registers, record: nil, recordAccess: nil, addressTaken: addressTaken)
            }
            if outS[addr] != registers {
                outS[addr] = registers
                for succ in block.successors
                where body.contains(succ) && succ != header && !queued.contains(succ) {
                    worklist.append(succ); queued.insert(succ)
                }
            }
        }
        return outS
    }

    /// Whether `value` is a linear recurrence `local(id) ± c` (c ≠ 0) — a genuine
    /// induction step. `+` is commutative; `-` only with the placeholder on the
    /// left (`i - c`).
    private static func isInductionRecurrence(_ value: AbstractValue, id: Int) -> Bool {
        guard case .binary(let op, let a, let b) = value else { return false }
        func isLocal(_ v: AbstractValue) -> Bool { if case .local(let x) = v { return x == id }; return false }
        func nonZeroConst(_ v: AbstractValue) -> Bool { if case .immediate(let c) = v { return c != 0 }; return false }
        switch op {
        case .add: return (isLocal(a) && nonZeroConst(b)) || (isLocal(b) && nonZeroConst(a))
        case .subtract: return isLocal(a) && nonZeroConst(b)
        default: return false
        }
    }

    /// The condition under which a conditional branch is TAKEN, as a comparison
    /// value — for a compare-and-branch (`cbz`/`cbnz`, `tbz`/`tbnz` on a sign
    /// bit) or a flag branch (`b.cond`). Nil when it isn't cleanly a comparison,
    /// so a diamond over it declines to become a select.
    private func branchTakenCondition(_ insn: Instruction, in registers: State) -> AbstractValue? {
        guard let detail = insn.detail else { return nil }
        func operandValue(_ index: Int) -> AbstractValue? {
            guard index < detail.operands.count,
                  let register = detail.operands[index].operand.register
            else { return nil }
            let value = registers[register.key] ?? .unknown
            return value == .unknown ? nil : value
        }
        switch detail.id {
        case AARCH64_INS_CBZ:
            return operandValue(0).map { .binary(.equal, $0, .immediate(0)) }
        case AARCH64_INS_CBNZ:
            return operandValue(0).map { .binary(.notEqual, $0, .immediate(0)) }
        case AARCH64_INS_TBZ, AARCH64_INS_TBNZ:
            guard let value = operandValue(0), detail.operands.count >= 2,
                  let bit = detail.operands[1].operand.immediateValue,
                  (0..<64).contains(bit)
            else { return nil }
            let width = detail.operands[0].operand.register.map({ $0.widthBits }) ?? 64
            if bit == width - 1 {
                // Sign bit: tbz taken = non-negative, tbnz taken = negative.
                return .binary(detail.id == AARCH64_INS_TBZ ? .greaterEqual : .less,
                               value, .immediate(0))
            }
            // Any other bit is an honest mask test — `(v & (1<<bit)) == 0` for
            // tbz (bit clear taken), `!= 0` for tbnz. This is how a `Bool` (bit 0)
            // condition arrives.
            let masked = AbstractValue.binary(.bitAnd, value, .immediate(1 << bit))
            return .binary(detail.id == AARCH64_INS_TBZ ? .equal : .notEqual, masked, .immediate(0))
        default:
            guard let op = Self.comparisonOperator(detail.conditionCode),
                  let flags = registers[Self.flagsKey]
            else { return nil }
            return comparisonValue(flags: flags, op)
        }
    }

    /// Decode a Swift `_SmallString` passed in two registers (x0 = low 8 bytes,
    /// x1 = high 8 bytes, with the count in the top byte's low nibble and the
    /// `0xE` small-string discriminator in its high nibble). Returns the text
    /// when it decodes to printable UTF-8, else nil.
    public static func decodeSmallString(lo: UInt64, hi: UInt64) -> String? {
        let discriminator = UInt8(truncatingIfNeeded: hi >> 56)
        guard (discriminator & 0xF0) == 0xE0 else { return nil }
        let count = Int(discriminator & 0x0F)
        guard (1...15).contains(count) else { return nil }

        var bytes: [UInt8] = []
        for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: lo >> shift)) }
        for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: hi >> shift)) }
        let content = Array(bytes.prefix(count))
        guard content.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return nil }
        return String(decoding: content, as: UTF8.self)
    }

    // MARK: - Transfer function

    /// One instruction's effect on the register/stack state, driven by Capstone's
    /// structured operands.
    ///
    /// Dispatch is on the instruction **id**, never on the mnemonic text and
    /// never on Capstone's per-operand `access` flags. Both of those lie:
    /// `cmp x1, #1` is an alias for `subs xzr, x1, #1`, and Capstone reports its
    /// x1 operand as WRITE (in `op.access` *and* in `cs_regs_access`) even though
    /// `cmp` writes no general register. Trusting either would clobber a tracked
    /// value on every compare. Reads are likewise unreliable (`ldaddal` reports
    /// no accesses at all). So: an explicit table for what we model, and a
    /// pessimistic clobber for everything else.
    private func apply(
        _ insn: Instruction,
        into registers: inout State,
        recordAccess: ((UInt64, SelfFieldAccess) -> Void)? = nil,
        recordArrayElement: ((UInt64, Int, AbstractValue) -> Void)? = nil,
        recordSlotStore: ((Int, AbstractValue) -> Void)? = nil
    ) {
        guard let detail = insn.detail else {
            // Capstone couldn't decode what objdump printed — data in __text, or
            // an unknown encoding. We cannot know what it writes, and keeping
            // stale values would be a lie, so drop everything nameable.
            registers.removeAll()
            return
        }

        // Branches and returns write no general register. (Calls never reach
        // here — `transfer` intercepts them.) This must precede the default,
        // which would otherwise clobber `x0` on `cbz x0, …`.
        if let flow = insn.controlFlow, flow != .sequential { return }

        // An instruction that writes NZCV but that we don't model into a
        // comparison (float/conditional compares, the S-variant arithmetic) must
        // invalidate the tracked flags, so a later `cset` never reads a stale
        // comparison and fabricates the wrong condition.
        if Self.unmodeledFlagWriters.contains(detail.id.rawValue) {
            registers[Self.flagsKey] = nil
        }

        // A result pointer flowing into anything but a modelled copy, offset,
        // access, or spill derives an alias whose stores would be invisible, so
        // the buffer is unprovable from here on (see `derivesUntrackedResultAlias`).
        if derivesUntrackedResultAlias(detail, in: registers) {
            Self.poisonResult(&registers)
        }

        switch detail.id {
        case AARCH64_INS_ADRP, AARCH64_INS_ADR:
            // Capstone resolves the page/PC-relative target into the immediate.
            guard let dest = destinationRegister(detail),
                  let target = detail.operands.count >= 2 ? detail.operands[1].operand.immediateValue : nil
            else { clobber(detail, into: &registers); return }
            write(dest, .address(UInt64(bitPattern: target)), into: &registers)

        case AARCH64_INS_ADD, AARCH64_INS_ADDS, AARCH64_INS_SUB, AARCH64_INS_SUBS:
            guard let dest = destinationRegister(detail), detail.operands.count >= 3 else {
                clobber(detail, into: &registers); return
            }
            let lhs = source(detail.operands[1], in: registers)
            let rhs = source(detail.operands[2], in: registers)
            let op: AbstractBinaryOperator = (detail.id == AARCH64_INS_ADD || detail.id == AARCH64_INS_ADDS)
                ? .add : .subtract
            // `shiftedImmediate` is the fix for `sub sp, sp, #0x2, lsl #12`:
            // reading the immediate alone yields 2 where the real value is 8192.
            if let delta = detail.operands[2].shiftedImmediate {
                let adding = op == .add
                let magnitude = UInt64(bitPattern: delta)
                switch lhs {
                case .address(let address):
                    write(dest, .address(adding ? address &+ magnitude : address &- magnitude), into: &registers)
                    return
                case .frame(let offset):
                    write(dest, .frame(adding ? offset &+ delta : offset &- delta), into: &registers)
                    return
                case .selfPointer where adding:
                    recordAccess?(insn.address, SelfFieldAccess(
                        offset: Int(delta), bytes: 0, isWrite: false, isAddressOf: true
                    ))
                    write(dest, .selfField(offset: Int(delta)), into: &registers)
                    return
                case .selfField(let base) where adding:
                    recordAccess?(insn.address, SelfFieldAccess(
                        offset: base + Int(delta), bytes: 0, isWrite: false, isAddressOf: true
                    ))
                    write(dest, .selfField(offset: base + Int(delta)), into: &registers)
                    return
                // `add x9, x8, #0x10` forms the address of result byte 0x10.
                case .indirectResultPointer where adding:
                    write(dest, .indirectResultField(offset: Int(delta)), into: &registers)
                    return
                case .indirectResultField(let base) where adding:
                    write(dest, .indirectResultField(offset: base + Int(delta)), into: &registers)
                    return
                default:
                    break
                }
            }
            let result = expression(op, lhs, rhs)
            write(dest, result, into: &registers)
            // The S-variants (`adds`/`subs`) also set NZCV — the compiler emits
            // `subs x8, x8, x0; cset …` for a comparison as readily as `cmp`.
            if detail.id == AARCH64_INS_ADDS || detail.id == AARCH64_INS_SUBS {
                registers[Self.flagsKey] = result
            }

        case AARCH64_INS_AND, AARCH64_INS_ANDS, AARCH64_INS_ORR, AARCH64_INS_EOR,
             AARCH64_INS_MUL, AARCH64_INS_SMULH, AARCH64_INS_UMULH,
             AARCH64_INS_LSL, AARCH64_INS_LSR, AARCH64_INS_ASR,
             AARCH64_INS_SDIV, AARCH64_INS_UDIV:
            guard let dest = destinationRegister(detail), detail.operands.count >= 3 else {
                clobber(detail, into: &registers); return
            }
            let op: AbstractBinaryOperator = switch detail.id {
            case AARCH64_INS_AND, AARCH64_INS_ANDS: .bitAnd
            case AARCH64_INS_ORR: .bitOr
            case AARCH64_INS_EOR: .bitXor
            case AARCH64_INS_MUL: .multiply
            case AARCH64_INS_SMULH: .multiplyHigh
            case AARCH64_INS_UMULH: .unsignedMultiplyHigh
            case AARCH64_INS_SDIV: .divide
            case AARCH64_INS_UDIV: .unsignedDivide
            case AARCH64_INS_LSL: .shiftLeft
            case AARCH64_INS_LSR: .shiftRight
            case AARCH64_INS_ASR: .arithmeticShiftRight
            default: .add // unreachable: the outer case is exhaustive
            }
            let result = expression(
                op, source(detail.operands[1], in: registers),
                source(detail.operands[2], in: registers)
            )
            write(dest, result, into: &registers)
            if detail.id == AARCH64_INS_ANDS { registers[Self.flagsKey] = result }

        case AARCH64_INS_MADD, AARCH64_INS_MSUB:
            // Fused multiply-add/subtract: `madd d, n, m, a` = a + n*m,
            // `msub d, n, m, a` = a - n*m — the common shape of `a + b*c` and of
            // the `sdiv`/`msub` pair the compiler emits for `a % b`.
            guard let dest = destinationRegister(detail), detail.operands.count >= 4 else {
                clobber(detail, into: &registers); return
            }
            let product = expression(
                .multiply, source(detail.operands[1], in: registers),
                source(detail.operands[2], in: registers)
            )
            let addend = source(detail.operands[3], in: registers)
            write(dest, expression(detail.id == AARCH64_INS_MADD ? .add : .subtract, addend, product),
                  into: &registers)

        case AARCH64_INS_FADD, AARCH64_INS_FSUB, AARCH64_INS_FMUL, AARCH64_INS_FDIV, AARCH64_INS_FNMUL:
            guard let dest = destinationRegister(detail), detail.operands.count >= 3 else {
                clobber(detail, into: &registers); return
            }
            let op: AbstractBinaryOperator = switch detail.id {
            case AARCH64_INS_FADD: .add
            case AARCH64_INS_FSUB: .subtract
            case AARCH64_INS_FDIV: .divide
            default: .multiply // FMUL, FNMUL
            }
            let product = floatBinary(op, source(detail.operands[1], in: registers),
                                      source(detail.operands[2], in: registers))
            // FNMUL negates the product: `-(a * b)`.
            write(dest, detail.id == AARCH64_INS_FNMUL ? floatUnary(.negate, product) : product,
                  into: &registers)

        case AARCH64_INS_FNEG, AARCH64_INS_FSQRT, AARCH64_INS_FABS:
            guard let dest = destinationRegister(detail), detail.operands.count >= 2 else {
                clobber(detail, into: &registers); return
            }
            let op: AbstractUnaryOperator = switch detail.id {
            case AARCH64_INS_FSQRT: .squareRoot
            case AARCH64_INS_FABS: .absoluteValue
            default: .negate // FNEG
            }
            write(dest, floatUnary(op, source(detail.operands[1], in: registers)), into: &registers)

        case AARCH64_INS_FCVT, AARCH64_INS_SCVTF, AARCH64_INS_UCVTF,
             AARCH64_INS_FCVTZS, AARCH64_INS_FCVTZU:
            // A numeric conversion is part of the value: carried through bare,
            // `Double(n) * 1.5` rendered `(arg0 * 0x3ff8000000000000)`, an Int
            // times a 4.6e18 integer. Scalar forms only; a vector form is not
            // modelled.
            guard let dest = destinationRegister(detail),
                  detail.operands.count == 2 || detail.operands.count == 3,
                  detail.operands[1].operand.register != nil,
                  [16, 32, 64].contains(dest.widthBits)
            else { clobber(detail, into: &registers); return }
            let op: AbstractUnaryOperator = switch detail.id {
            case AARCH64_INS_FCVTZS: .toInteger(signed: true, bits: dest.widthBits)
            case AARCH64_INS_FCVTZU: .toInteger(signed: false, bits: dest.widthBits)
            default: .toFloat(bits: dest.widthBits)
            }
            let converted = floatUnary(op, source(detail.operands[1], in: registers))
            guard detail.operands.count == 3 else { write(dest, converted, into: &registers); return }
            // Fixed point: `ucvtf d0, x0, #2` is `Double(x0) / 4`, the compiler's
            // folding of `* 0.25`. Only the int-to-float direction is modelled.
            guard case .toFloat = op, dest.widthBits == 64 || dest.widthBits == 32,
                  let fractionBits = detail.operands[2].operand.immediateValue,
                  (1...64).contains(fractionBits)
            else { clobber(detail, into: &registers); return }
            let scale = Double(sign: .plus, exponent: Int(fractionBits), significand: 1)
            let scaleBits = dest.widthBits == 64 ? scale.bitPattern : UInt64(Float(scale).bitPattern)
            write(dest, floatBinary(.divide, converted, .immediate(scaleBits)), into: &registers)

        case AARCH64_INS_FMOV:
            // A register-to-register FP move carries the bits through unchanged
            // (`fmov x8, d0` reinterprets them; the bit-level rendering relies on that).
            guard let dest = destinationRegister(detail), detail.operands.count >= 2 else {
                clobber(detail, into: &registers); return
            }
            // `fmov d0, #<imm>` — decode the encoded float and carry its bit
            // pattern (single- or double-precision per the destination width), so
            // a float context renders it as `0.5`/`2.5` rather than dropping it.
            if let fp = detail.operands[1].operand.floatingPointValue {
                let bits = dest.widthBits == 32 ? UInt64(Float(fp).bitPattern) : fp.bitPattern
                write(dest, .immediate(bits), into: &registers)
                return
            }
            guard detail.operands[1].operand.register != nil else {
                clobber(detail, into: &registers); return
            }
            write(dest, source(detail.operands[1], in: registers), into: &registers)

        case AARCH64_INS_MOV, AARCH64_INS_MOVZ:
            // Capstone pre-folds MOVZ's shift into the immediate.
            guard let dest = destinationRegister(detail), detail.operands.count >= 2 else {
                clobber(detail, into: &registers); return
            }
            write(dest, source(detail.operands[1], in: registers), into: &registers)

        case AARCH64_INS_DUP:
            // `dup v0.2d, x9` replicates a general register into both vector
            // lanes: the two words the compiler then stores as a pair to fill a
            // buffer with one repeated value.
            guard let dest = destinationRegister(detail), detail.operands.count >= 2,
                  let lane = detail.operands[1].operand.register, lane.kind == .gpr,
                  dest.widthBits == 128
            else { clobber(detail, into: &registers); return }
            let value = source(detail.operands[1], in: registers)
            write(dest, value == .unknown ? .unknown : .aggregate([value, value]), into: &registers)

        case AARCH64_INS_MOVI:
            // `movi v0.2d, #0` zeroes a vector register: the two words the
            // compiler then stores as a pair (`stp q0, q0, [x8]`) to zero-fill a
            // buffer. Only the all-zero form is modelled; any other replicated
            // byte pattern is left unknown.
            guard let dest = destinationRegister(detail), detail.operands.count >= 2,
                  detail.operands[1].operand.immediateValue == 0
            else { clobber(detail, into: &registers); return }
            write(dest, dest.widthBits > 64
                  ? .aggregate([.immediate(0), .immediate(0)]) : .immediate(0), into: &registers)

        case AARCH64_INS_MOVK:
            // MOVK's shift is NOT pre-folded, and it merges into the existing value.
            guard let dest = destinationRegister(detail), detail.operands.count >= 2,
                  let imm = detail.operands[1].operand.immediateValue
            else { clobber(detail, into: &registers); return }
            let shift = detail.operands[1].shift.type == AARCH64_SFT_LSL ? UInt64(detail.operands[1].shift.amount) : 0
            let base: UInt64 = { if case .immediate(let v) = registers[dest.key] { return v } else { return 0 } }()
            let mask = ~(UInt64(0xffff) << shift)
            write(dest, .immediate((base & mask) | (UInt64(bitPattern: imm) << shift)), into: &registers)

        case AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDRB, AARCH64_INS_LDURB,
             AARCH64_INS_LDRH, AARCH64_INS_LDURH, AARCH64_INS_LDRSB, AARCH64_INS_LDURSB,
             AARCH64_INS_LDRSH, AARCH64_INS_LDURSH, AARCH64_INS_LDRSW, AARCH64_INS_LDURSW:
            guard let dest = destinationRegister(detail) else { clobber(detail, into: &registers); return }
            noteFieldAccess(insn, detail, in: registers, recordAccess)
            let target = memoryTarget(detail, in: registers)
            applyWriteback(detail, into: &registers)
            switch target {
            case .stackSlot(let key):
                let offset = Self.stackOffset(from: key)
                let bytes = Self.accessBytes(detail) ?? max(dest.widthBits / 8, 1)
                write(dest, offset.map { Self.stackValue(at: $0, bytes: bytes, in: registers) } ?? .unknown,
                      into: &registers)
            case .absolute(let address):
                // Only pointer-width loads can safely denote a selref/GOT slot.
                // A 16-byte vector load from a fixed address is two such words
                // (a literal-pool constant the enrichment pass may read).
                let isPointerLoad = detail.id == AARCH64_INS_LDR || detail.id == AARCH64_INS_LDUR
                if isPointerLoad, dest.kind == .vector, dest.widthBits == 128 {
                    write(dest, .aggregate([.loaded(address), .loaded(address &+ 8)]), into: &registers)
                } else {
                    write(dest, isPointerLoad ? .loaded(address) : .unknown, into: &registers)
                }
            case .selfField(let offset): write(dest, .selfFieldValue(offset: offset), into: &registers)
            case .vtableMethod(let offset):
                // The dispatch loads the vtable slot only through a pointer-width
                // read; a narrower load isn't a method pointer.
                let isPointerLoad = detail.id == AARCH64_INS_LDR || detail.id == AARCH64_INS_LDUR
                write(dest, isPointerLoad ? .selfVTableMethod(offset: offset) : .unknown, into: &registers)
            case .resultSlot(let offset):
                // Reading the buffer back: only an exact-width match of a tracked
                // store is known.
                let bytes = Self.accessBytes(detail) ?? max(dest.widthBits / 8, 1)
                write(dest, registers[Self.resultKey(offset, bytes: bytes)] ?? .unknown, into: &registers)
            case .asyncSlot(let offset):
                // Only a full-width integer load carries a pointer: `ldr w9`
                // drops its upper bits and `ldr d0` is a floating value. A value
                // this funclet itself stored there earlier comes back first.
                let isPointerLoad = dest.kind == .gpr && dest.widthBits == 64
                let stored = registers[Self.contextSlotKey(offset)]
                write(dest, isPointerLoad ? (stored ?? asyncSlotValue(at: offset)) : .unknown, into: &registers)
            case .asyncCalleeSlot(let offset):
                // The callee context's first word is the caller's own context;
                // nothing else in it is known here.
                let isPointerLoad = dest.kind == .gpr && dest.widthBits == 64
                write(dest, isPointerLoad && offset == 0 ? .asyncContext : .unknown, into: &registers)
            case .arrayElement, .none: write(dest, .unknown, into: &registers)
            }

        // A store writes memory, not a register — but it populates a stack slot,
        // which is how a value materialised before a branch reaches a call after it.
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STRB, AARCH64_INS_STURB,
             AARCH64_INS_STRH, AARCH64_INS_STURH:
            noteFieldAccess(insn, detail, in: registers, recordAccess)
            let target = memoryTarget(detail, in: registers)
            if let first = detail.operands.first {
                let value = source(first, in: registers)
                if case .stackSlot(let key)? = target {
                    if let offset = Self.stackOffset(from: key) {
                        let bytes = Self.accessBytes(detail) ?? 8
                        Self.storeStack(value, at: offset, bytes: bytes, outgoing: true, into: &registers)
                    }
                }
                if case .arrayElement(let site, let offset)? = target {
                    recordArrayElement?(site, offset, value)
                }
                if case .selfField = target {
                    // A register holding a prior field load is a snapshot.
                    // Keeping `.selfFieldValue` through the write would render
                    // that old register as the field's new value.
                    Self.invalidateSelfFieldAliases(in: &registers)
                }
                if case .resultSlot(let offset)? = target {
                    let bytes = Self.accessBytes(detail) ?? 8
                    Self.storeResult(value, at: offset, bytes: bytes, into: &registers)
                }
                if case .asyncSlot(let offset)? = target {
                    // -Onone stores x22 into its own context (`str x9, [x22,
                    // #0x10]`) and reaches ResumeParent through it at each exit;
                    // forwarding the store is what proves those exits returns.
                    for key in Self.contextSlotKeys(overlapping: offset, bytes: Self.accessBytes(detail) ?? 8) {
                        registers[key] = nil
                    }
                    if detail.id == AARCH64_INS_STR || detail.id == AARCH64_INS_STUR,
                       first.operand.register?.widthBits == 64 {
                        recordSlotStore?(offset, value)
                        if value != .unknown { registers[Self.contextSlotKey(offset)] = value }
                    }
                }
                // A full-width store establishes a useful equality: its source
                // register now also holds the current ivar value. Canonicalizing
                // that one register (without rewriting unrelated pointer aliases)
                // lets paths such as
                // `if (enabled) _count += delta; return _count` meet back at the
                // return even though one path performed arithmetic.
                if (detail.id == AARCH64_INS_STR || detail.id == AARCH64_INS_STUR),
                   value != .unknown, case .selfField(let offset)? = target,
                   let sourceRegister = first.operand.register {
                    write(sourceRegister, .selfFieldValue(offset: offset), into: &registers)
                }
            }
            applyWriteback(detail, into: &registers)

        case AARCH64_INS_STP, AARCH64_INS_STNP:
            noteFieldAccess(insn, detail, in: registers, recordAccess)
            let target = memoryTarget(detail, in: registers)
            if case .stackSlot(let key)? = target,
               let offset = Self.stackOffset(from: key),
               let bytes = detail.operands.first?.operand.register.map({ $0.widthBits / 8 }) {
                for (index, operand) in detail.operands.prefix(2).enumerated() {
                    Self.storeStack(
                        source(operand, in: registers),
                        at: offset + Int64(index * bytes), bytes: bytes,
                        outgoing: true, into: &registers
                    )
                }
            } else if case .selfField(let offset)? = target,
                      let bytes = detail.operands.first?.operand.register.map({ $0.widthBits / 8 }) {
                Self.invalidateSelfFieldAliases(in: &registers)
                for (index, operand) in detail.operands.prefix(2).enumerated() {
                    if let register = operand.operand.register {
                        write(register, .selfFieldValue(offset: offset + index * bytes), into: &registers)
                    }
                }
            } else if case .arrayElement(let site, let offset)? = target,
                      let bytes = detail.operands.first?.operand.register.map({ $0.widthBits / 8 }) {
                // A wide element (e.g. a 16-byte String) stored as a register pair.
                for (index, operand) in detail.operands.prefix(2).enumerated() {
                    recordArrayElement?(site, offset + index * bytes, source(operand, in: registers))
                }
            } else if case .resultSlot(let offset)? = target,
                      let bytes = detail.operands.first?.operand.register.map({ $0.widthBits / 8 }) {
                for (index, operand) in detail.operands.prefix(2).enumerated() {
                    Self.storeResult(source(operand, in: registers), at: offset + index * bytes,
                                     bytes: bytes, into: &registers)
                }
            } else if case .asyncSlot(let offset)? = target,
                      detail.operands.first?.operand.register?.widthBits == 64 {
                // `stp x22, x8, [x0]` is how the caller's context and the resume
                // pointer are written into a fresh callee context; the same shape
                // spills two locals into the function's own context.
                for (index, operand) in detail.operands.prefix(2).enumerated() {
                    let value = source(operand, in: registers)
                    registers[Self.contextSlotKey(offset + index * 8)] = value == .unknown ? nil : value
                    recordSlotStore?(offset + index * 8, source(operand, in: registers))
                }
            }
            // Stores two registers; writes none. Writeback still applies —
            // `stp x29, x30, [sp, #-0x70]!` is the standard prologue, and missing
            // it desynchronises the frame for every stack slot that follows.
            applyWriteback(detail, into: &registers)

        case AARCH64_INS_LDP, AARCH64_INS_LDNP:
            // A 16-byte Swift.String field arrives exactly here. Pair loads are
            // also how optimized Objective-C methods pull arguments 6+ back out
            // of their entry stack area.
            noteFieldAccess(insn, detail, in: registers, recordAccess)
            let target = memoryTarget(detail, in: registers)
            let registerBytes = detail.operands.first?.operand.register.map { $0.widthBits / 8 } ?? 8
            for (index, operand) in detail.operands.prefix(2).enumerated() {
                guard let register = operand.operand.register else { continue }
                let value: AbstractValue = switch target {
                case .stackSlot(let key):
                    Self.stackOffset(from: key).flatMap {
                        Self.stackValue(
                            at: $0 + Int64(index * registerBytes),
                            bytes: registerBytes, in: registers
                        )
                    } ?? .unknown
                case .selfField(let offset):
                    .selfFieldValue(offset: offset + index * registerBytes)
                case .resultSlot(let offset):
                    registers[Self.resultKey(offset + index * registerBytes, bytes: registerBytes)] ?? .unknown
                case .asyncSlot(let offset) where register.kind == .gpr && registerBytes == 8:
                    asyncSlotValue(at: offset + index * 8)
                case .asyncCalleeSlot(let offset) where register.kind == .gpr && registerBytes == 8
                    && offset + index * 8 == 0:
                    .asyncContext
                case .absolute, .vtableMethod, .arrayElement, .asyncSlot, .asyncCalleeSlot, .none:
                    .unknown
                }
                write(register, value, into: &registers)
            }
            applyWriteback(detail, into: &registers)

        case AARCH64_INS_ALIAS_CMP, AARCH64_INS_ALIAS_CMN, AARCH64_INS_ALIAS_TST, AARCH64_INS_CCMP, AARCH64_INS_CCMN:
            // These write only NZCV, never a general register — critically they
            // must NOT reach the default, since Capstone renders `cmp x1, #1` with
            // x1 as its first operand (it aliases `subs xzr, x1, #1`) and a
            // destination-clobbering default would destroy x1. Record the flags
            // value so a following `cset`/`csel` can reconstruct the comparison.
            // `cmp` compares `a - b`, `cmn` compares `a + b`, `tst` is `a & b`.
            if detail.operands.count >= 2 {
                let lhs = source(detail.operands[0], in: registers)
                let rhs = source(detail.operands[1], in: registers)
                switch detail.id {
                case AARCH64_INS_ALIAS_CMP: registers[Self.flagsKey] = expression(.subtract, lhs, rhs)
                case AARCH64_INS_ALIAS_CMN: registers[Self.flagsKey] = expression(.add, lhs, rhs)
                case AARCH64_INS_ALIAS_TST: registers[Self.flagsKey] = expression(.bitAnd, lhs, rhs)
                default: registers[Self.flagsKey] = nil // CCMP/CCMN: conditional
                }
            } else {
                registers[Self.flagsKey] = nil
            }

        case AARCH64_INS_ALIAS_CSET, AARCH64_INS_ALIAS_CSETM:
            // `cset wd, <cc>` materialises the flags as a boolean. Reconstruct the
            // comparison from the recorded flags value and the condition code.
            guard let dest = destinationRegister(detail),
                  let op = Self.comparisonOperator(detail.conditionCode),
                  let flags = registers[Self.flagsKey]
            else { clobber(detail, into: &registers); return }
            write(dest, comparisonValue(flags: flags, op), into: &registers)

        case AARCH64_INS_CSEL, AARCH64_INS_CSINC, AARCH64_INS_CSINV, AARCH64_INS_CSNEG:
            // The branchless ternary: `csel d, n, m, cc` = cc ? n : m. The
            // `inc`/`inv`/`neg` variants apply +1 / bitwise-not / negate to the
            // false operand. This is how `-O` lowers a ternary, so it produces the
            // same `.select` a `-Onone` diamond does.
            guard let dest = destinationRegister(detail), detail.operands.count >= 3,
                  let op = Self.comparisonOperator(detail.conditionCode),
                  let flags = registers[Self.flagsKey]
            else { clobber(detail, into: &registers); return }
            let condition = comparisonValue(flags: flags, op)
            let whenTrue = source(detail.operands[1], in: registers)
            let falseOperand = source(detail.operands[2], in: registers)
            let whenFalse: AbstractValue = switch detail.id {
            case AARCH64_INS_CSINC: expression(.add, falseOperand, .immediate(1))
            case AARCH64_INS_CSINV: falseOperand == .unknown ? .unknown : .unary(.bitwiseNot, falseOperand)
            case AARCH64_INS_CSNEG: falseOperand == .unknown ? .unknown : .unary(.negate, falseOperand)
            default: falseOperand
            }
            let result: AbstractValue = (condition == .unknown || whenTrue == .unknown || whenFalse == .unknown)
                ? .unknown
                : .select(condition: condition, whenTrue: whenTrue, whenFalse: whenFalse)
            write(dest, result, into: &registers)

        default:
            clobber(detail, into: &registers)
        }
    }

    /// What an unmodelled instruction writes.
    ///
    /// The default is **operand 0**, because that is what almost every ARM64
    /// instruction writes, and the exceptions are enumerable. Clobbering every
    /// register an instruction merely *names* would be sound but destroys real
    /// information: `csel x0, x1, x19, eq` only writes x0, and killing x19 —
    /// which is callee-saved and routinely holds a receiver across a call —
    /// silently drops arguments that were previously recovered.
    ///
    /// Validation: a register the instruction writes (by Capstone's access
    /// flags) that held a proven value and that the transfer never wrote was
    /// not modelled, and its stale value can render as a confident argument.
    /// Calls are exempt (the ABI, not the instruction, says what survives).
    private static func checkWritesModelled(_ insn: Instruction, before: State, written modelled: Set<String>) {
        guard insn.controlFlow != .call, let detail = insn.detail else { return }
        var written = Set<String>()
        for info in detail.operands {
            if case .register(let register) = info.operand, info.isWritten, register.kind == .gpr {
                written.insert(register.key)
            }
        }
        for key in written.subtracting(modelled).sorted() {
            guard let old = before[key], old != .unknown else { continue }
            Probe.record(.tracerUnmodelledWrite, at: insn.address,
                         ["register": .label(key), "instruction": .label(insn.text), "kept": .label("\(old)")])
        }
    }

    /// Being wrong here is asymmetric, and the tables reflect that. Over-
    /// clobbering costs precision (a `?` where a value was known). Under-
    /// clobbering leaves a stale value that renders as a confident, fabricated
    /// argument — which the "never invent" rule forbids. So a family is listed
    /// only when its members provably write nothing (plain stores), and
    /// anything whose destination is not operand 0 (the atomics) clobbers wide.
    private func clobber(_ detail: StructuredInsn, into registers: inout State) {
        let id = detail.id.rawValue
        if Self.storesWithoutRegisterWrite.contains(id) {
            applyWriteback(detail, into: &registers)
            return
        }
        if Self.atomicReadModifyWrite.contains(id) || Self.pairLoads.contains(id) {
            for operand in detail.operands {
                if let reg = operand.operand.register { write(reg, .unknown, into: &registers) }
            }
            applyWriteback(detail, into: &registers)
            return
        }
        if let dest = destinationRegister(detail) { write(dest, .unknown, into: &registers) }
        applyWriteback(detail, into: &registers)
    }

    /// Stores write memory, not registers.
    ///
    /// The exclusive stores (STXR/STLXR/STXP/STLXP) are deliberately ABSENT:
    /// they write a status register in operand 0, so the default handles them.
    /// The old text path matched `hasPrefix("st")` and clobbered nothing for
    /// them, leaving a stale value to render as a later call argument.
    private static let storesWithoutRegisterWrite: Set<UInt32> = Set([
        AARCH64_INS_ST1, AARCH64_INS_ST1B, AARCH64_INS_ST1D, AARCH64_INS_ST1H, AARCH64_INS_ST1Q,
        AARCH64_INS_ST1W, AARCH64_INS_ST2, AARCH64_INS_ST2B, AARCH64_INS_ST2D, AARCH64_INS_ST2G,
        AARCH64_INS_ST2H, AARCH64_INS_ST2W, AARCH64_INS_ST3, AARCH64_INS_ST3B, AARCH64_INS_ST3D,
        AARCH64_INS_ST3H, AARCH64_INS_ST3W, AARCH64_INS_ST4, AARCH64_INS_ST4B, AARCH64_INS_ST4D,
        AARCH64_INS_ST4H, AARCH64_INS_ST4W, AARCH64_INS_ST64B, AARCH64_INS_ST64BV, AARCH64_INS_ST64BV0,
        AARCH64_INS_ALIAS_STADD, AARCH64_INS_ALIAS_STADDB, AARCH64_INS_ALIAS_STADDH, AARCH64_INS_ALIAS_STADDL,
        AARCH64_INS_ALIAS_STADDLB, AARCH64_INS_ALIAS_STADDLH, AARCH64_INS_ALIAS_STCLR, AARCH64_INS_ALIAS_STCLRB,
        AARCH64_INS_ALIAS_STCLRH, AARCH64_INS_ALIAS_STCLRL, AARCH64_INS_ALIAS_STCLRLB, AARCH64_INS_ALIAS_STCLRLH,
        AARCH64_INS_ALIAS_STEOR, AARCH64_INS_ALIAS_STEORB, AARCH64_INS_ALIAS_STEORH, AARCH64_INS_ALIAS_STEORL,
        AARCH64_INS_ALIAS_STEORLB, AARCH64_INS_ALIAS_STEORLH, AARCH64_INS_STG, AARCH64_INS_STGM, AARCH64_INS_STGP,
        AARCH64_INS_STLLR, AARCH64_INS_STLLRB, AARCH64_INS_STLLRH, AARCH64_INS_STLR, AARCH64_INS_STLRB,
        AARCH64_INS_STLRH, AARCH64_INS_STLUR, AARCH64_INS_STLURB, AARCH64_INS_STLURH, AARCH64_INS_STNP,
        AARCH64_INS_STNT1B, AARCH64_INS_STNT1D, AARCH64_INS_STNT1H, AARCH64_INS_STNT1W, AARCH64_INS_STP,
        AARCH64_INS_STR, AARCH64_INS_STRB, AARCH64_INS_STRH, AARCH64_INS_ALIAS_STSET, AARCH64_INS_ALIAS_STSETB,
        AARCH64_INS_ALIAS_STSETH, AARCH64_INS_ALIAS_STSETL, AARCH64_INS_ALIAS_STSETLB, AARCH64_INS_ALIAS_STSETLH,
        AARCH64_INS_ALIAS_STSMAX, AARCH64_INS_ALIAS_STSMAXB, AARCH64_INS_ALIAS_STSMAXH, AARCH64_INS_ALIAS_STSMAXL,
        AARCH64_INS_ALIAS_STSMAXLB, AARCH64_INS_ALIAS_STSMAXLH, AARCH64_INS_ALIAS_STSMIN, AARCH64_INS_ALIAS_STSMINB,
        AARCH64_INS_ALIAS_STSMINH, AARCH64_INS_ALIAS_STSMINL, AARCH64_INS_ALIAS_STSMINLB, AARCH64_INS_ALIAS_STSMINLH,
        AARCH64_INS_STTR, AARCH64_INS_STTRB, AARCH64_INS_STTRH, AARCH64_INS_ALIAS_STUMAX, AARCH64_INS_ALIAS_STUMAXB,
        AARCH64_INS_ALIAS_STUMAXH, AARCH64_INS_ALIAS_STUMAXL, AARCH64_INS_ALIAS_STUMAXLB, AARCH64_INS_ALIAS_STUMAXLH,
        AARCH64_INS_ALIAS_STUMIN, AARCH64_INS_ALIAS_STUMINB, AARCH64_INS_ALIAS_STUMINH, AARCH64_INS_ALIAS_STUMINL,
        AARCH64_INS_ALIAS_STUMINLB, AARCH64_INS_ALIAS_STUMINLH, AARCH64_INS_STUR, AARCH64_INS_STURB,
        AARCH64_INS_STURH, AARCH64_INS_STZ2G, AARCH64_INS_STZG, AARCH64_INS_STZGM
    ].map(\.rawValue))

    /// Atomic read-modify-write. The destination is operand **1**, not 0, and
    /// Capstone reports no operand accesses at all for these (`op.access` is 0
    /// on every operand; `cs_regs_access` claims they write nothing). Clobber
    /// every register operand: imprecise, since operand 0 is only read, but
    /// never a lie. 583 sites in CoreLocation's __text.
    private static let atomicReadModifyWrite: Set<UInt32> = Set([
        AARCH64_INS_CAS, AARCH64_INS_CASA, AARCH64_INS_CASAB, AARCH64_INS_CASAH, AARCH64_INS_CASAL,
        AARCH64_INS_CASALB, AARCH64_INS_CASALH, AARCH64_INS_CASB, AARCH64_INS_CASH, AARCH64_INS_CASL,
        AARCH64_INS_CASLB, AARCH64_INS_CASLH, AARCH64_INS_CASP, AARCH64_INS_CASPA, AARCH64_INS_CASPAL,
        AARCH64_INS_CASPL, AARCH64_INS_LDADD, AARCH64_INS_LDADDA, AARCH64_INS_LDADDAB,
        AARCH64_INS_LDADDAH, AARCH64_INS_LDADDAL, AARCH64_INS_LDADDALB, AARCH64_INS_LDADDALH,
        AARCH64_INS_LDADDB, AARCH64_INS_LDADDH, AARCH64_INS_LDADDL, AARCH64_INS_LDADDLB,
        AARCH64_INS_LDADDLH, AARCH64_INS_LDCLR, AARCH64_INS_LDCLRA, AARCH64_INS_LDCLRAB,
        AARCH64_INS_LDCLRAH, AARCH64_INS_LDCLRAL, AARCH64_INS_LDCLRALB, AARCH64_INS_LDCLRALH,
        AARCH64_INS_LDCLRB, AARCH64_INS_LDCLRH, AARCH64_INS_LDCLRL, AARCH64_INS_LDCLRLB,
        AARCH64_INS_LDCLRLH, AARCH64_INS_LDEOR, AARCH64_INS_LDEORA, AARCH64_INS_LDEORAB,
        AARCH64_INS_LDEORAH, AARCH64_INS_LDEORAL, AARCH64_INS_LDEORALB, AARCH64_INS_LDEORALH,
        AARCH64_INS_LDEORB, AARCH64_INS_LDEORH, AARCH64_INS_LDEORL, AARCH64_INS_LDEORLB,
        AARCH64_INS_LDEORLH, AARCH64_INS_LDSET, AARCH64_INS_LDSETA, AARCH64_INS_LDSETAB,
        AARCH64_INS_LDSETAH, AARCH64_INS_LDSETAL, AARCH64_INS_LDSETALB, AARCH64_INS_LDSETALH,
        AARCH64_INS_LDSETB, AARCH64_INS_LDSETH, AARCH64_INS_LDSETL, AARCH64_INS_LDSETLB,
        AARCH64_INS_LDSETLH, AARCH64_INS_LDSMAX, AARCH64_INS_LDSMAXA, AARCH64_INS_LDSMAXAB,
        AARCH64_INS_LDSMAXAH, AARCH64_INS_LDSMAXAL, AARCH64_INS_LDSMAXALB, AARCH64_INS_LDSMAXALH,
        AARCH64_INS_LDSMAXB, AARCH64_INS_LDSMAXH, AARCH64_INS_LDSMAXL, AARCH64_INS_LDSMAXLB,
        AARCH64_INS_LDSMAXLH, AARCH64_INS_LDSMIN, AARCH64_INS_LDSMINA, AARCH64_INS_LDSMINAB,
        AARCH64_INS_LDSMINAH, AARCH64_INS_LDSMINAL, AARCH64_INS_LDSMINALB, AARCH64_INS_LDSMINALH,
        AARCH64_INS_LDSMINB, AARCH64_INS_LDSMINH, AARCH64_INS_LDSMINL, AARCH64_INS_LDSMINLB,
        AARCH64_INS_LDSMINLH, AARCH64_INS_LDUMAX, AARCH64_INS_LDUMAXA, AARCH64_INS_LDUMAXAB,
        AARCH64_INS_LDUMAXAH, AARCH64_INS_LDUMAXAL, AARCH64_INS_LDUMAXALB, AARCH64_INS_LDUMAXALH,
        AARCH64_INS_LDUMAXB, AARCH64_INS_LDUMAXH, AARCH64_INS_LDUMAXL, AARCH64_INS_LDUMAXLB,
        AARCH64_INS_LDUMAXLH, AARCH64_INS_LDUMIN, AARCH64_INS_LDUMINA, AARCH64_INS_LDUMINAB,
        AARCH64_INS_LDUMINAH, AARCH64_INS_LDUMINAL, AARCH64_INS_LDUMINALB, AARCH64_INS_LDUMINALH,
        AARCH64_INS_LDUMINB, AARCH64_INS_LDUMINH, AARCH64_INS_LDUMINL, AARCH64_INS_LDUMINLB,
        AARCH64_INS_LDUMINLH, AARCH64_INS_SWP, AARCH64_INS_SWPA, AARCH64_INS_SWPAB, AARCH64_INS_SWPAH,
        AARCH64_INS_SWPAL, AARCH64_INS_SWPALB, AARCH64_INS_SWPALH, AARCH64_INS_SWPB, AARCH64_INS_SWPH,
        AARCH64_INS_SWPL, AARCH64_INS_SWPLB, AARCH64_INS_SWPLH
    ].map(\.rawValue))

    /// Two destinations: operands 0 and 1.
    private static let pairLoads: Set<UInt32> = Set([
        AARCH64_INS_LDAXP, AARCH64_INS_LDNP, AARCH64_INS_LDP, AARCH64_INS_LDPSW, AARCH64_INS_LDXP
    ].map(\.rawValue))



    private func write(_ reg: PhysReg, _ value: AbstractValue, into registers: inout State) {
        guard reg.kind != .zero else { return }   // writes to xzr are discarded
        if Probe.isActive, let log = TracerWriteLog.current { log.keys.insert(reg.key) }
        // A truncated copy (`mov w9, w22`) or a floating register cannot hold
        // an async context or continuation pointer, though its key aliases xN.
        switch value {
        case .asyncContext, .asyncCalleeContext, .asyncResumeParent:
            guard reg.kind == .gpr, reg.widthBits == 64 else {
                registers[reg.key] = .unknown
                return
            }
        default:
            break
        }
        registers[reg.key] = value
    }

    /// Build or fold a symbolic expression. A small depth cap prevents long
    /// compiler-generated chains (and especially loop-carried values) from
    /// ballooning while retaining the short expressions source code uses for
    /// ivar arithmetic and return values.
    private func expression(
        _ op: AbstractBinaryOperator,
        _ lhs: AbstractValue,
        _ rhs: AbstractValue
    ) -> AbstractValue {
        guard lhs != .unknown, rhs != .unknown else { return .unknown }
        if case .immediate(let left) = lhs, case .immediate(let right) = rhs {
            let folded: UInt64? = switch op {
            case .add: left &+ right
            case .subtract: left &- right
            case .multiply: left &* right
            // sdiv semantics on the bit patterns: Int.min / -1 wraps to Int.min
            // (and its remainder is 0), as the instruction does.
            case .divide:
                right != 0
                    ? UInt64(bitPattern: Int64(bitPattern: left).dividedReportingOverflow(by: Int64(bitPattern: right)).partialValue)
                    : nil
            case .remainder:
                right != 0
                    ? UInt64(bitPattern: Int64(bitPattern: left).remainderReportingOverflow(dividingBy: Int64(bitPattern: right)).partialValue)
                    : nil
            case .unsignedDivide: right != 0 ? left / right : nil
            case .unsignedRemainder: right != 0 ? left % right : nil
            case .bitAnd: left & right
            case .bitOr: left | right
            case .bitXor: left ^ right
            case .shiftLeft: right < 64 ? left &<< right : nil
            case .shiftRight: right < 64 ? left &>> right : nil
            case .arithmeticShiftRight:
                right < 64
                    ? UInt64(bitPattern: Int64(bitPattern: left) >> Int64(right))
                    : nil
            case .multiplyHigh:
                UInt64(bitPattern: Int64(bitPattern: left).multipliedFullWidth(by: Int64(bitPattern: right)).high)
            case .unsignedMultiplyHigh:
                left.multipliedFullWidth(by: right).high
            case .equal: left == right ? 1 : 0
            case .notEqual: left != right ? 1 : 0
            case .less: Int64(bitPattern: left) < Int64(bitPattern: right) ? 1 : 0
            case .lessEqual: Int64(bitPattern: left) <= Int64(bitPattern: right) ? 1 : 0
            case .greater: Int64(bitPattern: left) > Int64(bitPattern: right) ? 1 : 0
            case .greaterEqual: Int64(bitPattern: left) >= Int64(bitPattern: right) ? 1 : 0
            // Unsigned comparisons fold over the raw bit patterns (which are
            // already UInt64), so two constants collapse with the machine's own
            // unsigned semantics.
            case .unsignedLess: left < right ? 1 : 0
            case .unsignedLessEqual: left <= right ? 1 : 0
            case .unsignedGreater: left > right ? 1 : 0
            case .unsignedGreaterEqual: left >= right ? 1 : 0
            }
            return folded.map(AbstractValue.immediate) ?? .unknown
        }
        if case .immediate(0) = rhs {
            switch op {
            case .add, .subtract, .bitOr, .bitXor, .shiftLeft, .shiftRight,
                 .arithmeticShiftRight:
                return lhs
            case .multiply, .bitAnd, .multiplyHigh, .unsignedMultiplyHigh: return .immediate(0)
            case .divide, .remainder, .unsignedDivide, .unsignedRemainder:
                return .unknown // by zero — don't simplify
            case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual,
                 .unsignedLess, .unsignedLessEqual, .unsignedGreater, .unsignedGreaterEqual:
                break // a comparison against 0 is meaningful; keep it symbolic
            }
        }
        // `a - (a / b) * b` is `a % b`, the shape the compiler lowers a remainder
        // to (sdiv, then mul + sub or msub). Fold it back to the modulo.
        if op == .subtract,
           case .binary(.multiply, let quotient, let divisor) = rhs,
           case .binary(let division, let numerator, let denominator) = quotient,
           division == .divide || division == .unsignedDivide,
           numerator == lhs, denominator == divisor {
            return .binary(division == .divide ? .remainder : .unsignedRemainder, lhs, divisor)
        }
        if let folded = MagicDivision.fold(op, lhs, rhs) {
            return folded
        }
        guard Self.expressionDepth(lhs) < 8, Self.expressionDepth(rhs) < 8 else { return .unknown }
        return .binary(op, lhs, rhs)
    }

    /// Build a floating-point binary node. Unlike `expression`, it never folds
    /// constants or applies algebraic identities (`x + 0`, `x * 0`) — those hold
    /// for two's-complement integers but not for IEEE floats (`-0.0`, `NaN`,
    /// `Inf`), and an FP register never carries an `.immediate` anyway.
    private func floatBinary(
        _ op: AbstractBinaryOperator, _ lhs: AbstractValue, _ rhs: AbstractValue
    ) -> AbstractValue {
        guard lhs != .unknown, rhs != .unknown,
              Self.expressionDepth(lhs) < 8, Self.expressionDepth(rhs) < 8
        else { return .unknown }
        return .binary(op, lhs, rhs)
    }

    private func floatUnary(_ op: AbstractUnaryOperator, _ value: AbstractValue) -> AbstractValue {
        guard value != .unknown, Self.expressionDepth(value) < 8 else { return .unknown }
        return .unary(op, value)
    }

    /// The tracked flags value from the most recent modelled compare, keyed so it
    /// flows through the register map and the block meet like any other state.
    private static let flagsKey = "nzcv.flags"

    /// Instruction ids that write NZCV but that we do NOT reconstruct into a
    /// comparison — float and conditional compares, and the flag-setting
    /// arithmetic (`adds`/`subs`/`ands` and friends). A `cset` after one of these
    /// must not read a stale integer comparison, so they invalidate the flags.
    private static let unmodeledFlagWriters: Set<UInt32> = Set([
        AARCH64_INS_FCMP, AARCH64_INS_FCMPE, AARCH64_INS_FCCMP, AARCH64_INS_FCCMPE,
        AARCH64_INS_CCMP, AARCH64_INS_CCMN, AARCH64_INS_BICS, AARCH64_INS_ADCS,
        AARCH64_INS_SBCS,
    ].map(\.rawValue))

    /// Reconstruct a boolean comparison from a flags value and a comparison
    /// operator. A `cmp a, b` stores `a - b`, so a `.subtract` node unwraps to a
    /// direct `a <op> b`; anything else (a `tst`'s `a & b`, or a `cmp a, #0`
    /// folded to just `a`) compares against zero.
    private func comparisonValue(flags: AbstractValue, _ op: AbstractBinaryOperator) -> AbstractValue {
        let lhs: AbstractValue, rhs: AbstractValue
        if case .binary(.subtract, let a, let b) = flags {
            lhs = a; rhs = b
        } else {
            lhs = flags; rhs = .immediate(0)
        }
        // Through `expression` so a comparison of two known constants folds to its
        // 0/1 result (`(0 != 0)` → 0) instead of printing the trivial compare.
        return expression(op, lhs, rhs)
    }

    /// The comparison a condition code denotes after a subtract-based compare.
    /// Signed and unsigned variants collapse to one symbol set; the unordered,
    /// overflow, and always/never codes are left unmodelled.
    private static func comparisonOperator(_ cc: AArch64CC_CondCode) -> AbstractBinaryOperator? {
        if cc == AArch64CC_EQ { return .equal }
        if cc == AArch64CC_NE { return .notEqual }
        // Signed ordered (LT/GE/GT/LE) and the sign-flag codes (MI/PL) map to the
        // signed operators; the unsigned ordered codes (LO/HS/HI/LS) map to the
        // unsigned operators — preserving, not merging, the machine's signedness.
        if cc == AArch64CC_GE || cc == AArch64CC_PL { return .greaterEqual }
        if cc == AArch64CC_LT || cc == AArch64CC_MI { return .less }
        if cc == AArch64CC_GT { return .greater }
        if cc == AArch64CC_LE { return .lessEqual }
        if cc == AArch64CC_HS { return .unsignedGreaterEqual }
        if cc == AArch64CC_LO { return .unsignedLess }
        if cc == AArch64CC_HI { return .unsignedGreater }
        if cc == AArch64CC_LS { return .unsignedLessEqual }
        return nil
    }

    private static func expressionDepth(_ value: AbstractValue) -> Int {
        switch value {
        case .binary(_, let lhs, let rhs): return 1 + max(expressionDepth(lhs), expressionDepth(rhs))
        case .unary(_, let operand): return 1 + expressionDepth(operand)
        case .select(let condition, let whenTrue, let whenFalse):
            return 1 + max(expressionDepth(condition), expressionDepth(whenTrue), expressionDepth(whenFalse))
        default: return 0
        }
    }

    /// Forget every register or slot whose value was read from a self field:
    /// after a store through self it is a snapshot, not the field. Recovered
    /// from the pre-merge stash (983aa25), with its native-execution oracle.
    private static func invalidateSelfFieldAliases(in registers: inout State) {
        let keys = registers.compactMap { key, value in containsSelfFieldValue(value) ? key : nil }
        for key in keys { registers[key] = nil }
    }

    private static func containsSelfFieldValue(_ value: AbstractValue) -> Bool {
        switch value {
        case .selfFieldValue: return true
        case .unary(_, let operand): return containsSelfFieldValue(operand)
        case .binary(_, let lhs, let rhs):
            return containsSelfFieldValue(lhs) || containsSelfFieldValue(rhs)
        case .select(let condition, let yes, let no):
            return containsSelfFieldValue(condition) || containsSelfFieldValue(yes)
                || containsSelfFieldValue(no)
        case .aggregate(let values): return values.contains(where: containsSelfFieldValue)
        default: return false
        }
    }

    /// Read one scalar or a SIMD-packed run of eight-byte stack values.
    private static func stackValue(at offset: Int64, bytes: Int, in registers: State) -> AbstractValue {
        guard bytes > 8 else { return registers[stackKey(offset)] ?? .unknown }
        let words = stride(from: 0, to: bytes, by: 8).map {
            registers[stackKey(offset + Int64($0))] ?? .unknown
        }
        guard words.allSatisfy({ $0 != .unknown }) else { return .unknown }
        return .aggregate(words)
    }

    /// Store a scalar or unpack a SIMD value into consecutive stack words.
    private static func storeStack(
        _ value: AbstractValue,
        at offset: Int64,
        bytes: Int,
        outgoing: Bool,
        into registers: inout State
    ) {
        let words: [AbstractValue]
        if case .aggregate(let packed) = value, bytes > 8 {
            words = Array(packed.prefix(max(1, (bytes + 7) / 8)))
        } else {
            words = [value]
        }
        for (index, word) in words.enumerated() {
            let wordOffset = offset + Int64(index * 8)
            registers[stackKey(wordOffset)] = word
            if outgoing { registers[outgoingKey(wordOffset)] = word }
        }
    }

    /// The value an operand supplies: a register's tracked value, or a literal.
    private func source(_ operand: StructuredOperandInfo, in registers: State) -> AbstractValue {
        if let shifted = operand.shiftedImmediate { return .immediate(UInt64(bitPattern: shifted)) }
        guard let reg = operand.operand.register else { return .unknown }
        if reg.kind == .zero { return .immediate(0) }
        let value = registers[reg.key] ?? .unknown
        switch operand.shift.type {
        case AARCH64_SFT_INVALID: return value
        case AARCH64_SFT_LSL:
            return expression(.shiftLeft, value, .immediate(UInt64(operand.shift.amount)))
        case AARCH64_SFT_LSR, AARCH64_SFT_ASR:
            let op: AbstractBinaryOperator = operand.shift.type == AARCH64_SFT_ASR
                ? .arithmeticShiftRight : .shiftRight
            return expression(op, value, .immediate(UInt64(operand.shift.amount)))
        default:
            return .unknown
        }
    }

    private func destinationRegister(_ detail: StructuredInsn) -> PhysReg? {
        detail.operands.first?.operand.register
    }

    private enum MemoryTarget {
        case stackSlot(String)
        case absolute(UInt64)
        /// A byte offset into `self`.
        case selfField(Int)
        /// A byte offset into `self`'s class metadata vtable — a load through the
        /// metadata pointer that lives at `self + 0`.
        case vtableMethod(Int)
        /// A store of an element into the array-literal built at `site`, at the
        /// given byte offset within the array object.
        case arrayElement(site: UInt64, offset: Int)
        /// A byte offset into the incoming x8 result buffer.
        case resultSlot(Int)
        /// A byte offset into the function's own async context.
        case asyncSlot(Int)
        /// A byte offset into the awaited callee's context (x22 at an
        /// await-return funclet).
        case asyncCalleeSlot(Int)
    }

    /// What a pointer-width load from the function's own async context yields:
    /// offset 8 is the ABI's ResumeParent, the continuation an async function
    /// returns through; any other slot is a spill, known only when the chain
    /// pass proved its single store.
    private func asyncSlotValue(at offset: Int) -> AbstractValue {
        if offset == 8 { return .asyncResumeParent }
        return asyncContextSlots[offset] ?? .asyncContextSlot(offset)
    }

    /// Where a memory operand points, when its base is a known frame offset or a
    /// known absolute address. A register index (`[x0, w1, uxtw #3]`) is left
    /// unresolved rather than guessed.
    private func memoryTarget(_ detail: StructuredInsn, in registers: State) -> MemoryTarget? {
        guard let operand = detail.operands.first(where: { $0.operand.isMemory }),
              case .memory(let base, let index, let displacement) = operand.operand,
              let base, index == nil
        else { return nil }
        // Post-index accesses the base itself; the displacement applies after.
        let effective = detail.postIndex ? 0 : displacement
        switch registers[base.key] {
        case .frame(let offset): return .stackSlot(Self.stackKey(offset &+ effective))
        case .address(let address): return .absolute(address &+ UInt64(bitPattern: effective))
        case .selfPointer: return .selfField(Int(effective))
        case .selfField(let field): return .selfField(field + Int(effective))
        // A load through the metadata pointer at `self + 0` (a class instance's
        // isa) reaches the vtable — the second `ldr` of a virtual dispatch.
        case .selfFieldValue(0): return .vtableMethod(Int(effective))
        // A store into a freshly-allocated array literal, keyed by its site.
        case .arrayLiteral(let site, _): return .arrayElement(site: site, offset: Int(effective))
        case .indirectResultPointer: return .resultSlot(Int(effective))
        case .indirectResultField(let base): return .resultSlot(base + Int(effective))
        case .asyncContext: return .asyncSlot(Int(effective))
        case .asyncCalleeContext: return .asyncCalleeSlot(Int(effective))
        default: return nil
        }
    }

    /// Access width in bytes.
    ///
    /// `aarch64_op_mem` carries no width, so it comes from the instruction id plus
    /// the destination register's width: `ldr w0` reads 4 bytes, `ldr x0` reads
    /// 8, and `ldp x19, x20` reads 16 — which is exactly how a 16-byte
    /// `Swift.String` field is loaded.
    private static func accessBytes(_ detail: StructuredInsn) -> Int? {
        let registerBytes = detail.operands.first?.operand.register.map { $0.widthBits / 8 }
        switch detail.id {
        case AARCH64_INS_LDRB, AARCH64_INS_LDURB, AARCH64_INS_STRB, AARCH64_INS_STURB,
             AARCH64_INS_LDRSB, AARCH64_INS_LDURSB:
            return 1
        case AARCH64_INS_LDRH, AARCH64_INS_LDURH, AARCH64_INS_STRH, AARCH64_INS_STURH,
             AARCH64_INS_LDRSH, AARCH64_INS_LDURSH:
            return 2
        case AARCH64_INS_LDRSW, AARCH64_INS_LDURSW:
            return 4
        case AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_STR, AARCH64_INS_STUR:
            return registerBytes
        case AARCH64_INS_LDP, AARCH64_INS_LDNP, AARCH64_INS_STP, AARCH64_INS_STNP:
            return registerBytes.map { $0 * 2 }
        default:
            return nil
        }
    }

    private static let storeIDs: Set<UInt32> = Set([
        AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STRB, AARCH64_INS_STURB,
        AARCH64_INS_STRH, AARCH64_INS_STURH, AARCH64_INS_STP, AARCH64_INS_STNP,
    ].map(\.rawValue))

    /// Record a `self` field access, when this instruction makes one.
    private func noteFieldAccess(
        _ insn: Instruction,
        _ detail: StructuredInsn,
        in registers: State,
        _ recordAccess: ((UInt64, SelfFieldAccess) -> Void)?
    ) {
        guard let recordAccess,
              case .selfField(let offset)? = memoryTarget(detail, in: registers),
              let bytes = Self.accessBytes(detail)
        else { return }
        let isWrite = Self.storeIDs.contains(detail.id.rawValue)
        let storedValues: [AbstractValue]? = if isWrite,
            detail.id == AARCH64_INS_STP || detail.id == AARCH64_INS_STNP {
            detail.operands.prefix(2).map { source($0, in: registers) }
        } else {
            nil
        }
        recordAccess(insn.address, SelfFieldAccess(
            offset: offset,
            bytes: bytes,
            isWrite: isWrite,
            storedValue: isWrite ? detail.operands.first.map { source($0, in: registers) } : nil,
            storedValues: storedValues
        ))
    }

    /// Stack slots share the register map, under a key no register can collide with.
    private static func stackKey(_ frameOffset: Int64) -> String { "stack@\(frameOffset)" }
    private static let outgoingPrefix = "outgoing@"

    /// The register-state key for a word of the function's own async context
    /// this funclet stored, by byte offset.
    private static let contextSlotPrefix = "ownctx@"
    static func contextSlotKey(_ offset: Int) -> String { "\(contextSlotPrefix)\(offset)" }
    /// The 8-byte words a store of `bytes` at `offset` touches.
    static func contextSlotKeys(overlapping offset: Int, bytes: Int) -> [String] {
        let first = offset - ((offset % 8) + 8) % 8
        return stride(from: first - 8, to: offset + bytes, by: 8).map(contextSlotKey)
    }
    private static func outgoingKey(_ frameOffset: Int64) -> String { "\(outgoingPrefix)\(frameOffset)" }
    private static func stackOffset(from key: String) -> Int64? {
        guard key.hasPrefix("stack@") else { return nil }
        return Int64(key.dropFirst("stack@".count))
    }

    /// Apply a writeback/post-index memory operand's effect on its base register.
    /// `writeback`/`postIndex` are flags from the decoder — the old path sniffed
    /// for a trailing `!` in the operand text.
    private func applyWriteback(_ detail: StructuredInsn, into registers: inout State) {
        guard detail.writeback,
              let operand = detail.operands.first(where: { $0.operand.isMemory }),
              case .memory(let base, _, let displacement) = operand.operand,
              let base
        else { return }
        // Pre-index: the displacement is in the memory operand. Post-index: it is
        // a separate trailing immediate, and mem.disp is 0.
        let delta = detail.postIndex
            ? (detail.operands.last?.operand.immediateValue ?? 0)
            : displacement
        switch registers[base.key] {
        case .frame(let offset): registers[base.key] = .frame(offset &+ delta)
        case .address(let address): registers[base.key] = .address(address &+ UInt64(bitPattern: delta))
        default: registers[base.key] = .unknown
        }
    }

    // MARK: - Helpers

    static func trimTrailingUnknown(_ values: [AbstractValue]) -> [AbstractValue]? {
        guard let last = values.lastIndex(where: { $0 != .unknown }) else { return nil }
        return Array(values[0...last])
    }

    func testExpression(
        _ op: AbstractBinaryOperator, _ lhs: AbstractValue, _ rhs: AbstractValue
    ) -> AbstractValue {
        expression(op, lhs, rhs)
    }
}

/// The registers `ValueTracer.write` touched during one instruction's
/// transfer, kept only while a probe checks that every write was modelled.
final class TracerWriteLog: @unchecked Sendable {
    @TaskLocal static var current: TracerWriteLog?
    var keys = Set<String>()
}
