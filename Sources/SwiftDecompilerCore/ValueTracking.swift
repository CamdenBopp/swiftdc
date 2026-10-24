import Ccapstone
import Foundation
import Synchronization

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
        // The register bit pattern does not inherit the source operand's
        // signedness. Preserve the machine operation even in UInt returns.
        case .shiftRight: ">>\u{1D41}"
        case .arithmeticShiftRight: ">>\u{02E2}"
        case .multiplyHigh: "mulh\u{02E2}"
        case .unsignedMultiplyHigh: "mulh\u{1D41}"
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
    /// Reverse bytes independently within each 16/32/64-bit chunk of the
    /// operand's bit pattern. Register-width normalization stays explicit.
    case byteSwap(bits: Int)
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
    /// The second word (x1) of the two-word result of the call at this
    /// address, for a callee whose signature returns a `Swift.String`: with
    /// `.callResult` of the same call in x0, the whole String.
    case callResultHigh(UInt64)
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

/// The frame facts a function's own instructions fix: offsets that start a
/// separately addressed local or a register save (escaped regions end at the
/// next one), and the save slots themselves.
struct FrameLayout: Sendable {
    var boundaries: [Int64] = []
    var saveSlots: Set<Int64> = []
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
    /// The bytes the store into each `stackArguments` slot wrote, 0 where
    /// unknown. Apple arm64 packs stack arguments to their own alignment, so
    /// one eight-byte slot can hold two four-byte arguments, and clang
    /// merges their stores into one: a slot is one argument only where its
    /// store matches it.
    public var stackArgumentWidths: [Int] = []
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
    /// A paired load's register width: its first register reads the first
    /// `registerBytes` of the access and its second the rest. Nil for any
    /// other access.
    public var registerBytes: Int? = nil
}

/// A named loop-carried variable's proven constant value on entry.
public struct LoopInitialization: Sendable, Equatable {
    public var name: String
    public var value: UInt64
    public var stackOffset: Int64?
    public init(name: String, value: UInt64, stackOffset: Int64? = nil) {
        self.name = name; self.value = value; self.stackOffset = stackOffset
    }
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
    /// condition code. Compare-and-branch forms (`cbz`/`tbz`) instead recover
    /// their tested register directly. Lets the structurer render source-named
    /// conditions in place of raw registers.
    public var branchConditions: [UInt64: AbstractValue] = [:]
    /// Proven loop induction body updates, keyed by the loop header's branch
    /// instruction — statements (`total += i`, `i += 1`) emitted in order
    /// (accumulate then advance) on the loop-back transfer. Only set for proven
    /// linear/accumulator recurrences
    /// (see `resolveLoopInductions`).
    public var loopUpdates: [UInt64: [String]] = [:]
    /// Entry bindings keyed by the header branch. Render immediately before
    /// entering its structured loop, including each nested-loop invocation.
    public var loopInitializations: [UInt64: [LoopInitialization]] = [:]
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
    /// Offset of `self` → the widths of the stores that left their source
    /// register named as the field there (`.selfFieldValue`): such a value
    /// is that many bytes, whatever the field's size.
    public var selfFieldAliasWidths: [Int: Set<Int>] = [:]
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
    /// Definite own-context values immediately before each entry branch.
    /// Used to prove initialized slots at suspension, never to seed entry.
    public var asyncSlotFactsAtBranches: [UInt64: [Int: AbstractValue]] = [:]
    /// An incomplete analysis cannot establish absence of context mutations.
    /// Completed snapshots set this false, then flag unbounded memory writes.
    public var asyncUnboundedMemoryWrites = true
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
    /// Only the chain pass requests entry transfer facts; ordinary analysis
    /// avoids scanning/copying slot state at every async branch.
    var asyncSlotFactBranches: Set<UInt64> = []
    /// The fixpoint's worklist bound, per block. Past it the analysis claims
    /// nothing (`values.fixpoint-cap`). Injectable so a test can force it.
    var iterationsPerBlock = 64
    /// The loop-induction pass's own bound: `(body blocks + 1) ×` this many
    /// block visits.
    var loopBodyIterationsPerBlock = 8

    /// Callee address → the callee-saved registers its body writes without
    /// saving (`CalleeRegisterSummary`): an outlined fragment reached by `bl`
    /// does not preserve them, so they are forgotten after a call to it.
    var calleeClobbers: [UInt64: Set<String>] = [:]
    /// In-image call targets whose bodies write no field of any object
    /// (`CalleeRegisterSummary.writesNoFields`).
    var fieldPreservingCallees: Set<UInt64> = []

    /// Callees that use the caller's x29 as a pointer
    /// (`CalleeRegisterSummary.readsFramePointer`): a call to one may write
    /// anywhere in this frame, above or below the frame record x29 holds.
    var framePointerUsers: Set<UInt64> = []

    /// Call targets that are functions of this image. The known C arity a
    /// callee's name gives is evidence only for the library function of
    /// that name, not for an in-image function that shares it.
    var inImageCallTargets: Set<UInt64> = []

    /// Callees that use the caller's x22 as a pointer
    /// (`CalleeRegisterSummary.readsContextRegister`): a call to one may write
    /// the async context x22 holds, though no argument hands it over.
    var contextRegisterUsers: Set<UInt64> = []

    /// Additional results proven void by a resolved indirect target or an
    /// Objective-C receiver's declared signature. A selector name alone is
    /// never proof of its return convention.
    var voidCallSites = Set<UInt64>()
    var callReturnsVoid: (@Sendable (_ callee: String, CallSite) -> Bool)?

    public init(calleeConventions: [UInt64: CalleeResultConvention] = [:], asyncContextSlots: [Int: AbstractValue] = [:]) {
        self.calleeConventions = calleeConventions
        self.asyncContextSlots = asyncContextSlots
    }

    /// A place the tracer keeps a fact: a register, a frame, context or
    /// result-buffer word, the flags, or a marker. These were string keys
    /// (`"x3"`, `"stack@-16"`); hashing, building and re-parsing them was
    /// about half the tracer's time (docs/IR.md, step 3). `description` is
    /// the former spelling.
    enum Location: Hashable, Sendable, CustomStringConvertible {
        case x(Int)
        case v(Int)
        case sp
        case zero
        case nzcv
        case otherRegister(Int)
        /// A frame word by offset, its stored width, and the copy of a store
        /// at or above sp kept as a possible outgoing stack argument.
        case stack(Int64)
        case stackWidth(Int64)
        case outgoing(Int64)
        /// A word of the function's own async context, by byte offset.
        case contextSlot(Int)
        /// The awaited callee's context's first word: its parent.
        case calleeParent
        /// A store through the incoming x8 (`resultKey`), and the
        /// whole-buffer and poison markers. `bytes` is an access width, and
        /// `Int32` keeps the key at 16 bytes, the size of the string keys.
        case result(offset: Int, bytes: Int32)
        case resultWhole
        case resultPoison
        case flags
        case flagsWidth
        /// x20 was written since the last call (see `selfFreshKey`).
        case selfFresh
        /// The escape markers (see "Escaped frame memory").
        case frameEscaped(Int64)
        case frameBelow(Int64)
        case frameEscapedAll
        /// sp was moved below offset k by a non-constant amount: `frame(k) - n`
        /// there is a dynamic allocation, not a pointer back into the frame.
        case frameDynamic(Int64)
        case contextEscaped(Int64)
        case calleeContextEscaped

        init(_ register: PhysReg) {
            switch register.kind {
            case .gpr: self = .x(register.number)
            case .vector: self = .v(register.number)
            case .stackPointer: self = .sp
            case .zero: self = .zero
            case .nzcv: self = .nzcv
            case .other: self = .otherRegister(register.number)
            }
        }

        /// A register or frame word spelled as the entry-convention seeds
        /// spell it (`x2`, `v0`, `sp`, `stack@16`).
        init?(key: String) {
            if key == "sp" { self = .sp; return }
            if key.hasPrefix("stack@") {
                guard let offset = Int64(key.dropFirst("stack@".count)) else { return nil }
                self = .stack(offset)
                return
            }
            guard let first = key.first, first == "x" || first == "v", key.count > 1,
                  key.dropFirst().allSatisfy(\.isNumber), let number = Int(key.dropFirst())
            else { return nil }
            self = first == "x" ? .x(number) : .v(number)
        }

        var description: String {
            switch self {
            case .x(let n): "x\(n)"
            case .v(let n): "v\(n)"
            case .sp: "sp"
            case .zero: "xzr"
            case .nzcv: "nzcv"
            case .otherRegister(let n): "reg\(n)"
            case .stack(let k): "stack@\(k)"
            case .stackWidth(let k): "stack-width@\(k)"
            case .outgoing(let k): "outgoing@\(k)"
            case .contextSlot(let k): "ownctx@\(k)"
            case .calleeParent: "callee-context.parent"
            case .result(let offset, let bytes): "result@\(offset)/\(bytes)"
            case .resultWhole: "result.whole"
            case .resultPoison: "result.poison"
            case .flags: "nzcv.flags"
            case .flagsWidth: "nzcv.width"
            case .selfFresh: "swiftself.fresh"
            case .frameEscaped(let k): "frame.escaped@\(k)"
            case .frameBelow(let k): "frame.below@\(k)"
            case .frameEscapedAll: "frame.escaped"
            case .frameDynamic(let k): "frame.dynamic@\(k)"
            case .contextEscaped(let k): "context.escaped@\(k)"
            case .calleeContextEscaped: "callee-context.escaped"
            }
        }

        /// A general or vector register named by number (`x3`, `v0`).
        var isNumberedRegister: Bool {
            switch self {
            case .x, .v: true
            default: false
            }
        }
    }

    /// Register and stack-slot values, keyed by `Location`, so registers and
    /// slots live in one map and flow through the same meet.
    private typealias State = [Location: AbstractValue]

    /// What a call's callee name proves, whatever the register state. The
    /// tracer revisits each call on every fixpoint lap and in every later
    /// pass; parsing the name out of the annotation each time was a quarter
    /// of call transfer on Clarc, so `analyze` builds these once per call.
    struct CallFacts: Sendable {
        let callee: String
        /// False for a call to an in-image function whose name may be a
        /// library function's: the tables kept by name are no evidence for it.
        let knownArityApplies: Bool
        /// Reads through the frame addresses it receives and never writes them.
        let readsOnly: Bool
        /// Writes no field of any object: a retain, or an exclusivity
        /// access marker. A release is not one, since the deinit it can run
        /// may write anything.
        let writesNoFields: Bool
        /// The registers that may hand the callee a pointer: the parameters of
        /// a runtime entry point with a fixed C arity, anything else's x0–x8
        /// and x20.
        let passedRegisters: [Location]
        let passesNoStackArguments: Bool
        /// The demangled name carries ` throws`.
        let throwsByName: Bool
        let provablyDoesNotThrow: Bool
        /// A runtime call that returns its x0 argument (`objc_retain`).
        let returnsArgument: Bool
        /// `objc_retain_xN`: the register it retains and returns.
        let retainedRegister: Int?
        let allocatesArray: Bool
        /// A Swift signature returning `()`, or a setter.
        let returnsVoidByName: Bool
        let isSuperSend: Bool
        let hasTupleResult: Bool
        /// A Swift signature returning a String (or `String?`), whose second
        /// word comes back in x1.
        let returnsString: Bool
        /// What the SDK declares a C function returns (`SDKCPrototypes`):
        /// `v`, `i`, `f`, `d`, or `s` for a value no one register holds.
        /// Nil for a type the table could not classify.
        let cResult: Character?

        init(_ insn: Instruction) {
            self.init(callee: DisassembledFunction.calleeName(of: insn) ?? "")
        }

        /// `knownArityApplies` is false for a call to an in-image function,
        /// whose name may be a library function's without its arity.
        init(callee: String, knownArityApplies: Bool = true) {
            self.callee = callee
            self.knownArityApplies = knownArityApplies
            readsOnly = knownArityApplies && ValueTracer.readOnlyPointerCallees.contains(callee)
            let knownArity = knownArityApplies ? DisassembledFunction.knownCArity(of: callee) : nil
            passedRegisters = knownArity.map { arity in
                (0..<arity).map { Location.x($0) }
            } ?? [.x(0), .x(1), .x(2), .x(3), .x(4), .x(5), .x(6), .x(7), .x(8), .x(20)]
            passesNoStackArguments = knownArityApplies && ValueTracer.passesNoStackArguments(callee)
            throwsByName = callee.contains(" throws")
            provablyDoesNotThrow = ValueTracer.provablyDoesNotThrow(callee)
            let runtimeName = callee.hasPrefix("_") ? String(callee.dropFirst()) : callee
            returnsArgument = ValueTracer.identityRuntimeCalls.contains(runtimeName)
            retainedRegister = ValueTracer.retainedRegister(runtimeName)
            writesNoFields = knownArityApplies && (readsOnly || retainedRegister != nil
                || ValueTracer.fieldPreservingRuntimeCalls.contains(runtimeName))
            allocatesArray = callee.contains("_allocateUninitializedArray")
            returnsVoidByName = DisassembledFunction.splitSignature(callee)?.result == "()"
                || DisassembledFunction.swiftAccessorProperty(callee)?.isGetter == false
            isSuperSend = callee.hasPrefix("objc_msgSendSuper")
            hasTupleResult = DisassembledFunction.hasTupleResult(callee)
            returnsString = DisassembledFunction.splitSignature(callee)
                .map { Disassembler.twoWordStringTypes.contains($0.result) } ?? false
            cResult = knownArityApplies ? Self.result(of: DisassembledFunction.cPrototype(of: callee)) : nil
        }

        /// A declaration's result, or nil for one the table could not
        /// classify (`x`), which claims nothing about x0 or v0.
        static func result(of prototype: DisassembledFunction.CPrototype?) -> Character? {
            guard let result = prototype?.result, result != "x" else { return nil }
            return result
        }
    }

    /// `CallFacts` per callee name for one run. They are a pure function of
    /// the name, and a few thousand names serve a hundred thousand calls
    /// (Clarc: 5,636 for 103,776).
    final class CallFactsCache: Sendable {
        private let store = Mutex<[String: CallFacts]>([:])

        func facts(for callee: String) -> CallFacts {
            if let hit = store.withLock({ $0[callee] }) { return hit }
            let facts = CallFacts(callee: callee)
            store.withLock { $0[callee] = facts }
            return facts
        }
    }

    /// Shared by the tracers of one run; without it each `analyze` derives
    /// its calls' facts itself.
    var callFactsCache: CallFactsCache?

    /// What the analysed function's own instructions fix, independent of any
    /// register state: computed once per `analyze` and handed to every
    /// transfer.
    struct FunctionFacts: Sendable {
        var frame = FrameLayout()
        var calls: [UInt64: CallFacts] = [:]

        init() {}

        init(_ function: DisassembledFunction, cache: CallFactsCache?, inImageTargets: Set<UInt64> = []) {
            frame = ValueTracer.frameLayout(function.instructions)
            for insn in function.instructions where insn.controlFlow == .call {
                let callee = DisassembledFunction.calleeName(of: insn) ?? ""
                if let target = insn.branchTarget, inImageTargets.contains(target) {
                    calls[insn.address] = CallFacts(callee: callee, knownArityApplies: false)
                } else {
                    calls[insn.address] = cache?.facts(for: callee) ?? CallFacts(callee: callee)
                }
            }
        }

        func call(_ insn: Instruction) -> CallFacts { calls[insn.address] ?? CallFacts(insn) }
    }

    /// Entry state: `sp` anchors the frame at offset 0. Receiver/argument
    /// registers are seeded only when runtime or Swift metadata establishes the
    /// method convention for this exact implementation address.
    private static func initialState(entry: MethodEntryConvention?, asyncContextSlots: [Int: AbstractValue] = [:]) -> State {
        // x8 is the indirect-result address in every ARM64 convention, so the
        // seed is a fact about the ABI, not about this function; see
        // `AbstractValue.indirectResultPointer`.
        var state: State = [.sp: .frame(0), .x(8): .indirectResultPointer]
        switch entry {
        case .swiftInstance(let scalarArguments):
            state[.x(20)] = .selfPointer
            // Parameters occupy x0…/v0… independently of the `self` register
            // (x20), so an instance method's scalar arguments are seeded the same
            // way a free function's are.
            for (register, argument) in scalarArguments { if let location = Location(key: register) { state[location] = .argument(argument) } }
        case .objectiveC(let argumentCount, let typed), .objectiveCInitializer(let argumentCount, let typed):
            state[.x(0)] = .selfPointer
            // Metadata-typed locations: integer arguments in x2…, floating-point
            // ones in v0… on an independent counter, the rest on the entry stack
            // (only full 8-byte slots are supplied). A Double argument made every
            // later integer argument read one register early in the positional
            // layout below. An empty map seeds nothing: the layout is unproven.
            if let typed {
                for (location, argument) in typed {
                    if let location = Location(key: location) { state[location] = .argument(argument) }
                }
                break
            }
            // Untyped (an entry recovered from a symbol name): the all-integer
            // layout.
            // AAPCS64 has six argument registers left after self/_cmd. Further
            // ObjC arguments are stack-passed and intentionally remain unknown.
            for argument in 0 ..< min(max(argumentCount, 0), 6) {
                state[.x(argument + 2)] = .argument(argument)
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
            for (register, argument) in scalarArguments { if let location = Location(key: register) { state[location] = .argument(argument) } }
        case .swiftValueInstance(let seededRegisters):
            // `self` (and HFA parameters) arrive decomposed across SIMD registers;
            // each holds a field's value directly, so they read as `self.field` /
            // `arg<n>.field` with no x20 pointer.
            for (register, value) in seededRegisters { if let location = Location(key: register) { state[location] = value } }
        case .asyncFunclet(let base, let seededRegisters):
            state = initialState(entry: base, asyncContextSlots: asyncContextSlots)
            for (register, value) in seededRegisters { if let location = Location(key: register) { state[location] = value } }
            // ABI facts and entry seeds are mutable memory facts. They must
            // participate in the same invalidation and intersection as stores.
            state[contextSlotKey(8)] = .asyncResumeParent
            if seededRegisters.values.contains(.asyncCalleeContext) {
                state[calleeParentKey] = .asyncContext
            }
            for (offset, value) in asyncContextSlots {
                state[contextSlotKey(offset)] = value == .unknown ? nil : value
            }
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
        let facts = FunctionFacts(function, cache: callFactsCache, inImageTargets: inImageCallTargets)

        var predecessors: [UInt64: [UInt64]] = [:]
        for block in blocks {
            for successor in block.successors where blockByStart[successor] != nil {
                predecessors[successor, default: []].append(block.startAddress)
            }
        }

        // Blocks the entry or a block without predecessors (a landing pad)
        // reaches over modelled edges. Anything else runs only through an
        // edge the CFG does not model, so, like a landing pad, it starts
        // from nothing every time.
        var reached: Set<UInt64> = [function.startAddress]
        var reachWork = [function.startAddress] + blocks.map(\.startAddress).filter { predecessors[$0] == nil }
        reached.formUnion(reachWork)
        while let next = reachWork.popLast() {
            for successor in blockByStart[next]?.successors ?? [] where blockByStart[successor] != nil {
                if reached.insert(successor).inserted { reachWork.append(successor) }
            }
        }

        // Forward fixpoint: block entry state = meet of predecessors' exit states.
        var inState: [UInt64: State] = [:]
        var escapeMarkers: [UInt64: State] = [:]
        var outState: [UInt64: State] = [:]
        var worklist = blocks.map(\.startAddress)
        var queued = Set(worklist)
        var iterations = 0
        let cap = blocks.count * iterationsPerBlock + 16 // safety bound
        while let addr = worklist.first {
            worklist.removeFirst()
            queued.remove(addr)
            iterations += 1
            if iterations > cap {
                // The states are not a fixpoint: a block whose predecessors
                // were not all revisited holds an optimistic meet, and the
                // snapshot pass would replay it as proof. Claim nothing.
                Probe.record(.tracerFixpointCap, ["blocks": .int(blocks.count), "cap": .int(cap)])
                return FunctionAnalysis()
            }
            guard let block = blockByStart[addr] else { continue }
            let preds = predecessors[addr] ?? []
            // Only the function's entry receives the caller's ABI state. A block
            // with no predecessor may be an exception landing pad: its x0 is the
            // exception and its frame is the prologue's, not the entry's, so it
            // starts with nothing proven. And the entry keeps the caller as an
            // incoming edge when a loop branches back to it; met only with its
            // back edges, it lost its arguments and self.
            var incoming: [State] = []
            if reached.contains(addr) {
                incoming = preds.compactMap { outState[$0] }
                if addr == function.startAddress { incoming.append(Self.initialState(entry: entry, asyncContextSlots: asyncContextSlots)) }
                // None of its predecessors has run: not reached yet, so its
                // entry is unconstrained, not empty. Run from nothing, it
                // gained facts once a predecessor ran, entry states grew
                // after shrinking, and a loop that rotates values between
                // registers never settled (`values.fixpoint-cap`).
                if incoming.isEmpty, !preds.isEmpty { continue }
            }
            var blockEntry = Self.meet(incoming)
            // An escape the meet derives from a dropped address can stop being
            // derived on a later lap once the incoming values agree, and the
            // loop never settles. Escapes are MAY facts: once one reaches a
            // block it stays.
            for (key, value) in escapeMarkers[addr] ?? [:] where blockEntry[key] == nil { blockEntry[key] = value }
            escapeMarkers[addr] = blockEntry.filter { Self.isEscapeMarker($0.key) }
            inState[addr] = blockEntry
            var registers = blockEntry
            for insn in block.instructions {
                transfer(
                    insn, into: &registers, record: nil, recordAccess: nil,
                    initializerEntry: entry?.isObjectiveCInitializer == true,
                    facts: facts
                )
            }
            if !Self.sameFacts(outState[addr], registers) {
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
        resolveAcyclicSelects(
            blocks: blocks, predecessors: predecessors,
            blockByStart: blockByStart, inState: &inState, outState: outState,
            entry: entry, facts: facts
        )
        // Loop-carried induction variables: a header slot with a proven constant
        // initial value and a proven `i ± c` recurrence across the back-edge is
        // named `.local(i)`, so the loop's exit comparison reconstructs with a
        // name (`i < n`) instead of raw registers, and its body update `i += c` is
        // recorded. Declines anything unproven.
        let loopBindings = resolveLoopInductions(
            blocks: blocks, predecessors: predecessors,
            blockByStart: blockByStart, inState: &inState, outState: outState,
            facts: facts
        )

        // Snapshot pass: replay from each block's fixed entry state, recording
        // call arguments and self-field accesses.
        var result = FunctionAnalysis()
        result.asyncUnboundedMemoryWrites = false
        result.loopUpdates = loopBindings.updates
        result.loopInitializations = loopBindings.initializations
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
                   let value = registers[.x(0)], value != .unknown {
                    result.exitValues[insn.address] = value
                }
                if insn.controlFlow == .return,
                   let value = registers[.x(21)], value != .unknown {
                    result.exitErrorValues[insn.address] = value
                }
                // Also at a proven async return (a `br` through the context's
                // ResumeParent): a Double-returning async function delivers in
                // v0 there. Not at other branches: a recorded v0 would make the
                // enrichment pass run on a function it otherwise skips, and v0
                // before an ordinary tail call is the callee's argument.
                let isAsyncReturn = insn.controlFlow == .branch
                    && Self.indirectTarget(of: insn, in: registers) == .asyncResumeParent
                if isAsyncReturn, let value = registers[.x(20)], value != .unknown {
                    result.exitAsyncErrorValues[insn.address] = value
                }
                // A floating return is a scalar in d0 or s0: the d view, not
                // the whole register (`movi v0.2d, #0; ret` is `return 0`).
                if insn.controlFlow == .return || isAsyncReturn,
                   let value = registers[.v(0)].map({ Self.scalarView($0, bits: 64) }), value != .unknown {
                    result.exitFloatValues[insn.address] = value
                }
                // x1 at a return is the first yielded value of a `yield_once`
                // coroutine (`_modify`/`_read`); meaningless for an ordinary
                // return, so the enrichment reads it only for those accessors.
                if insn.controlFlow == .return,
                   let value = registers[.x(1)], value != .unknown {
                    result.exitYieldValues[insn.address] = value
                }
                if insn.controlFlow == .return {
                    let exit = Self.indirectResultExit(registers)
                    if exit.poisoned || exit.whole != nil || !exit.stores.isEmpty {
                        result.exitIndirectResults[insn.address] = exit
                    }
                }
                if insn.controlFlow == .branch {
                    if asyncSlotFactBranches.contains(insn.address) {
                        result.asyncSlotFactsAtBranches[insn.address] = Dictionary(uniqueKeysWithValues:
                            registers.compactMap { key, value -> (Int, AbstractValue)? in
                                guard case .contextSlot(let offset) = key, value != .unknown else { return nil }
                                return (offset, value)
                            })
                    }
                    let site = Self.snapshot(registers, saveSlots: facts.frame.saveSlots)
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
                    recordUnboundedMemoryWrite: { result.asyncUnboundedMemoryWrites = true },
                    recordFieldAlias: { result.selfFieldAliasWidths[$0, default: []].insert($1) },
                    initializerEntry: entry?.isObjectiveCInitializer == true,
                    facts: facts
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
                        result.exitErrorValuesByPredecessor[insn.address, default: [:]][end] = registers[.x(21)] ?? .unknown
                        break
                    }
                    transfer(insn, into: &registers, record: nil, recordAccess: nil,
                             initializerEntry: entry?.isObjectiveCInitializer == true, facts: facts)
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
    ///
    /// The prologue's callee-saved register saves (x19–x30 stored with their
    /// entry values before the first branch or call) bound regions too: the
    /// register save area belongs to no local. An async funclet saves x22, its
    /// context pointer, there; reaching it from an escaped local escaped the
    /// context.
    static func addressTakenFrameOffsets(_ instructions: [Instruction]) -> [Int64] {
        frameLayout(instructions).boundaries
    }

    /// Region boundaries (`addressTakenFrameOffsets`) and the prologue's
    /// register save slots, which also cannot be outgoing stack arguments: a
    /// frame's save area is never its outgoing area.
    static func frameLayout(_ instructions: [Instruction]) -> FrameLayout {
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
        var prologue = true
        var written = Set<String>()
        var saveSlots = Set<Int64>()
        for instruction in instructions {
            defer {
                if let flow = instruction.controlFlow, flow != .sequential { prologue = false }
                written.formUnion(instruction.detail?.writtenRegisterKeys ?? [])
            }
            if prologue, let detail = instruction.detail,
               detail.id == AARCH64_INS_STR || detail.id == AARCH64_INS_STUR || detail.id == AARCH64_INS_STP {
                let count = detail.id == AARCH64_INS_STP ? 2 : 1
                let sources = detail.operands.prefix(count).compactMap(\.operand.register)
                if sources.count == count, sources.allSatisfy({ register in
                       register.kind == .gpr && register.widthBits == 64 && (19...30).contains(register.number)
                           && !written.contains(register.key)
                   }),
                   let memory = detail.operands.first(where: { $0.operand.isMemory }),
                   case .memory(let base?, nil, let displacement) = memory.operand {
                    let effective = detail.postIndex ? 0 : displacement
                    let slot: Int64? = base.kind == .stackPointer ? sp + effective
                        : base.key == "x29" ? fp.map { $0 + effective } : nil
                    if let slot {
                        for index in 0..<count {
                            offsets.insert(slot + Int64(index * 8))
                            saveSlots.insert(slot + Int64(index * 8))
                        }
                    }
                }
            } else if instruction.controlFlow == .call {
                prologue = false
            }
            // Every rule below needs an operand that is sp or x29 or starts
            // with `[sp`; most instructions name neither register.
            guard namesFrameRegister(instruction.text) else { continue }
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
        return FrameLayout(boundaries: offsets.sorted(), saveSlots: saveSlots)
    }

    /// Whether `text` contains `sp` or `x29` anywhere: the cheap filter in
    /// front of `frameLayout`'s operand parse.
    private static func namesFrameRegister(_ text: String) -> Bool {
        var previous: UInt8 = 0
        var beforePrevious: UInt8 = 0
        for byte in text.utf8 {
            if previous == UInt8(ascii: "s"), byte == UInt8(ascii: "p") { return true }
            if beforePrevious == UInt8(ascii: "x"), previous == UInt8(ascii: "2"), byte == UInt8(ascii: "9") { return true }
            beforePrevious = previous
            previous = byte
        }
        return false
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
        return registers[Location(register)] ?? .unknown
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
        return Dictionary(uniqueKeysWithValues: registers.map { ($0.key.description, $0.value) })
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
        recordUnboundedMemoryWrite: (() -> Void)? = nil,
        recordFieldAlias: ((Int, Int) -> Void)? = nil,
        initializerEntry: Bool = false,
        facts: FunctionFacts = FunctionFacts()
    ) {
        if insn.controlFlow == .call {
            let site = Self.snapshot(registers, saveSlots: facts.frame.saveSlots)
            if let record {
                if !site.isEmpty { record(insn.address, site) }
            }
            let incomingX0 = registers[.x(0)] ?? .unknown
            let beforeCall = registers
            // `memcpy`/`memset` and the outlined value-witness copies are modelled
            // as the stores they perform (see `applyMemoryHelper`): their source
            // must be read before the invalidation below forgets it, and their
            // destination is written exactly, so the generic invalidation does
            // not apply to them. An in-image function named `memset` is an
            // ordinary call: a `memset(&a, 0, 8)` whose body writes nothing
            // rendered the `a` loaded after it as 0.
            let call = facts.call(insn)
            let handledAsMemoryHelper = call.knownArityApplies
                && applyMemoryHelper(callee: call.callee, site: site, into: &registers)
            // A local whose address the call receives may be written by it: an
            // NSError out-parameter (`str xzr, [sp]; mov x3, sp; bl …error:`),
            // an `inout` struct, an x8 result buffer, a `mutating` self in x20.
            // Keeping the pre-call value rendered the error a failed call
            // reported as the `nil` stored before it
            // (`_convertNSErrorToError(0)`, SwiftData). The callee may also
            // keep the address, so it stays escaped for every later call
            // (`forgetEscapedFrame`), and so does one that escaped earlier: a
            // frame address stored to a global before a call that writes
            // through the global rendered the pre-call value (`cacheEscape`).
            // A helper that only reads through its pointer leaves the local
            // intact: projecting an existential container yields a pointer to
            // its payload and must not erase the container's type and witness
            // words, or the witness-table call through them goes unresolved
            // (guarded by `resolvesConcreteWitnessTableDispatchIfPresent`).
            // Neither it nor an exactly modelled memory helper keeps a pointer.
            if !(call.readsOnly || handledAsMemoryHelper) {
                // A runtime entry point with a fixed C arity receives only its
                // parameters; anything else may also be an input.
                for key in call.passedRegisters {
                    if let value = registers[key] { Self.markEscape(value, into: &registers) }
                }
                // x29 is not an argument, but a callee that uses it reaches
                // the frame through it, below the frame record as well as
                // above it (`[x29, #-8]`), so the whole frame escapes.
                if let target = insn.branchTarget, framePointerUsers.contains(target),
                   case .frame? = registers[.x(29)] {
                    registers[Self.frameEscapeAllKey] = .immediate(1)
                }
                // The same for x22: preserving the register does not preserve
                // the context it points at.
                if let target = insn.branchTarget, contextRegisterUsers.contains(target),
                   let context = registers[.x(22)] {
                    Self.markEscape(context, into: &registers)
                }
                // Stack arguments are the words stored upward from sp at the
                // call (`snapshot`); only a callee that can take any reads them,
                // and never from the prologue's register save area.
                if !call.passesNoStackArguments, case .frame(let base)? = registers[.sp] {
                    for slot in 0..<16 {
                        let offset = base + Int64(slot * 8)
                        guard !facts.frame.saveSlots.contains(offset), let value = registers[Self.outgoingKey(offset)]
                        else { break }
                        Self.markEscape(value, into: &registers)
                    }
                }
                Self.forgetEscapedFrame(in: &registers, addressTaken: facts.frame.boundaries)
                // An escaped context pointer may be written through by any
                // call, from its offset up.
                let contextReach = registers.keys.compactMap { key -> Int64? in
                    if case .contextEscaped(let offset) = key { offset } else { nil }
                }.min()
                if let contextReach {
                    for key in registers.keys {
                        if case .contextSlot(let offset) = key, Int64(offset) &+ 8 > contextReach {
                            registers[key] = nil
                        }
                    }
                    recordUnboundedMemoryWrite?()
                }
                if registers[Self.calleeContextEscapeKey] != nil {
                    registers[Self.calleeParentKey] = nil
                }
            }
            // A register that held a field of self held its value before the
            // call, and the call may write the field: `let old = a; bumpA();
            // b = old` rendered `bumpA(); self.b = self.a`, the new a, and
            // `a = x; bumpA(); b = x` the same. A store to a field already
            // forgets these; so does any call but a retain or an access
            // marker, a memory helper included, since its destination may be
            // a field.
            if !call.writesNoFields, !(insn.branchTarget.map(fieldPreservingCallees.contains) ?? false) {
                Self.invalidateSelfFieldAliases(in: &registers)
            }
            if !handledAsMemoryHelper { applyCallToResultBuffers(insn, site: site, into: &registers) }
            // AAPCS64: x0–x17 are caller-saved, so a call clobbers them. x18 is
            // reserved, x19–x28 are callee-saved — and preserving those is what
            // carries `self` and locals across a call.
            for index in 1...17 { registers[.x(index)] = .unknown }
            registers[.x(30)] = .unknown
            // A callee handed the context (in an argument register; a call
            // reached with `bl` gets x22 only as callee-saved state) may write
            // it. `site` is the argument snapshot taken above.
            if site.arguments.contains(.asyncContext) || site.selfValue == .asyncContext {
                for key in registers.keys where Self.isContextSlot(key) { registers[key] = nil }
            }
            if let target = insn.branchTarget, let clobbered = calleeClobbers[target] {
                for key in clobbered { if let location = Location(key: key) { registers[location] = .unknown } }
            }
            // The vector/floating-point bank: v0–v7 and v16–v31 are caller-saved
            // (only the low 64 bits of v8–v15 survive a call). Clobbering them is
            // what stops a stale `d0` from before the call being read as the
            // call's floating-point result after it.
            for index in 0...7 { registers[.v(index)] = nil }
            for index in 16...31 { registers[.v(index)] = nil }
            let outgoingKeys = registers.keys.filter { if case .outgoing = $0 { true } else { false } }
            for key in outgoingKeys { registers[key] = nil }
            // Swift error convention: a throwing callee returns its error in x21
            // (swifterror), so the call *redefines* x21 even though AAPCS64 marks
            // it callee-saved. Without invalidating it, a pre-call `mov x21, #0`
            // is read as a live value in the post-call error check and fabricates
            // an always-false `(0 != 0)` — a wrong render, the top severity. Gated
            // to a throwing callee (the demangled name carries ` throws`), so a C
            // or Objective-C call, where x21 is an ordinary callee-saved register
            // carrying a live value across the call, is untouched.
            if call.throwsByName {
                registers[.x(21)] = .unknown
            }
            // The same convention when the name cannot say. Zeroing x21 right
            // before a call is how a caller arms swifterror, so unless the
            // callee provably does not throw, the post-call x21 is its error,
            // not that 0. Measured in SwiftData: an `@objc` thunk calling a
            // stripped throwing method rendered its error check `if (0 != 0)`
            // and its result `return 1`.
            if registers[.x(21)] == .immediate(0), !call.provablyDoesNotThrow {
                registers[.x(21)] = .unknown
            }
            if call.returnsArgument, incomingX0 != .unknown {
                // An unknown object handed through stays the call's result:
                // something is there, which an argument list keeps as `?`.
                // Taken as unknown, `objc_enumerationMutation` of an
                // autoreleased object read `objc_enumerationMutation()`.
                registers[.x(0)] = incomingX0
            } else if let source = call.retainedRegister {
                // `objc_retain_xN` retains the object in xN and returns it
                // in x0 (libobjc's first instruction is `ands x0, xN, xN`).
                // Matched as a prefix of `objc_retain`, it returned the stale
                // x0: an `@objc` thunk passed the wrong receiver and `self`.
                registers[.x(0)] = beforeCall[.x(source)] ?? .unknown
            } else if call.allocatesArray {
                // Returns the array in x0 (and its element buffer in x1); the
                // caller fills it next, so tag it with this site and its count —
                // the first argument — so those element stores can be gathered.
                let count: Int = { if case .immediate(let n) = incomingX0 { return Int(n) } else { return -1 } }()
                registers[.x(0)] = .arrayLiteral(site: insn.address, count: count)
            } else if call.returnsVoidByName
                        || voidCallSites.contains(insn.address)
                        || callReturnsVoid?(call.callee, site) == true {
                // A Swift callee returning Void leaves x0 holding whatever it
                // last computed. As a result, it rendered a value flowing on:
                // `OUTLINED_FUNCTION_35(Swift.Hasher._combine(0))` for a fragment
                // that takes nothing after `_combine(Swift.UInt) -> ()`.
                registers[.x(0)] = .unknown
                registers[.v(0)] = nil
            } else if initializerEntry, call.isSuperSend {
                // `self = [super init…]`: after the assignment, the returned
                // object is the initializer's current self even if the runtime
                // chose a different allocation.
                registers[.x(0)] = .selfPointer
            } else if call.hasTupleResult {
                // A register can be a tuple component, not the complete call
                // expression. Project it only when its ABI layout is proven.
                registers[.x(0)] = .unknown
                registers[.v(0)] = nil
            } else if let result = call.cResult {
                // A C function's declaration says where its result is: x0 for
                // an integer or pointer, v0 for a float or double, and
                // neither for void or a struct. Taken as x0, a run of
                // void `glVertex3f` calls nested, each the previous one's
                // argument; `NSInsetRect` returns an NSRect in d0-d3, and its
                // d0 passed on read as the whole rect. The register the
                // result is not in holds whatever the callee left there.
                registers[.x(0)] = result == "i" ? .callResult(insn.address) : .unknown
                registers[.v(0)] = result == "f" || result == "d" ? .callResult(insn.address) : nil
            } else {
                // The result register — x0 for integer/pointer/reference returns,
                // v0 for a floating-point one. The callee delivers into one; only
                // the register the caller actually reads next carries it forward,
                // so modelling the result in both is faithful.
                registers[.x(0)] = .callResult(insn.address)
                registers[.v(0)] = .callResult(insn.address)
                if call.returnsString { registers[.x(1)] = .callResultHigh(insn.address) }
            }
            registers[Self.selfFreshKey] = nil
            // AAPCS64 does not preserve NZCV across a call.
            registers[Self.flagsKey] = nil
            registers[Self.flagsWidthKey] = nil
            return
        }
        let hadSelf = registers[Self.selfFreshKey]
        let inputs = noteFrameMemoryWrite(insn, into: &registers, frame: facts.frame)
        apply(insn, into: &registers, recordAccess: recordAccess,
              recordArrayElement: recordArrayElement, recordSlotStore: recordSlotStore,
              recordUnboundedMemoryWrite: recordUnboundedMemoryWrite, recordFieldAlias: recordFieldAlias)
        // A frame address or context pointer transformed beyond the tracer's
        // arithmetic still points where it did, at an offset nothing tracks.
        if inputs.frame || inputs.context, let detail = insn.detail {
            let written = detail.writtenRegisterKeys.map { Location(key: $0).flatMap { registers[$0] } }
            if inputs.frame, written.contains(where: { $0.map { !Self.containsFrame($0) } ?? true }) {
                registers[Self.frameEscapeAllKey] = .immediate(1)
            }
            if inputs.context, written.contains(where: { $0.map { !Self.containsContext($0) } ?? true }) {
                registers[.contextEscaped(0)] = .immediate(1)
                registers[Self.calleeContextEscapeKey] = .immediate(1)
            }
        }
        // sp moved below k by a non-constant amount allocates below k.
        if let sp = registers[.sp], let base = Self.allocationBase(sp) {
            registers[.frameDynamic(base)] = .immediate(1)
        }
        if Self.writesSwiftSelf(insn) {
            registers[Self.selfFreshKey] = .immediate(1)
        } else {
            registers[Self.selfFreshKey] = hadSelf
        }
    }

    /// Runtime entry points that write no field of any object.
    private static let fieldPreservingRuntimeCalls: Set<String> = [
        "swift_retain", "swift_retain_n", "swift_nonatomic_retain", "swift_nonatomic_retain_n",
        "swift_bridgeObjectRetain", "swift_bridgeObjectRetain_n", "swift_nonatomic_bridgeObjectRetain",
        "swift_unknownObjectRetain", "swift_unknownObjectRetain_n", "swift_nonatomic_unknownObjectRetain",
        "objc_retain", "objc_retainAutorelease", "objc_retainAutoreleasedReturnValue",
        "objc_claimAutoreleasedReturnValue", "objc_unsafeClaimAutoreleasedReturnValue",
        "objc_retainAutoreleaseReturnValue", "objc_autorelease", "objc_autoreleaseReturnValue",
        "objc_retainBlock", "swift_beginAccess", "swift_endAccess",
    ]

    /// Each returns the object it was handed (objc4's `objc_autorelease`,
    /// `objc_retainAutorelease`, …): the result is that value. Without
    /// `objc_autorelease` here, `[[[X alloc] init] autorelease]` used twice
    /// rendered three allocations, the autorelease's result printed as the
    /// allocation it returned at every use.
    private static let identityRuntimeCalls: Set<String> = [
        "objc_retain", "objc_claimAutoreleasedReturnValue",
        "objc_retainAutoreleasedReturnValue", "objc_autoreleaseReturnValue",
        "objc_autorelease", "objc_retainAutorelease", "objc_retainAutoreleaseReturnValue",
        "objc_unsafeClaimAutoreleasedReturnValue",
    ]

    /// N for `objc_retain_xN`, the register-specific retain stub.
    static func retainedRegister(_ name: String) -> Int? {
        let prefix = "objc_retain_x"
        guard name.hasPrefix(prefix), let n = Int(name.dropFirst(prefix.count)), (0...28).contains(n) else { return nil }
        return n
    }

    /// AAPCS64 register snapshot shared by normal calls and possible tail-call
    /// branches. Keeping the construction identical prevents the two output
    /// paths from disagreeing about the same register state.
    /// `saveSlots` ends the stack arguments: the words stored upward from sp
    /// stop at the prologue's register save area, as the escape at a call
    /// does, and the frame record is no argument.
    private static func snapshot(_ registers: State, saveSlots: Set<Int64>) -> CallSite {
        let args = (0...7).map { registers[.x($0)] ?? .unknown }
        var stackArguments: [AbstractValue] = []
        var stackArgumentWidths: [Int] = []
        if case .frame(let stackBase)? = registers[.sp] {
            for slot in 0..<16 {
                let offset = stackBase + Int64(slot * 8)
                guard !saveSlots.contains(offset), let value = registers[outgoingKey(offset)] else { break }
                stackArguments.append(value)
                if case .immediate(let bytes)? = registers[stackWidthKey(offset)], bytes <= 8 {
                    stackArgumentWidths.append(Int(bytes))
                } else {
                    stackArgumentWidths.append(0)
                }
            }
        }
        return CallSite(
            arguments: trimTrailingUnknown(args) ?? [],
            // Every reader lays out a scalar `float`/`double` here (an ObjC `f`
            // or `d`, a Swift Double/Float/CGFloat), so each is the d view.
            floatArguments: (0...7).map { scalarView(registers[.v($0)] ?? .unknown, bits: 64) },
            stackArguments: stackArguments,
            stackArgumentWidths: stackArgumentWidths,
            // Only when freshly set for *this* Swift call — see selfFreshKey.
            // The result pointer parked in callee-saved x20 (`mov x20, x8`) is
            // never a receiver, however fresh the write.
            selfValue: registers[selfFreshKey] != nil && !isResultPointer(registers[.x(20)])
                ? (registers[.x(20)] ?? .unknown) : .unknown,
            errorValue: registers[.x(21)] ?? .unknown,
            indirectResult: registers[.x(8)] ?? .unknown
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
    private static let selfFreshKey = Location.selfFresh

    private static func writesSwiftSelf(_ insn: Instruction) -> Bool {
        guard let detail = insn.detail else { return false }
        func isX20(_ register: PhysReg) -> Bool { register.kind == .gpr && register.number == 20 }
        // Branches write no general register.
        if let flow = insn.controlFlow, flow != .sequential { return false }
        switch detail.id {
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP, AARCH64_INS_STNP,
             AARCH64_INS_ALIAS_CMP, AARCH64_INS_ALIAS_CMN, AARCH64_INS_ALIAS_TST, AARCH64_INS_CCMP, AARCH64_INS_CCMN:
            // These name a register first but read it.
            return false
        case AARCH64_INS_LDP, AARCH64_INS_LDNP:
            return detail.operands.prefix(2).contains { $0.operand.register.map(isX20) ?? false }
        default:
            return detail.operands.first?.operand.register.map(isX20) ?? false
        }
    }

    /// Meet (∧) of predecessor states: a register keeps its value only when all
    /// predecessors agree; otherwise it becomes unknown (absent).
    ///
    /// The one exception is the result-buffer poison marker, which is a union:
    /// a result pointer that escaped on ANY incoming path leaves the buffer
    /// unprovable at the join, even where the other paths agree on its contents.
    /// Whether two block states prove the same facts. A plain register that
    /// is `.unknown` and one that is absent claim the same nothing, but the
    /// meet drops a key where a write stores `.unknown`, so comparing the
    /// dictionaries literally saw a loop's x9 flip between the two forever:
    /// WeatherRadio's grid sampler (20 blocks) never converged and replayed an
    /// unconverged state. Marker keys (`result.whole`, `result.poison`, the
    /// fresh-self flag) and slots mean something by presence and compare
    /// literally.
    private static func sameFacts(_ a: State?, _ b: State) -> Bool {
        guard let a else { return false }
        if a == b { return true }
        for key in Set(a.keys).union(b.keys) where a[key] != b[key] {
            guard key.isNumberedRegister, (a[key] ?? .unknown) == .unknown, (b[key] ?? .unknown) == .unknown
            else { return false }
        }
        return true
    }

    private static func meet(_ states: [State]) -> State {
        guard var accumulator = states.first else { return [:] }
        for state in states.dropFirst() {
            accumulator = accumulator.filter { state[$0.key] == $0.value }
        }
        if states.contains(where: { $0[resultPoisonKey] != nil }) {
            accumulator[resultPoisonKey] = .immediate(1)
        }
        // An address that escaped on any incoming path is reachable here, and
        // one the join drops from a register or slot is no longer followed:
        // it escapes. Copies (`.outgoing`), widths and the awaited callee's
        // parent header are not places this function keeps its pointers.
        var dropped: [AbstractValue] = []
        var unsizedSlots: [Int64] = []
        var unsizedFlags = false
        for state in states {
            for (key, value) in state {
                if isEscapeMarker(key) {
                    accumulator[key] = value
                } else if accumulator[key] != value {
                    if case .stackWidth(let offset) = key {
                        unsizedSlots.append(offset)
                    } else if key == .flagsWidth {
                        unsizedFlags = true
                    } else if holdsValue(key), containsFrame(value) || containsContext(value) {
                        dropped.append(value)
                    }
                }
            }
        }
        // A slot is known only at the width stored to it. Where the paths
        // stored different widths, the bytes beyond the narrower store are
        // whatever was there before: a value the paths agree on, read at the
        // wider width, claimed bytes one path never wrote. (A value equal at
        // two widths is unchanged by narrowing, which no address is, so no
        // pointer is lost here.) Flags are known only at the width of their
        // compare: the same constants overflow at 32 bits and not at 64.
        for offset in unsizedSlots { accumulator[.stack(offset)] = nil }
        if unsizedFlags { accumulator[.flags] = nil }
        for value in dropped { markEscape(value, into: &accumulator) }
        return accumulator
    }

    // MARK: - Indirect result buffers

    /// The buffer-contents keys: `.result(offset:bytes:)` for a store through the
    /// incoming x8, plus the whole-buffer and poison markers. They live in the
    /// register map so the block meet treats them like any other slot.
    private static let resultWholeKey = Location.resultWhole
    private static let resultPoisonKey = Location.resultPoison
    private static func resultKey(_ offset: Int, bytes: Int) -> Location { .result(offset: offset, bytes: Int32(clamping: bytes)) }
    private static func resultOffset(from key: Location) -> (offset: Int, bytes: Int)? {
        if case .result(let offset, let bytes) = key { return (offset, Int(bytes)) }
        return nil
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
            return Self.isResultPointer(registers[Location(register)])
        }
        let operands = detail.operands
        // Memory operands: a result-pointer base is modelled only with no index
        // register; a result pointer as the INDEX is never modelled.
        for operand in operands {
            if case .memory(let base, let index, _) = operand.operand {
                if let index, Self.isResultPointer(registers[Location(index)]) { return true }
                if let base, Self.isResultPointer(registers[Location(base)]) {
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
        switch registers[.x(8)] {
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
                    registers[Self.stackWidthKey(base + Int64(offset))] = .immediate(UInt64(min(8, size - offset)))
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
            registers[stackWidthKey(offset)] = nil
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
                    value = Self.stackValue(at: source + Int64(offset), bytes: bytes, in: registers)
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

    /// Forward select facts through acyclic dependencies in graph order. A
    /// diamond's new entry state must reach its outgoing branch before another
    /// diamond can use it. Cycles retain the original converged analysis;
    /// this pass never assumes a loop has reached a new fixpoint.
    private func resolveAcyclicSelects(
        blocks: [BasicBlock], predecessors: [UInt64: [UInt64]],
        blockByStart: [UInt64: BasicBlock], inState: inout [UInt64: State],
        outState: [UInt64: State], entry: MethodEntryConvention?, facts: FunctionFacts
    ) {
        let rawInState = inState
        resolveDiamondSelects(blocks: blocks, predecessors: predecessors,
                             blockByStart: blockByStart, inState: &inState, outState: outState)
        resolveSwitchSelects(blocks: blocks, predecessors: predecessors,
                            blockByStart: blockByStart, inState: &inState, outState: outState)
        guard blocks.contains(where: { (predecessors[$0.startAddress]?.count ?? 0) >= 2 }) else { return }
        var remaining = Dictionary(uniqueKeysWithValues: blocks.map { block in
            (block.startAddress, (predecessors[block.startAddress] ?? []).filter { blockByStart[$0] != nil }.count)
        })
        var queue = remaining.keys.filter { remaining[$0] == 0 }.sorted(), cursor = 0
        var forwarded = outState
        Probe.muted {
            while cursor < queue.count {
                let address = queue[cursor]; cursor += 1
                guard let block = blockByStart[address] else { continue }
                var inputs = (predecessors[address] ?? []).compactMap { forwarded[$0] }
                if address == blocks.first?.startAddress { inputs.append(Self.initialState(entry: entry, asyncContextSlots: asyncContextSlots)) }
                let prior = rawInState[address]
                inState[address] = Self.meet(inputs)
                resolveDiamondSelects(blocks: [block], predecessors: predecessors,
                                     blockByStart: blockByStart, inState: &inState, outState: forwarded)
                resolveSwitchSelects(blocks: [block], predecessors: predecessors,
                                    blockByStart: blockByStart, inState: &inState, outState: forwarded)
                let incoming = inState[address] ?? [:]
                if !Self.sameFacts(prior, incoming) {
                    var registers = incoming
                    for insn in block.instructions {
                        transfer(insn, into: &registers, record: nil, recordAccess: nil,
                                 initializerEntry: entry?.isObjectiveCInitializer == true, facts: facts)
                    }
                    forwarded[address] = registers
                }
                for successor in block.successors.sorted() where remaining[successor] != nil {
                    remaining[successor, default: 0] -= 1
                    if remaining[successor] == 0 { queue.append(successor) }
                }
            }
        }
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
        facts: FunctionFacts
    ) -> (updates: [UInt64: [String]], initializations: [UInt64: [LoopInitialization]]) {
        var updates: [UInt64: [String]] = [:]
        var initializations: [UInt64: [LoopInitialization]] = [:]
        var sourcesByHeader: [UInt64: [UInt64]] = [:]
        for (from, header) in Self.backEdges(blocks: blocks, blockByStart: blockByStart) {
            sourcesByHeader[header, default: []].append(from)
        }
        var displayId = 0
        var accumulatorId = 0
        // The converged states, before any loop's names are written back:
        // the facts that hold on every lap, back-edge arrivals included.
        let converged = inState
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
            // Ordered by the slots' former string keys (`stack@-16` before
            // `stack@-8`): the order numbers the placeholders, and so the names.
            let candidateKeys = preLoopEntry.keys.filter { key in
                guard case .stack = key, case .immediate = preLoopEntry[key] else { return false }
                return (headerIn[key] ?? .unknown) == .unknown
            }.sorted { $0.description < $1.description }
            guard !candidateKeys.isEmpty else { continue }
            // Seed each candidate with a fresh placeholder and re-transfer the loop
            // body so the back-edge value is expressed in terms of the placeholder.
            // Every other fact is the converged header's, which holds on every
            // lap: seeded from the loop's entry alone, the lap missed what only
            // the back edge brings (an address escaped at the end of the body,
            // a pointer slot that changes after the first lap), so `i += 1`
            // and `j += 100` were claimed where a later lap writes `i` too.
            var seed = converged[header] ?? [:]
            var placeholderId: [Int: Location] = [:]
            for (offset, key) in candidateKeys.enumerated() {
                seed[key] = .local(offset)
                placeholderId[offset] = key
            }
            // A capped body pass holds unconverged states: claim nothing.
            guard let bodyOut = retransferBody(
                body: body, header: header, headerSeed: seed,
                blockByStart: blockByStart, predecessors: predecessors,
                facts: facts
            ), let backOut = bodyOut[backFrom] else { continue }
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
            // Body snapshots must use the same proven counter identity as the
            // header. Other temporary placeholders must never become names.
            for address in body.sorted() where address != header {
                let preds = predecessors[address] ?? []
                guard !preds.isEmpty, preds.allSatisfy({ body.contains($0) && bodyOut[$0] != nil }) else { continue }
                let entry = Self.meet(preds.compactMap { bodyOut[$0] })
                for (key, value) in entry {
                    if let named = Self.renameInductionFact(value, from: comparedPid, to: displayId) {
                        inState[address, default: [:]][key] = named
                    }
                }
            }
            displayId += 1
            // Loop-carried accumulators / secondary counters: other self-recurrence
            // slots whose per-iteration addend renders in terms of already-named
            // variables (`total += i`, `seen += 1`). Rendered BEFORE the primary
            // increment (accumulate, then advance).
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
                initializations[branchAddr] = names.keys.sorted().compactMap { pid in
                    guard let key = placeholderId[pid], let name = names[pid],
                          case .immediate(let value)? = preLoopEntry[key] else { return nil }
                    return LoopInitialization(name: name, value: value, stackOffset: Self.stackOffset(from: key))
                }
            }
        }
        return (updates, initializations)
    }

    private static func renameInductionFact(_ value: AbstractValue, from: Int, to: Int) -> AbstractValue? {
        var found = false
        func rename(_ value: AbstractValue) -> AbstractValue {
            switch value {
            case .local(let id):
                guard id == from else { return .unknown }
                found = true
                return .local(to)
            case .binary(let op, let lhs, let rhs):
                let l = rename(lhs), r = rename(rhs)
                return l == .unknown || r == .unknown ? .unknown : .binary(op, l, r)
            case .unary(let op, let operand):
                let inner = rename(operand)
                return inner == .unknown ? .unknown : .unary(op, inner)
            case .select(let condition, let yes, let no):
                let c = rename(condition), y = rename(yes), n = rename(no)
                return c == .unknown || y == .unknown || n == .unknown ? .unknown
                    : .select(condition: c, whenTrue: y, whenFalse: n)
            default: return value
            }
        }
        let named = rename(value)
        return found && named != .unknown ? named : nil
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
    /// body predecessors. Returns each body block's exit state, or nil when the
    /// bound is hit before the states settle.
    private func retransferBody(
        body: Set<UInt64>, header: UInt64, headerSeed: State,
        blockByStart: [UInt64: BasicBlock], predecessors: [UInt64: [UInt64]],
        facts: FunctionFacts
    ) -> [UInt64: State]? {
        var outS: [UInt64: State] = [:]
        var escapeMarkers: [UInt64: State] = [:]
        var worklist = [header]
        var queued: Set<UInt64> = [header]
        var iterations = 0
        let cap = (body.count + 1) * loopBodyIterationsPerBlock
        while let addr = worklist.first {
            worklist.removeFirst(); queued.remove(addr)
            iterations += 1
            if iterations > cap {
                Probe.record(.tracerLoopBodyCap, at: header, ["blocks": .int(body.count), "cap": .int(cap)])
                return nil
            }
            guard let block = blockByStart[addr] else { continue }
            var entry: State
            if addr == header {
                entry = headerSeed
            } else {
                let bodyPreds = (predecessors[addr] ?? []).filter { body.contains($0) }
                entry = Self.meet(bodyPreds.compactMap { outS[$0] })
            }
            // Escapes stay once they reach a block (see `analyze`).
            for (key, value) in escapeMarkers[addr] ?? [:] where entry[key] == nil { entry[key] = value }
            escapeMarkers[addr] = entry.filter { Self.isEscapeMarker($0.key) }
            var registers = entry
            for insn in block.instructions {
                transfer(insn, into: &registers, record: nil, recordAccess: nil, facts: facts)
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
            let value = registers[Location(register)] ?? .unknown
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
            guard let flags = registers[Self.flagsKey]
            else { return nil }
            return flagCondition(flags, code: detail.conditionCode, width: registers[Self.flagsWidthKey])
        }
    }

    /// The text of any Swift small string, for two words already known to be
    /// one String (a String parameter or field): the empty string, control
    /// characters and non-ASCII text too, which `decodeSmallString` refuses
    /// because a pair of integers could look like them. The high nibble is
    /// 0xE for ASCII and 0xA for other UTF-8 (the ASCII bit, 62, clear), and
    /// the bytes must agree with it, be valid UTF-8, and leave every byte past
    /// the count zero.
    public static func decodeStringSmallString(lo: UInt64, hi: UInt64) -> String? {
        let discriminator = UInt8(truncatingIfNeeded: hi >> 56)
        let isASCII: Bool
        switch discriminator & 0xF0 {
        case 0xE0: isASCII = true
        case 0xA0: isASCII = false
        default: return nil
        }
        let count = Int(discriminator & 0x0F)
        var bytes: [UInt8] = []
        for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: lo >> shift)) }
        for shift in stride(from: 0, to: 56, by: 8) { bytes.append(UInt8(truncatingIfNeeded: hi >> shift)) }
        let content = Array(bytes.prefix(count))
        guard bytes.dropFirst(count).allSatisfy({ $0 == 0 }),
              content.allSatisfy({ $0 < 0x80 }) == isASCII,
              let text = String(validating: content, as: UTF8.self)
        else { return nil }
        return text
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
        recordSlotStore: ((Int, AbstractValue) -> Void)? = nil,
        recordUnboundedMemoryWrite: (() -> Void)? = nil,
        recordFieldAlias: ((Int, Int) -> Void)? = nil
    ) {
        guard let detail = insn.detail else {
            // Capstone couldn't decode what objdump printed — data in __text, or
            // an unknown encoding. We cannot know what it writes, and keeping
            // stale values would be a lie, so drop everything nameable.
            registers.removeAll()
            recordUnboundedMemoryWrite?()
            return
        }
        if detail.operands.contains(where: { $0.operand.isMemory }),
           !Self.readOnlyMemoryIDs.contains(detail.id.rawValue) {
            if invalidateAsyncMemoryForWrite(detail, into: &registers) {
                recordUnboundedMemoryWrite?()
            }
        }

        // Branches and returns write no general register. (Calls never reach
        // here — `transfer` intercepts them.) This must precede the default,
        // which would otherwise clobber `x0` on `cbz x0, …`.
        if let flow = insn.controlFlow, flow != .sequential { return }

        // Every instruction that writes NZCV invalidates the tracked flags
        // first; the few modelled ones (`cmp`/`cmn`/`tst`, `adds`/`subs`/`ands`)
        // set them again below. A listed set of unmodelled writers missed
        // `ngcs` and `negs`, and a path that returned early out of `adds`
        // left the previous comparison standing, so a later branch read a
        // stale comparison and rendered the wrong condition.
        let incomingFlags = registers[Self.flagsKey]
        let incomingFlagsWidth = registers[Self.flagsWidthKey]
        if detail.updatesFlags || Self.unmodeledFlagWriters.contains(detail.id.rawValue) {
            registers[Self.flagsKey] = nil
            registers[Self.flagsWidthKey] = nil
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
                // A subtraction keeps its operands for a conditional compare
                // to read; a sum folds like any other value.
                registers[Self.flagsKey] = detail.id == AARCH64_INS_SUBS ? .binary(op, lhs, rhs)
                    : .binary(op, lhs, rhs)
                registers[Self.flagsWidthKey] = .immediate(UInt64(dest.widthBits))
            }

        case AARCH64_INS_ALIAS_MVN, AARCH64_INS_ORN:
            // MVN is ORN with a zero first operand. Complement the optionally
            // shifted source before OR, then normalize the destination width.
            let operandCount = detail.id == AARCH64_INS_ALIAS_MVN ? 2 : 3
            guard let dest = destinationRegister(detail), dest.kind == .gpr || dest.kind == .zero,
                  detail.operands.count == operandCount,
                  detail.operands.dropFirst().allSatisfy({ operand in
                      guard let reg = operand.operand.register else { return false }
                      return (reg.kind == .gpr || reg.kind == .zero) && reg.widthBits == dest.widthBits
                  })
            else { clobber(detail, into: &registers); return }
            let inverted = bitwiseComplement(source(detail.operands[operandCount - 1], in: registers))
            let result = detail.id == AARCH64_INS_ALIAS_MVN ? inverted
                : expression(.bitOr, source(detail.operands[1], in: registers), inverted)
            write(dest, result, into: &registers)

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
            var shifted = source(detail.operands[1], in: registers)
            // A 32-bit arithmetic shift shifts in the 32-bit sign: `asr w0,
            // w8, #31` of 0x80000001 is 0xffffffff, not 1.
            if dest.widthBits == 32, op == .arithmeticShiftRight || op == .divide {
                shifted = signExtended(shifted, bits: 32)
            }
            var rhs = source(detail.operands[2], in: registers)
            if op == .divide, dest.widthBits == 32 { rhs = signExtended(rhs, bits: 32) }
            if op == .shiftLeft || op == .shiftRight || op == .arithmeticShiftRight {
                rhs = expression(.bitAnd, rhs, .immediate(UInt64(dest.widthBits - 1)))
            }
            let result = expression(op, shifted, rhs)
            write(dest, result, into: &registers)
            if detail.id == AARCH64_INS_ANDS {
                registers[Self.flagsKey] = constantFlags(.bitAnd, source(detail.operands[1], in: registers),
                                                         source(detail.operands[2], in: registers)) ?? result
                registers[Self.flagsWidthKey] = .immediate(UInt64(dest.widthBits))
            }

        case AARCH64_INS_REV, AARCH64_INS_REV16, AARCH64_INS_REV32, AARCH64_INS_REV64:
            guard let dest = destinationRegister(detail), [32, 64].contains(dest.widthBits),
                  dest.kind == .gpr || dest.kind == .zero, detail.operands.count == 2,
                  let input = detail.operands[1].operand.register,
                  input.kind == .gpr || input.kind == .zero, input.widthBits == dest.widthBits,
                  (detail.id != AARCH64_INS_REV32 && detail.id != AARCH64_INS_REV64) || dest.widthBits == 64
            else { clobber(detail, into: &registers); return }
            let bits = detail.id == AARCH64_INS_REV16 ? 16 : detail.id == AARCH64_INS_REV32 ? 32 : dest.widthBits
            let value = source(detail.operands[1], in: registers)
            let reversed: AbstractValue
            if case .immediate(let value) = value, let result = ByteReversal.apply(value, bits: bits) {
                reversed = .immediate(result)
            } else if value == .unknown || Self.expressionDepth(value) >= 8 {
                reversed = .unknown
            } else { reversed = .unary(.byteSwap(bits: bits), value) }
            write(dest, reversed, into: &registers)

        case AARCH64_INS_EXTR, AARCH64_INS_ROR, AARCH64_INS_ALIAS_ROR:
            // Extract a width-sized window from high:low. The immediate ROR
            // alias supplies the same register for both halves. Register ROR
            // has a different operand shape and fails the immediate guard.
            let rotating = detail.id != AARCH64_INS_EXTR
            let shift: Int64? = rotating
                ? (detail.operands.count == 2 && detail.operands[1].shift.type == AARCH64_SFT_ROR
                    ? Int64(detail.operands[1].shift.amount) : nil)
                : (detail.operands.count == 4 ? detail.operands[3].operand.immediateValue : nil)
            guard let dest = destinationRegister(detail), [32, 64].contains(dest.widthBits),
                  dest.kind == .gpr || dest.kind == .zero,
                  detail.operands.count == (rotating ? 2 : 4),
                  let high = detail.operands[1].operand.register,
                  let low = detail.operands[rotating ? 1 : 2].operand.register,
                  high.widthBits == dest.widthBits, low.widthBits == dest.widthBits,
                  high.kind == .gpr || high.kind == .zero,
                  low.kind == .gpr || low.kind == .zero,
                  let shift,
                  shift >= 0, shift < dest.widthBits
            else { clobber(detail, into: &registers); return }
            // Capstone attaches the alias's rotation to its source operand.
            // Strip that metadata and implement the instruction exactly once.
            let lowValue = source(StructuredOperandInfo(operand: .register(low),
                shift: (AARCH64_SFT_INVALID, 0), extender: AARCH64_EXT_INVALID), in: registers)
            // At zero, the high register contributes no bits. Do not shift by
            // the full width, or let an unknown high half poison the low half.
            if shift == 0 { write(dest, lowValue, into: &registers); return }
            let highValue = source(StructuredOperandInfo(operand: .register(high),
                shift: (AARCH64_SFT_INVALID, 0), extender: AARCH64_EXT_INVALID), in: registers)
            let result = expression(.bitOr,
                expression(.shiftRight, lowValue, .immediate(UInt64(shift))),
                expression(.shiftLeft, highValue, .immediate(UInt64(dest.widthBits) - UInt64(shift))))
            write(dest, result, into: &registers)

        case AARCH64_INS_SMULL, AARCH64_INS_UMULL,
             AARCH64_INS_SMADDL, AARCH64_INS_UMADDL,
             AARCH64_INS_SMSUBL, AARCH64_INS_UMSUBL,
             AARCH64_INS_ALIAS_SMNEGL, AARCH64_INS_ALIAS_UMNEGL:
            let fused = detail.id == AARCH64_INS_SMADDL || detail.id == AARCH64_INS_UMADDL
                || detail.id == AARCH64_INS_SMSUBL || detail.id == AARCH64_INS_UMSUBL
            guard let dest = destinationRegister(detail), dest.widthBits == 64,
                  dest.kind == .gpr || dest.kind == .zero,
                  detail.operands.count == (fused ? 4 : 3),
                  let left = detail.operands[1].operand.register, left.widthBits == 32,
                  let right = detail.operands[2].operand.register, right.widthBits == 32,
                  (left.kind == .gpr || left.kind == .zero), (right.kind == .gpr || right.kind == .zero)
            else { clobber(detail, into: &registers); return }
            let signed = detail.id == AARCH64_INS_SMULL || detail.id == AARCH64_INS_SMADDL
                || detail.id == AARCH64_INS_SMSUBL || detail.id == AARCH64_INS_ALIAS_SMNEGL
            func widened(_ reg: PhysReg) -> AbstractValue {
                let value = source(StructuredOperandInfo(operand: .register(reg),
                    shift: (AARCH64_SFT_INVALID, 0), extender: AARCH64_EXT_INVALID), in: registers)
                return signed ? signExtended(value, bits: 32) : value
            }
            let product = expression(.multiply, widened(left), widened(right))
            let subtracting = detail.id == AARCH64_INS_SMSUBL || detail.id == AARCH64_INS_UMSUBL
                || detail.id == AARCH64_INS_ALIAS_SMNEGL || detail.id == AARCH64_INS_ALIAS_UMNEGL
            let addend: AbstractValue
            if fused {
                guard let reg = detail.operands[3].operand.register, reg.widthBits == 64,
                      reg.kind == .gpr || reg.kind == .zero
                else { clobber(detail, into: &registers); return }
                addend = source(detail.operands[3], in: registers)
            } else { addend = .immediate(0) }
            write(dest, fused || subtracting ? expression(subtracting ? .subtract : .add, addend, product)
                : product, into: &registers)

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

        case AARCH64_INS_SXTB, AARCH64_INS_SXTH, AARCH64_INS_SXTW,
             AARCH64_INS_UXTB, AARCH64_INS_UXTH:
            // Scalar extend aliases extract the low byte/half/word. Extend
            // before write() so a W destination zero-extends the signed word.
            guard let dest = destinationRegister(detail), dest.kind == .gpr,
                  detail.operands.count == 2,
                  let input = detail.operands[1].operand.register, input.kind == .gpr
            else { clobber(detail, into: &registers); return }
            let bits: Int = switch detail.id {
            case AARCH64_INS_SXTB, AARCH64_INS_UXTB: 8
            case AARCH64_INS_SXTH, AARCH64_INS_UXTH: 16
            default: 32
            }
            // Capstone may repeat the alias's extension in operand.extender.
            // Read the register once, then apply the instruction's semantics.
            let value = source(StructuredOperandInfo(operand: .register(input),
                shift: (AARCH64_SFT_INVALID, 0), extender: AARCH64_EXT_INVALID), in: registers)
            let signed = detail.id == AARCH64_INS_SXTB || detail.id == AARCH64_INS_SXTH || detail.id == AARCH64_INS_SXTW
            write(dest, signed ? signExtended(value, bits: bits) : narrowed(value, bits: bits), into: &registers)

        case AARCH64_INS_MOV, AARCH64_INS_MOVZ:
            // Capstone pre-folds MOVZ's shift into the immediate.
            guard let dest = destinationRegister(detail), detail.operands.count >= 2 else {
                clobber(detail, into: &registers); return
            }
            write(dest, source(detail.operands[1], in: registers), into: &registers)

        case AARCH64_INS_DUP:
            // `dup v0.2d, x9` replicates a general register into both vector
            // lanes: the two words the compiler then stores as a pair to fill a
            // buffer with one repeated value. A narrower lane (`dup v0.4s, w0`)
            // repeats inside each word, which is then `w0 | w0 << 32`, not w0.
            guard let dest = destinationRegister(detail), detail.operands.count >= 2,
                  let lane = detail.operands[1].operand.register, lane.kind == .gpr,
                  lane.widthBits == 64, dest.widthBits == 128
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
            // The other 48 bits are the register's own. Reading an untracked
            // register as zero claimed a constant the machine never makes
            // (`movk x0, #1` on an argument rendered `return 1`).
            let kept = expression(.bitAnd, registers[Location(dest)] ?? .unknown, .immediate(~(UInt64(0xffff) << shift)))
            write(dest, expression(.bitOr, kept, .immediate(UInt64(bitPattern: imm) << shift)), into: &registers)

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
                var value = offset.map { Self.stackValue(at: $0, bytes: bytes, in: registers) } ?? .unknown
                if dest.kind == .gpr {
                    switch detail.id {
                    case AARCH64_INS_LDRSB, AARCH64_INS_LDURSB,
                         AARCH64_INS_LDRSH, AARCH64_INS_LDURSH,
                         AARCH64_INS_LDRSW, AARCH64_INS_LDURSW:
                        value = signExtended(value, bits: bytes * 8)
                    default: value = narrowed(value, bits: min(bytes * 8, 64))
                    }
                }
                write(dest, value, into: &registers)
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
                let stored = registers[Self.contextSlotKey(offset)] ?? .unknown
                write(dest, isPointerLoad ? stored : .unknown, into: &registers)
            case .asyncCalleeSlot(let offset):
                // The callee context's first word is the caller's own context;
                // nothing else in it is known here.
                let isPointerLoad = dest.kind == .gpr && dest.widthBits == 64
                write(dest, isPointerLoad && offset == 0 ? (registers[Self.calleeParentKey] ?? .unknown) : .unknown, into: &registers)
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
                        let stored = first.operand.register?.kind == .gpr
                            ? narrowed(value, bits: min(bytes * 8, 64)) : value
                        Self.storeStack(stored, at: offset, bytes: bytes, outgoing: true, into: &registers)
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
                    if (detail.id == AARCH64_INS_STR || detail.id == AARCH64_INS_STUR),
                       Self.isFullWidthGPR(first) {
                        recordSlotStore?(offset, value)
                        if value != .unknown { registers[Self.contextSlotKey(offset)] = value }
                    }
                }
                if case .asyncCalleeSlot(0)? = target,
                   (detail.id == AARCH64_INS_STR || detail.id == AARCH64_INS_STUR),
                   Self.isFullWidthGPR(first) {
                    registers[Self.calleeParentKey] = value == .unknown ? nil : value
                }
                // A full-width store establishes a useful equality: its source
                // register now also holds the current ivar value. Canonicalizing
                // that one register (without rewriting unrelated pointer aliases)
                // lets paths such as
                // `if (enabled) _count += delta; return _count` meet back at the
                // return even though one path performed arithmetic.
                if (detail.id == AARCH64_INS_STR || detail.id == AARCH64_INS_STUR),
                   value != .unknown, !Self.isArgument(value), case .selfField(let offset)? = target,
                   let sourceRegister = first.operand.register {
                    write(sourceRegister, .selfFieldValue(offset: offset), into: &registers)
                    recordFieldAlias?(offset, sourceRegister.widthBits / 8)
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
                    // A constant stays a constant. Renamed to the field it was
                    // stored to, the `movi v0.2d, #0` an initializer zeroes
                    // every field with rendered each later store of it as a
                    // copy of the field before: `self.point = self.other`, a
                    // pair of Doubles from a pair of Ints.
                    if let register = operand.operand.register, !Self.isConstant(source(operand, in: registers)),
                       !Self.isArgument(source(operand, in: registers)) {
                        write(register, .selfFieldValue(offset: offset + index * bytes), into: &registers)
                        recordFieldAlias?(offset + index * bytes, bytes)
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
                      detail.operands.count >= 3,
                      detail.operands.prefix(2).allSatisfy({ Self.isFullWidthGPR($0) }) {
                // `stp x22, x8, [x0]` is how the caller's context and the resume
                // pointer are written into a fresh callee context; the same shape
                // spills two locals into the function's own context.
                for (index, operand) in detail.operands.prefix(2).enumerated() {
                    let value = source(operand, in: registers)
                    registers[Self.contextSlotKey(offset + index * 8)] = value == .unknown ? nil : value
                    recordSlotStore?(offset + index * 8, source(operand, in: registers))
                }
            }
            if case .asyncCalleeSlot(let offset)? = target,
               detail.operands.count >= 3,
               detail.operands.prefix(2).allSatisfy({ Self.isFullWidthGPR($0) }) {
                for (index, operand) in detail.operands.prefix(2).enumerated() where offset + index * 8 == 0 {
                    let value = source(operand, in: registers)
                    registers[Self.calleeParentKey] = value == .unknown ? nil : value
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
                    registers[Self.contextSlotKey(offset + index * 8)] ?? .unknown
                case .asyncCalleeSlot(let offset) where register.kind == .gpr && registerBytes == 8
                    && offset + index * 8 == 0:
                    registers[Self.calleeParentKey] ?? .unknown
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
                case AARCH64_INS_ALIAS_CMP:
                    // Keep the operands: folding the difference loses overflow
                    // and register width before a conditional compare reads it.
                    registers[Self.flagsKey] = .binary(.subtract, lhs, rhs)
                    registers[Self.flagsWidthKey] = .immediate(UInt64(detail.operands[0].operand.register?.widthBits ?? 64))
                case AARCH64_INS_ALIAS_CMN:
                    registers[Self.flagsKey] = .binary(.add, lhs, rhs)
                    registers[Self.flagsWidthKey] = .immediate(UInt64(detail.operands[0].operand.register?.widthBits ?? 64))
                case AARCH64_INS_ALIAS_TST:
                    registers[Self.flagsKey] = constantFlags(.bitAnd, lhs, rhs) ?? expression(.bitAnd, lhs, rhs)
                    registers[Self.flagsWidthKey] = .immediate(UInt64(detail.operands[0].operand.register?.widthBits ?? 64))
                case AARCH64_INS_CCMP:
                    guard detail.operands.count >= 3,
                          let fallback = detail.operands[2].operand.immediateValue, (0..<16).contains(fallback),
                          let incomingFlags,
                          let condition = flagCondition(incomingFlags, code: detail.conditionCode, width: incomingFlagsWidth, requireComplete: true),
                          condition != .unknown, lhs != .unknown, rhs != .unknown
                    else { return }
                    let width = detail.operands[0].operand.register?.widthBits ?? 64
                    let conditions = Self.flagCodes.map { code -> AbstractValue in
                        let compared = subtractionCondition(lhs, rhs, code: code, width: width)
                        let alternate = AbstractValue.immediate(Self.literalFlagCondition(UInt64(fallback), code: code) ? 1 : 0)
                        if case .immediate(let taken) = condition { return taken != 0 ? compared : alternate }
                        guard compared != .unknown, Self.expressionDepth(condition) < 8,
                              Self.expressionDepth(compared) < 8 else { return .unknown }
                        if compared == alternate { return alternate }
                        return .select(condition: condition, whenTrue: compared, whenFalse: alternate)
                    }
                    registers[Self.flagsKey] = .aggregate(conditions)
                default: registers[Self.flagsKey] = nil // CCMN remains declined.
                }
            } else {
                registers[Self.flagsKey] = nil
            }

        case AARCH64_INS_ALIAS_CSET, AARCH64_INS_ALIAS_CSETM:
            // `cset wd, <cc>` materialises the flags as a boolean. Reconstruct the
            // comparison from the recorded flags value and the condition code.
            guard let dest = destinationRegister(detail),
                  let flags = registers[Self.flagsKey],
                  let condition = flagCondition(flags, code: detail.conditionCode, width: registers[Self.flagsWidthKey]),
                  condition != .unknown
            else { clobber(detail, into: &registers); return }
            var result = condition
            if detail.id == AARCH64_INS_ALIAS_CSETM {
                // All ones when the condition holds: `0 - c`, masked to a
                // 32-bit destination. A constant condition folds.
                result = expression(.subtract, .immediate(0), condition)
                if dest.widthBits == 32 { result = expression(.bitAnd, result, .immediate(0xffff_ffff)) }
            }
            write(dest, result, into: &registers)

        case AARCH64_INS_CSEL, AARCH64_INS_CSINC, AARCH64_INS_CSINV, AARCH64_INS_CSNEG:
            // The branchless ternary: `csel d, n, m, cc` = cc ? n : m. The
            // `inc`/`inv`/`neg` variants apply +1 / bitwise-not / negate to the
            // false operand. This is how `-O` lowers a ternary, so it produces the
            // same `.select` a `-Onone` diamond does.
            guard let dest = destinationRegister(detail), detail.operands.count >= 3,
                  let flags = registers[Self.flagsKey],
                  let condition = flagCondition(flags, code: detail.conditionCode, width: registers[Self.flagsWidthKey]),
                  condition != .unknown
            else { clobber(detail, into: &registers); return }
            let whenTrue = source(detail.operands[1], in: registers)
            let falseOperand = source(detail.operands[2], in: registers)
            var whenFalse: AbstractValue = switch detail.id {
            case AARCH64_INS_CSINC: expression(.add, falseOperand, .immediate(1))
            case AARCH64_INS_CSINV:
                if case .immediate(let bits) = falseOperand { .immediate(~bits) }
                else if falseOperand == .unknown { .unknown } else { .unary(.bitwiseNot, falseOperand) }
            case AARCH64_INS_CSNEG:
                if case .immediate(let bits) = falseOperand { .immediate(0 &- bits) }
                else if falseOperand == .unknown { .unknown } else { .unary(.negate, falseOperand) }
            default: falseOperand
            }
            // The arms are what the 32-bit destination holds: `csinc w0, …` of
            // 0xffffffff is 0, not 0x1_0000_0000.
            var whenTrueValue = whenTrue
            if dest.widthBits == 32 {
                if case .immediate(let bits) = whenTrueValue { whenTrueValue = .immediate(bits & 0xffff_ffff) }
                if case .immediate(let bits) = whenFalse { whenFalse = .immediate(bits & 0xffff_ffff) }
            }
            let result: AbstractValue
            if case .immediate(let taken) = condition {
                // A constant condition selects one arm: `(1 ? 11 : 22)` is 11.
                result = taken != 0 ? whenTrueValue : whenFalse
            } else {
                result = (condition == .unknown || whenTrueValue == .unknown || whenFalse == .unknown)
                    ? .unknown
                    : .select(condition: condition, whenTrue: whenTrueValue, whenFalse: whenFalse)
            }
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
            guard let location = Location(key: key), let old = before[location], old != .unknown else { continue }
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
                registers[Location(reg)] = .unknown
                return
            }
        default:
            break
        }
        // Every 32-bit write zero-extends, including symbolic arithmetic whose
        // result can overflow the word. Constants alone missed `mov w0, w0`
        // and `add w0, w0, #1` with an incoming UInt64 argument.
        if reg.kind == .gpr, reg.widthBits == 32 {
            registers[Location(reg)] = narrowed(value, bits: 32)
            return
        }
        registers[Location(reg)] = value
    }

    private func bitwiseComplement(_ value: AbstractValue) -> AbstractValue {
        if case .immediate(let bits) = value { return .immediate(~bits) }
        if case .unary(.bitwiseNot, let inner) = value { return inner }
        guard value != .unknown, Self.expressionDepth(value) < 8 else { return .unknown }
        return .unary(.bitwiseNot, value)
    }

    private func narrowed(_ value: AbstractValue, bits: Int) -> AbstractValue {
        if bits == 64 { return value }
        let mask: UInt64 = bits == 64 ? .max : (1 << bits) - 1
        if case .binary(let op, _, _) = value, op.isComparison { return value }
        if case .binary(.bitAnd, _, .immediate(let existing)) = value, existing & mask == existing { return value }
        return expression(.bitAnd, value, .immediate(mask))
    }

    /// What a scalar view of a vector register holds: `d0` is the low 64 bits
    /// of v0, `s0` the low 32. An `.aggregate` is the whole register as its
    /// eight-byte lanes, so `movi v0.2d, #0; str d0, [sp]` stores lane 0 alone;
    /// stored whole, `printf("%f|%d", 0.0, 1)` rendered the double as `(0, 0)`.
    /// A view narrower than a lane keeps a constant lane's low bits and
    /// declines anything else. Any other value passes through as it was.
    static func scalarView(_ value: AbstractValue, bits: Int) -> AbstractValue {
        guard case .aggregate(let lanes) = value, bits < 128 else { return value }
        guard let low = lanes.first else { return .unknown }
        if bits == 64 { return low }
        guard bits < 64, case .immediate(let word) = low else { return .unknown }
        return .immediate(word & ((1 << UInt64(bits)) - 1))
    }

    private func signExtended(_ value: AbstractValue, bits: Int) -> AbstractValue {
        let shift = UInt64(64 - bits)
        return expression(.arithmeticShiftRight,
                          expression(.shiftLeft, value, .immediate(shift)), .immediate(shift))
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
        if op == .bitAnd, case .immediate(let mask) = rhs {
            if mask == .max { return lhs }
            if case .binary(.bitAnd, let inner, .immediate(let previous)) = lhs {
                return expression(.bitAnd, inner, .immediate(previous & mask))
            }
            if Self.fitsLowMask(lhs, mask: mask) { return lhs }
        }
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

    /// A local range proof keeps width normalization idempotent without
    /// discarding masks on unconstrained arguments or arithmetic results.
    private static func fitsLowMask(_ value: AbstractValue, mask: UInt64) -> Bool {
        switch value {
        case .immediate(let bits): return bits & mask == bits
        case .binary(let op, _, _) where op.isComparison: return mask & 1 == 1
        case .binary(.bitAnd, _, .immediate(let inner)): return inner & mask == inner
        case .binary(let op, let lhs, let rhs) where op == .bitOr || op == .bitXor:
            return fitsLowMask(lhs, mask: mask) && fitsLowMask(rhs, mask: mask)
        case .select(_, let whenTrue, let whenFalse):
            return fitsLowMask(whenTrue, mask: mask) && fitsLowMask(whenFalse, mask: mask)
        default: return false
        }
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
    private static let flagsKey = Location.flags
    private static let flagsWidthKey = Location.flagsWidth

    private static let flagCodes: [AArch64CC_CondCode] = [
        AArch64CC_EQ, AArch64CC_NE, AArch64CC_HS, AArch64CC_LO,
        AArch64CC_MI, AArch64CC_PL, AArch64CC_VS, AArch64CC_VC,
        AArch64CC_HI, AArch64CC_LS, AArch64CC_GE, AArch64CC_LT,
        AArch64CC_GT, AArch64CC_LE,
    ]

    /// Flags from two constant operands, kept unfolded so their NZCV can be
    /// computed exactly; nil when either operand is not a constant.
    private func constantFlags(_ op: AbstractBinaryOperator, _ lhs: AbstractValue, _ rhs: AbstractValue) -> AbstractValue? {
        guard case .immediate = lhs, case .immediate = rhs else { return nil }
        return .binary(op, lhs, rhs)
    }

    /// NZCV of `lhs op rhs` at `width` bits, for constant operands of a
    /// compare (`subtract`), a compare-negative or flag-setting add (`add`),
    /// or a test (`bitAnd`). The carry of an add is its unsigned carry-out
    /// and of a subtract its absence of borrow; a test clears C and V. A
    /// comparison read off the folded value got these wrong: `cmn w8, w9` of
    /// 0 and 0 leaves C clear, so `hs` is false.
    static func constantNZCV(_ flags: AbstractValue, width: Int) -> UInt64? {
        guard case .binary(let op, .immediate(let rawA), .immediate(let rawB)) = flags else { return nil }
        let mask: UInt64 = width == 32 ? 0xffff_ffff : .max
        let sign: UInt64 = width == 32 ? 0x8000_0000 : 0x8000_0000_0000_0000
        let a = rawA & mask, b = rawB & mask
        let result: UInt64, carry: Bool, overflow: Bool
        switch op {
        case .subtract:
            result = (a &- b) & mask
            carry = a >= b
            overflow = (a & sign) != (b & sign) && (result & sign) != (a & sign)
        case .add:
            result = (a &+ b) & mask
            carry = width == 32 ? (a + b) > mask : a.addingReportingOverflow(b).overflow
            overflow = (a & sign) == (b & sign) && (result & sign) != (a & sign)
        case .bitAnd:
            result = a & b
            carry = false
            overflow = false
        default:
            return nil
        }
        return (result & sign != 0 ? 8 : 0) | (result == 0 ? 4 : 0) | (carry ? 2 : 0) | (overflow ? 1 : 0)
    }

    private static func literalFlagCondition(_ flags: UInt64, code: AArch64CC_CondCode) -> Bool {
        let n = flags & 8 != 0, z = flags & 4 != 0, c = flags & 2 != 0, v = flags & 1 != 0
        switch code {
        case AArch64CC_EQ: return z
        case AArch64CC_NE: return !z
        case AArch64CC_HS: return c
        case AArch64CC_LO: return !c
        case AArch64CC_MI: return n
        case AArch64CC_PL: return !n
        case AArch64CC_VS: return v
        case AArch64CC_VC: return !v
        case AArch64CC_HI: return c && !z
        case AArch64CC_LS: return !c || z
        case AArch64CC_GE: return n == v
        case AArch64CC_LT: return n != v
        case AArch64CC_GT: return !z && n == v
        case AArch64CC_LE: return z || n != v
        default: return false
        }
    }

    private func flagCondition(_ flags: AbstractValue, code: AArch64CC_CondCode, width: AbstractValue?, requireComplete: Bool = false) -> AbstractValue? {
        if case .aggregate(let conditions) = flags,
           let index = Self.flagCodes.firstIndex(of: code), index < conditions.count {
            return conditions[index]
        }
        if let nzcv = Self.constantNZCV(flags, width: width == .immediate(32) ? 32 : 64) {
            return .immediate(Self.literalFlagCondition(nzcv, code: code) ? 1 : 0)
        }
        if case .binary(.add, let lhs, let rhs) = flags {
            return additionCondition(lhs, rhs, code: code, width: width == .immediate(32) ? 32 : 64)
        }
        if case .binary(.subtract, let lhs, let rhs) = flags {
            // Constants fold exactly, at the compare's width and with its
            // overflow: `cmp w8, w9` of 0xffffffff and 1 is negative, so
            // `pl` is false, though the 64-bit difference is positive.
            var constants = false
            if case .immediate = lhs, case .immediate = rhs { constants = true }
            if requireComplete || constants {
                return subtractionCondition(lhs, rhs, code: code, width: width == .immediate(32) ? 32 : 64)
            }
            guard let op = Self.comparisonOperator(code) else { return nil }
            return comparisonValue(flags: flags, op)
        }
        if code == AArch64CC_EQ || code == AArch64CC_NE {
            let result = requireComplete && width == .immediate(32) ? expression(.bitAnd, flags, .immediate(0xffff_ffff)) : flags
            return expression(code == AArch64CC_EQ ? .equal : .notEqual, result, .immediate(0))
        }
        // Conditional compares may build on a flag producer only when the
        // particular incoming condition is exact. A sum's sign alone does not
        // prove signed ordering, since its overflow flag also participates.
        guard !requireComplete else { return nil }
        // Other flag producers retain their existing conservative model.
        guard let op = Self.comparisonOperator(code) else { return nil }
        return comparisonValue(flags: flags, op)
    }

    private func additionCondition(_ lhs: AbstractValue, _ rhs: AbstractValue, code: AArch64CC_CondCode, width: Int) -> AbstractValue {
        // N xor V is the sign of the mathematical sum, not its wrapped result.
        // A constant RHS permits the simpler equivalent signed threshold.
        if [AArch64CC_EQ, AArch64CC_NE, AArch64CC_LT, AArch64CC_GE, AArch64CC_GT, AArch64CC_LE].contains(code),
           case .immediate(let bits) = rhs {
            let c = width == 32 ? Int64(Int32(truncatingIfNeeded: bits)) : Int64(bitPattern: bits)
            let minimum = width == 32 ? Int64(Int32.min) : Int64.min
            if c == minimum, code != AArch64CC_EQ, code != AArch64CC_NE {
                return .immediate(code == AArch64CC_LT || code == AArch64CC_LE ? 1 : 0)
            }
            if let op = Self.comparisonOperator(code) {
                let negated = UInt64(0) &- UInt64(bitPattern: c)
                let threshold = width == 32 ? UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: negated))) : negated
                return expression(op, width == 32 ? signExtended(lhs, bits: 32) : lhs,
                                  .immediate(threshold))
            }
        }
        let a = narrowed(lhs, bits: width), b = narrowed(rhs, bits: width)
        let result = narrowed(expression(.add, a, b), bits: width)
        let signMask = UInt64(1) << (width - 1)
        func sign(_ value: AbstractValue) -> AbstractValue {
            expression(.notEqual, expression(.bitAnd, value, .immediate(signMask)), .immediate(0))
        }
        func not(_ value: AbstractValue) -> AbstractValue { expression(.bitXor, value, .immediate(1)) }
        let n = sign(result), z = expression(.equal, result, .immediate(0))
        let carry = expression(.unsignedLess, result, a)
        let overflow = expression(.bitAnd, expression(.equal, sign(a), sign(b)), expression(.notEqual, n, sign(a)))
        let lt = expression(.bitXor, n, overflow)
        switch code {
        case AArch64CC_EQ: return z
        case AArch64CC_NE: return not(z)
        case AArch64CC_HS: return carry
        case AArch64CC_LO: return not(carry)
        case AArch64CC_MI: return n
        case AArch64CC_PL: return not(n)
        case AArch64CC_VS: return overflow
        case AArch64CC_VC: return not(overflow)
        case AArch64CC_HI: return expression(.bitAnd, carry, not(z))
        case AArch64CC_LS: return expression(.bitOr, not(carry), z)
        case AArch64CC_GE: return not(lt)
        case AArch64CC_LT: return lt
        case AArch64CC_GT: return expression(.bitAnd, not(z), not(lt))
        case AArch64CC_LE: return expression(.bitOr, z, lt)
        default: return .unknown
        }
    }

    private func subtractionCondition(_ lhs: AbstractValue, _ rhs: AbstractValue, code: AArch64CC_CondCode, width: Int) -> AbstractValue {
        func unsigned(_ value: AbstractValue) -> AbstractValue {
            width == 32 ? expression(.bitAnd, value, .immediate(0xffff_ffff)) : value
        }
        func signed(_ value: AbstractValue) -> AbstractValue {
            width == 32 ? expression(.arithmeticShiftRight, expression(.shiftLeft, value, .immediate(32)), .immediate(32)) : value
        }
        let a = unsigned(lhs), b = unsigned(rhs)
        if code == AArch64CC_MI || code == AArch64CC_PL {
            let n = expression(.less, signed(expression(.subtract, lhs, rhs)), .immediate(0))
            return code == AArch64CC_MI ? n : expression(.bitXor, n, .immediate(1))
        }
        if code == AArch64CC_VS || code == AArch64CC_VC {
            let leftSign = expression(.less, signed(lhs), .immediate(0))
            let rightSign = expression(.less, signed(rhs), .immediate(0))
            let resultSign = expression(.less, signed(expression(.subtract, lhs, rhs)), .immediate(0))
            let v = expression(.bitAnd, expression(.notEqual, leftSign, rightSign), expression(.notEqual, resultSign, leftSign))
            return code == AArch64CC_VS ? v : expression(.bitXor, v, .immediate(1))
        }
        guard let op = Self.comparisonOperator(code) else { return .unknown }
        return expression(op, op.isUnsignedComparison || op == .equal || op == .notEqual ? a : signed(lhs),
                          op.isUnsignedComparison || op == .equal || op == .notEqual ? b : signed(rhs))
    }

    /// Explicit NZCV writers, including decoder versions that omit the flags
    /// bit. A modelled writer (CCMP) reinstates its new state below; the others
    /// must not leave a stale integer comparison available to a consumer.
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
    /// Signed and unsigned variants remain distinct; overflow and always/never
    /// codes are handled only where an exact flag model is available.
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
        case .binary(.bitAnd, let value, .immediate(0xffff_ffff)):
            // Word normalization adds no computation dependency. Charging it
            // again made bounded 32-bit CCMP overflow predicates exceed the
            // pre-existing arithmetic-depth limit after symbolic W reads.
            return expressionDepth(value)
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
    /// One of the function's own arguments, which no call can change.
    private static func isArgument(_ value: AbstractValue) -> Bool {
        if case .argument = value { return true }
        return false
    }

    /// An immediate, or a vector register's words all immediates.
    private static func isConstant(_ value: AbstractValue) -> Bool {
        switch value {
        case .immediate: return true
        case .aggregate(let words): return !words.isEmpty && words.allSatisfy(isConstant)
        default: return false
        }
    }

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
        guard bytes > 8 else {
            if let width = registers[stackWidthKey(offset)] {
                guard case .immediate(let knownBytes) = width, knownBytes >= bytes else { return .unknown }
            }
            return registers[stackKey(offset)] ?? .unknown
        }
        let words = stride(from: 0, to: bytes, by: 8).map {
            stackValue(at: offset + Int64($0), bytes: min(8, bytes - $0), in: registers)
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
        // A byte/halfword store can overwrite part of an older tracked word.
        // Forget intersecting snapshots rather than retaining their old bits.
        for key in registers.keys {
            guard let previous = stackOffset(from: key) else { continue }
            let width: Int64 = if case .immediate(let bytes)? = registers[stackWidthKey(previous)] {
                Int64(clamping: bytes)
            } else { 8 }
            guard previous < offset + Int64(bytes), offset < previous + width else { continue }
            registers[key] = nil
            registers[stackWidthKey(previous)] = nil
            registers[outgoingKey(previous)] = nil
        }
        let words: [AbstractValue]
        if case .aggregate(let packed) = value, bytes > 8 {
            words = Array(packed.prefix(max(1, (bytes + 7) / 8)))
        } else {
            words = [value]
        }
        for (index, word) in words.enumerated() {
            let wordOffset = offset + Int64(index * 8)
            registers[stackKey(wordOffset)] = word
            registers[stackWidthKey(wordOffset)] = .immediate(UInt64(min(8, bytes - index * 8)))
            if outgoing { registers[outgoingKey(wordOffset)] = word }
        }
    }

    /// The value an operand supplies: a register's tracked value, or a literal.
    private func source(_ operand: StructuredOperandInfo, in registers: State) -> AbstractValue {
        if let shifted = operand.shiftedImmediate { return .immediate(UInt64(bitPattern: shifted)) }
        guard let reg = operand.operand.register else { return .unknown }
        if reg.kind == .zero { return .immediate(0) }
        var value = registers[Location(reg)] ?? .unknown
        if reg.kind == .vector { value = Self.scalarView(value, bits: reg.widthBits) }
        // A 32-bit register is the low word of its 64-bit key. `cmp w8, w9`
        // with x8 = 0x1_0000_0001 compares 1, not the whole value. A known
        // constant is cut exactly, and sign- or zero-extended when the
        // operand says so (`add x0, x1, w2, sxtw`).
        if reg.kind == .gpr, reg.widthBits == 32 {
            switch value {
            case .asyncContext, .asyncCalleeContext, .asyncResumeParent, .indirectResultPointer:
                return .unknown // a truncated opaque pointer is not that pointer
            default: break
            }
            value = narrowed(value, bits: 32)
            switch operand.extender {
            case AARCH64_EXT_SXTW: value = signExtended(value, bits: 32)
            case AARCH64_EXT_SXTH: value = signExtended(value, bits: 16)
            case AARCH64_EXT_SXTB: value = signExtended(value, bits: 8)
            case AARCH64_EXT_UXTH: value = narrowed(value, bits: 16)
            case AARCH64_EXT_UXTB: value = narrowed(value, bits: 8)
            default: break
            }
        }
        switch operand.shift.type {
        case AARCH64_SFT_INVALID: return value
        case AARCH64_SFT_LSL:
            return expression(.shiftLeft, value, .immediate(UInt64(operand.shift.amount)))
        case AARCH64_SFT_LSR, AARCH64_SFT_ASR:
            let op: AbstractBinaryOperator = operand.shift.type == AARCH64_SFT_ASR
                ? .arithmeticShiftRight : .shiftRight
            if op == .arithmeticShiftRight, reg.kind == .gpr, reg.widthBits == 32 {
                value = signExtended(value, bits: 32)
            }
            return expression(op, value, .immediate(UInt64(operand.shift.amount)))
        default:
            return .unknown
        }
    }

    private func destinationRegister(_ detail: StructuredInsn) -> PhysReg? {
        detail.operands.first?.operand.register
    }

    private enum MemoryTarget {
        case stackSlot(Location)
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

    private static let calleeParentKey = Location.calleeParent

    private static func isFullWidthGPR(_ operand: StructuredOperandInfo) -> Bool {
        guard let register = operand.operand.register else { return false }
        return register.widthBits == 64 && (register.kind == .gpr || register.kind == .zero)
    }

    /// Only explicit read-only opcodes prove no memory write; operand access
    /// flags omit effects for atomics and other instructions on this decoder.
    private static let readOnlyMemoryIDs: Set<UInt32> = Set([
        AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDP, AARCH64_INS_LDNP,
        AARCH64_INS_LDPSW, AARCH64_INS_LDRB, AARCH64_INS_LDURB,
        AARCH64_INS_LDRH, AARCH64_INS_LDURH, AARCH64_INS_LDRSB, AARCH64_INS_LDURSB,
        AARCH64_INS_LDRSH, AARCH64_INS_LDURSH, AARCH64_INS_LDRSW, AARCH64_INS_LDURSW,
    ].map(\.rawValue))

    /// Return true when a write may affect any context byte. Only a complete
    /// negative private-frame extent is disjoint under the ordinary frame ABI.
    private func invalidateAsyncMemoryForWrite(_ detail: StructuredInsn, into registers: inout State) -> Bool {
        let target = memoryTarget(detail, in: registers)
        let bytes = Self.accessBytes(detail)
        if case .stackSlot(let key)? = target, let start = Self.stackOffset(from: key),
           let bytes, bytes > 0 {
            let (end, overflow) = start.addingReportingOverflow(Int64(bytes))
            if !overflow, start < 0, end <= 0 { return false }
        }
        if case .asyncSlot(let offset)? = target, let bytes, bytes > 0 {
            // Relative offsets do not establish disjoint allocations. A write
            // through the parent can also reach the child's cached parent word.
            let mayReachCallee = registers[Self.calleeParentKey] != nil
                || registers.values.contains(.asyncCalleeContext)
            registers[Self.calleeParentKey] = nil
            for key in registers.keys {
                guard case .contextSlot(let start) = key else { continue }
                if Self.byteRangesOverlap(start, 8, offset, bytes) { registers[key] = nil }
            }
            return mayReachCallee
        }
        if case .asyncCalleeSlot(let offset)? = target, let bytes, bytes > 0 {
            // The child's extent is unknown: child+32 may be parent+16.
            // Forget the other identity's facts and decline chain-wide claims.
            let mayReachOwn = registers.keys.contains(where: Self.isContextSlot)
            for key in registers.keys where Self.isContextSlot(key) { registers[key] = nil }
            if Self.byteRangesOverlap(0, 8, offset, bytes) { registers[Self.calleeParentKey] = nil }
            return mayReachOwn
        }
        for key in registers.keys where Self.isContextSlot(key) { registers[key] = nil }
        registers[Self.calleeParentKey] = nil
        return true
    }

    private static func byteRangesOverlap(_ a: Int, _ aBytes: Int, _ b: Int, _ bBytes: Int) -> Bool {
        let (aEnd, aOverflow) = a.addingReportingOverflow(aBytes)
        let (bEnd, bOverflow) = b.addingReportingOverflow(bBytes)
        return aOverflow || bOverflow || (a < bEnd && b < aEnd)
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
        switch registers[Location(base)] {
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
        let isPairedLoad = detail.id == AARCH64_INS_LDP || detail.id == AARCH64_INS_LDNP
        recordAccess(insn.address, SelfFieldAccess(
            offset: offset,
            bytes: bytes,
            isWrite: isWrite,
            storedValue: isWrite ? detail.operands.first.map { source($0, in: registers) } : nil,
            storedValues: storedValues,
            registerBytes: isPairedLoad ? bytes / 2 : nil
        ))
    }

    /// Stack slots share the register map, under a key no register can collide with.
    private static func stackKey(_ frameOffset: Int64) -> Location { .stack(frameOffset) }
    private static func stackWidthKey(_ frameOffset: Int64) -> Location { .stackWidth(frameOffset) }

    /// The register-state key for a word of the function's own async context
    /// this funclet stored, by byte offset.
    static func contextSlotKey(_ offset: Int) -> Location { .contextSlot(offset) }
    private static func isContextSlot(_ key: Location) -> Bool {
        if case .contextSlot = key { return true }
        return false
    }

    private static func outgoingKey(_ frameOffset: Int64) -> Location { .outgoing(frameOffset) }
    private static func stackOffset(from key: Location) -> Int64? {
        if case .stack(let offset) = key { return offset }
        return nil
    }

    // MARK: - Escaped frame memory

    /// Frame memory reachable through an escaped address. A frame address
    /// escapes once it leaves what the tracer follows: passed to a call,
    /// stored anywhere but an exactly tracked frame slot, transformed beyond
    /// the tracer's arithmetic, or dropped from a slot or a join while it is
    /// still in memory or a register. From then on any call, and any store
    /// through a pointer of unknown origin, may rewrite what it reaches.
    ///
    /// - `.frameEscaped(k)`: an address at offset k, reaching up to the next
    ///   local whose address the function takes separately
    ///   (`addressTakenFrameOffsets`) or the frame top; from an incoming
    ///   stack argument (k >= 0), upward without bound.
    /// - `.frameBelow(k)`: an address inside a dynamic allocation below k
    ///   (`.frameDynamic(k)`), which reaches nothing at or above k.
    /// - `.frameEscapedAll`: an address of unknown offset; it reaches everything.
    ///
    /// They are MAY facts: `meet` unions them, and they never clear.
    private static let frameEscapeAllKey = Location.frameEscapedAll

    /// The function's own async context reached a place the tracer does not
    /// follow: stored outside a context slot, handed to a call, transformed,
    /// or dropped. From then on any call may rewrite it. The awaited callee's
    /// context has its own marker: a call handed it (`swift_task_dealloc`)
    /// may rewrite that context, whose parent header is all that is known of
    /// it. MAY facts, like the frame markers.
    /// `.contextEscaped(k)`: a pointer to offset k of the own context, which
    /// reaches k and above (an `inout` slot handed to a call); k = 0 is the
    /// whole context.
    private static let calleeContextEscapeKey = Location.calleeContextEscaped

    /// A state key that is the only record of a value in a register, a frame
    /// slot, a context slot or a result-buffer word.
    private static func holdsValue(_ key: Location) -> Bool {
        switch key {
        case .x, .v, .sp, .stack, .contextSlot, .result: true
        default: false
        }
    }

    private static func isEscapeMarker(_ key: Location) -> Bool {
        switch key {
        case .frameEscaped, .frameBelow, .frameEscapedAll, .frameDynamic, .contextEscaped, .calleeContextEscaped: true
        default: false
        }
    }

    private static func contains(_ target: AbstractValue, in value: AbstractValue) -> Bool {
        if value == target { return true }
        switch value {
        case .binary(_, let lhs, let rhs): return contains(target, in: lhs) || contains(target, in: rhs)
        case .unary(_, let operand): return contains(target, in: operand)
        case .select(let condition, let whenTrue, let whenFalse):
            return contains(target, in: condition) || contains(target, in: whenTrue) || contains(target, in: whenFalse)
        case .aggregate(let values): return values.contains { contains(target, in: $0) }
        default: return false
        }
    }

    private static func containsContext(_ value: AbstractValue) -> Bool {
        contains(.asyncContext, in: value) || contains(.asyncCalleeContext, in: value)
    }

    /// A value leaves what the tracer follows: any frame address or async
    /// context pointer in it escapes.
    private static func markEscape(_ value: AbstractValue, into registers: inout State) {
        if contains(.asyncContext, in: value) {
            let offset: Int64 = if case .binary(.add, .asyncContext, .immediate(let k)) = value,
                                   k < UInt64(Int64.max) { Int64(k) } else { 0 }
            registers[.contextEscaped(offset)] = .immediate(1)
        }
        if contains(.asyncCalleeContext, in: value) { registers[calleeContextEscapeKey] = .immediate(1) }
        markFrameEscape(value, into: &registers)
    }

    private static func containsFrame(_ value: AbstractValue) -> Bool {
        switch value {
        case .frame: return true
        case .binary(_, let lhs, let rhs): return containsFrame(lhs) || containsFrame(rhs)
        case .unary(_, let operand): return containsFrame(operand)
        case .select(let condition, let whenTrue, let whenFalse):
            return containsFrame(condition) || containsFrame(whenTrue) || containsFrame(whenFalse)
        case .aggregate(let values): return values.contains(where: containsFrame)
        default: return false
        }
    }

    /// The frame offset a dynamic allocation hangs below: `frame(k) - n` for
    /// a non-constant n, then any offsets within the block.
    private static func allocationBase(_ value: AbstractValue) -> Int64? {
        switch value {
        case .binary(.subtract, .frame(let base), let size):
            if case .immediate = size { return nil }
            return containsFrame(size) ? nil : base
        case .binary(.add, let lhs, let rhs), .binary(.subtract, let lhs, let rhs):
            return containsFrame(rhs) ? nil : allocationBase(lhs)
        default:
            return nil
        }
    }

    private static func markFrameEscape(_ value: AbstractValue, into registers: inout State) {
        guard containsFrame(value) else { return }
        if case .frame(let offset) = value {
            registers[.frameEscaped(offset)] = .immediate(1)
        } else if let base = allocationBase(value), registers[.frameDynamic(base)] != nil {
            registers[.frameBelow(base)] = .immediate(1)
        } else {
            registers[frameEscapeAllKey] = .immediate(1)
        }
    }

    /// Forget every frame fact an escaped address can reach. A forgotten slot
    /// that held a frame address still holds it in memory, so that address
    /// escapes too, until nothing new escapes.
    private static func forgetEscapedFrame(in registers: inout State, addressTaken: [Int64]) {
        var seen = -1
        while true {
            let markers = registers.keys.filter(isEscapeMarker).count
            guard markers != seen else { return }
            seen = markers
            guard let reach = escapedReach(registers, addressTaken: addressTaken) else { return }
            forgetFrame(in: &registers, where: reach)
        }
    }

    /// Whether an escaped address may reach `bytes` at a frame offset; nil
    /// when nothing has escaped.
    private static func escapedReach(_ registers: State, addressTaken: [Int64]) -> ((Int64, Int64) -> Bool)? {
        let everything = registers[frameEscapeAllKey] != nil
        var regions: [(start: Int64, end: Int64)] = []
        for key in registers.keys {
            if case .frameEscaped(let start) = key {
                regions.append((start, start >= 0 ? Int64.max : (addressTaken.first { $0 > start } ?? 0)))
            } else if case .frameBelow(let end) = key {
                regions.append((Int64.min, end))
            }
        }
        guard everything || !regions.isEmpty else { return nil }
        return { offset, bytes in
            everything || regions.contains { $0.start < offset &+ bytes && offset < $0.end }
        }
    }

    /// Forget the frame facts for which `reaches(offset, bytes)` holds. A
    /// forgotten frame address is still in memory: it escapes.
    private static func forgetFrame(in registers: inout State, where reaches: (Int64, Int64) -> Bool) {
        var lost: [AbstractValue] = []
        for key in Array(registers.keys) {
            guard let offset = stackOffset(from: key) else { continue }
            let bytes: Int64 = if case .immediate(let width)? = registers[stackWidthKey(offset)] {
                Int64(clamping: width)
            } else { 8 }
            guard reaches(offset, bytes) else { continue }
            if let value = registers[key] { lost.append(value) }
            registers[key] = nil
            registers[stackWidthKey(offset)] = nil
            registers[outgoingKey(offset)] = nil
        }
        for value in lost { markEscape(value, into: &registers) }
    }

    /// Entry-provenance pointers: computed before this frame existed, so no
    /// store through one reaches it.
    private static func predatesFrame(_ value: AbstractValue?) -> Bool {
        switch value {
        case .argument?, .argumentField?, .selfPointer?, .selfField?, .indirectResultPointer?,
             .indirectResultField?, .asyncContext?, .asyncCalleeContext?:
            return true
        default:
            return false
        }
    }

    /// A memory write's effect on frame facts, before the write is applied.
    /// A frame address stored anywhere but an exactly tracked frame slot
    /// escapes. A write whose frame extent the tracer cannot bound forgets
    /// what it may reach; a write through a pointer of unknown origin forgets
    /// every escaped region. Exact `str`/`stp`-family stores to a frame slot
    /// are left to `apply`, which models them.
    /// Returns whether a register operand read as a value held a frame
    /// address or a context pointer (the caller checks the result kept it).
    private func noteFrameMemoryWrite(
        _ insn: Instruction, into registers: inout State, frame: FrameLayout
    ) -> (frame: Bool, context: Bool) {
        guard let detail = insn.detail else { return (false, false) }
        var memory: (base: PhysReg?, index: PhysReg?, displacement: Int64)?
        for info in detail.operands {
            if case .memory(let base, let index, let displacement) = info.operand {
                memory = (base, index, detail.postIndex ? 0 : displacement)
            }
        }
        // Register operands only: a memory operand's base and index are
        // addresses, carried inside it.
        let valueInputs = detail.operands.compactMap { info -> AbstractValue? in
            guard let register = info.operand.register, register.kind != .zero, info.isRead || info.access == 0
            else { return nil }
            return registers[Location(register)]
        }
        let reads = (frame: valueInputs.contains(where: Self.containsFrame),
                     context: valueInputs.contains(where: Self.containsContext))
        guard let memory, !Self.readOnlyMemoryIDs.contains(detail.id.rawValue) else { return reads }
        let target = memoryTarget(detail, in: registers)
        let modelledSlot: Bool = if case .stackSlot? = target {
            Self.modelledStackStoreIDs.contains(detail.id.rawValue)
        } else { false }
        // A tracked slot keeps a stored frame address in view, unless the
        // slot itself is reachable through an escaped address.
        var tracked = false
        if modelledSlot, case .stackSlot(let key)? = target, let start = Self.stackOffset(from: key) {
            let bytes = Int64(Self.accessBytes(detail) ?? 8)
            tracked = !(Self.escapedReach(registers, addressTaken: frame.boundaries)?(start, bytes) ?? false)
        }
        // A context pointer stored into a context slot by a full-width store
        // stays followed (`.contextSlot`, the callee's parent header): that is how
        // -Onone spills it and how an await links the callee to its parent.
        let contextSlotStore: Bool = switch target {
        case .asyncSlot?, .asyncCalleeSlot?:
            [AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP].contains(detail.id)
                && detail.operands.filter({ $0.operand.register != nil }).allSatisfy(Self.isFullWidthGPR)
        default: false
        }
        if !tracked {
            for value in valueInputs {
                if contextSlotStore { Self.markFrameEscape(value, into: &registers) } else { Self.markEscape(value, into: &registers) }
            }
        }
        switch target {
        case .stackSlot(let key)?:
            guard !modelledSlot, let start = Self.stackOffset(from: key) else { break }
            let bytes = Self.accessBytes(detail).map(Int64.init)
            Self.forgetFrame(in: &registers) { offset, width in
                offset &+ width > start && (bytes.map { offset < start &+ $0 } ?? true)
            }
        case .absolute?, .selfField?, .vtableMethod?, .arrayElement?, .resultSlot?, .asyncSlot?, .asyncCalleeSlot?:
            break
        case nil:
            let base = memory.base.flatMap { registers[Location($0)] }
            let indexed = memory.index != nil
            if let base, Self.containsFrame(base) {
                // Inside a dynamic allocation below k, a write at a constant
                // displacement stays below k plus its extent.
                if !indexed, let allocation = Self.allocationBase(base),
                   registers[.frameDynamic(allocation)] != nil,
                   let bytes = Self.accessBytes(detail) {
                    let limit = allocation &+ max(memory.displacement, 0) &+ Int64(bytes)
                    Self.forgetFrame(in: &registers) { offset, _ in offset < limit }
                } else {
                    Self.forgetFrame(in: &registers) { _, _ in true }
                }
            } else if !(Self.predatesFrame(base) && !indexed) {
                Self.forgetEscapedFrame(in: &registers, addressTaken: frame.boundaries)
            }
        }
        return (false, false)
    }

    /// Whether a call reads nothing from the outgoing stack area: a runtime
    /// entry point of known C arity up to eight, or a non-generic Swift
    /// function whose parameters fit in eight registers. A scalar takes one,
    /// a `String` two, anything else at most four (a larger loadable value
    /// travels by reference).
    private static func passesNoStackArguments(_ callee: String) -> Bool {
        if let arity = DisassembledFunction.knownCArity(of: callee) { return arity <= 8 }
        guard let signature = DisassembledFunction.splitSignature(callee), !signature.isAsync,
              let range = DisassembledFunction.outermostArgumentListRange(of: signature.head),
              !signature.head[..<range.lowerBound].contains("<")
        else { return false }
        let scalars: Set<String> = ["Swift.Int", "Swift.UInt", "Swift.Int64", "Swift.UInt64", "Swift.Int32",
            "Swift.UInt32", "Swift.Int16", "Swift.UInt16", "Swift.Int8", "Swift.UInt8", "Swift.Bool",
            "Swift.Double", "Swift.Float", "Builtin.Word", "Builtin.Int1", "Builtin.Int64", "Builtin.RawPointer"]
        let registers = DisassembledFunction.splitTopLevelArguments(signature.head[range]).reduce(0) { total, parameter in
            var type = parameter.trimmingCharacters(in: .whitespaces)
            if let colon = type.range(of: ": ") { type = String(type[colon.upperBound...]) }
            if type.hasPrefix("inout ") { return total + 1 }
            return total + (scalars.contains(type) ? 1 : type == "Swift.String" ? 2 : 4)
        }
        return registers <= 8
    }

    /// The stores `apply` writes into a frame slot exactly.
    private static let modelledStackStoreIDs: Set<UInt32> = Set([
        AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STRB, AARCH64_INS_STURB,
        AARCH64_INS_STRH, AARCH64_INS_STURH, AARCH64_INS_STP, AARCH64_INS_STNP,
    ].map(\.rawValue))

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
        switch registers[Location(base)] {
        case .frame(let offset): registers[Location(base)] = .frame(offset &+ delta)
        case .address(let address): registers[Location(base)] = .address(address &+ UInt64(bitPattern: delta))
        default: registers[Location(base)] = .unknown
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
