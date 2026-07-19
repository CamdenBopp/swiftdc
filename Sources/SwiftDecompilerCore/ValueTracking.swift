import CCapstone
import Foundation

/// Operators retained in source-level symbolic expressions. These are kept
/// deliberately small and side-effect free: when an instruction falls outside
/// this set, value tracking still degrades to `.unknown` rather than guessing.
public enum AbstractBinaryOperator: Equatable, Sendable {
    case add
    case subtract
    case multiply
    case divide
    case remainder
    case bitAnd
    case bitOr
    case bitXor
    case shiftLeft
    case shiftRight
    case arithmeticShiftRight
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
        case .divide: "/"
        case .remainder: "%"
        case .bitAnd: "&"
        case .bitOr: "|"
        case .bitXor: "^"
        case .shiftLeft: "<<"
        case .shiftRight, .arithmeticShiftRight: ">>"
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
/// `fsqrt`, `fabs`, `mvn`). Like the binary set this stays small and pure; an
/// unmodelled instruction still degrades to `.unknown`.
public enum AbstractUnaryOperator: Equatable, Sendable {
    case negate
    case squareRoot
    case absoluteValue
    case bitwiseNot
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
    case objectiveC(argumentCount: Int)
    /// An Objective-C initializer has the same register convention, but a
    /// metadata-proven `init…` entry lets a super-initializer result become the
    /// method's new `self` for subsequent ivar accesses.
    case objectiveCInitializer(argumentCount: Int)
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

    var isObjectiveCInitializer: Bool {
        if case .objectiveCInitializer = self { return true }
        return false
    }
}

/// The values reaching one call, snapshotted just before it executes.
public struct CallSite: Equatable, Sendable {
    /// x0–x7, trailing unknowns trimmed.
    public var arguments: [AbstractValue] = []
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
        arguments.isEmpty && stackArguments.isEmpty && selfValue == .unknown
            && errorValue == .unknown && indirectResult == .unknown
    }
}

/// A memory access into `self`, for field naming.
public struct SelfFieldAccess: Sendable, Equatable {
    /// Byte offset from the start of the instance.
    public var offset: Int
    /// Access width. Comes from the instruction id and register width —
    /// `arm64_op_mem` carries no width at all.
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
    /// v0 (the d0/s0 floating-point return register) immediately before a
    /// return. A `Double`/`Float`-returning function delivers its result here,
    /// not in x0, so the enrichment pass reads this one for those return types.
    public var exitFloatValues: [UInt64: AbstractValue] = [:]
    /// Instruction address → the access it makes into `self`.
    public var selfFieldAccesses: [UInt64: SelfFieldAccess] = [:]
    /// Array-literal construction site → the values stored into it, by byte
    /// offset. Reconstructs `[e0, e1, …]` from the `_allocateUninitializedArray` +
    /// element-store + `_finalizeUninitializedArray` lowering.
    public var arrayElements: [UInt64: [Int: AbstractValue]] = [:]
}

/// An abstract interpreter over a function's basic blocks. Propagates constants,
/// addresses, frame-relative stack slots, and `self` through registers, and
/// snapshots the argument registers at each call.
public struct ValueTracer: Sendable {
    public init() {}

    /// Register and stack-slot values. Register keys are canonical names
    /// (`x3`, `sp`); stack slots are keyed by frame offset (see `stackKey`), so
    /// both live in one map and flow through the same meet.
    private typealias State = [String: AbstractValue]

    /// Entry state: `sp` anchors the frame at offset 0. Receiver/argument
    /// registers are seeded only when runtime or Swift metadata establishes the
    /// method convention for this exact implementation address.
    private static func initialState(entry: MethodEntryConvention?) -> State {
        var state: State = ["sp": .frame(0)]
        switch entry {
        case .swiftInstance(let scalarArguments):
            state["x20"] = .selfPointer
            // Parameters occupy x0…/v0… independently of the `self` register
            // (x20), so an instance method's scalar arguments are seeded the same
            // way a free function's are.
            for (register, argument) in scalarArguments { state[register] = .argument(argument) }
        case .objectiveC(let argumentCount), .objectiveCInitializer(let argumentCount):
            state["x0"] = .selfPointer
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
            if iterations > cap { break }
            guard let block = blockByStart[addr] else { continue }
            let preds = predecessors[addr] ?? []
            // No predecessors: the entry block (or unreachable code) — start from
            // the frame anchor rather than an empty state.
            let blockEntry = preds.isEmpty
                ? Self.initialState(entry: entry)
                : Self.meet(preds.compactMap { outState[$0] })
            inState[addr] = blockEntry
            var registers = blockEntry
            for insn in block.instructions {
                transfer(
                    insn, into: &registers, record: nil, recordAccess: nil,
                    initializerEntry: entry?.isObjectiveCInitializer == true
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
            blockByStart: blockByStart, inState: &inState, outState: outState
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
                   let value = registers["v0"], value != .unknown {
                    result.exitFloatValues[insn.address] = value
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
                transfer(
                    insn, into: &registers,
                    record: { result.callSites[$0] = $1 },
                    recordAccess: { result.selfFieldAccesses[$0] = $1 },
                    recordArrayElement: { result.arrayElements[$0, default: [:]][$1] = $2 },
                    initializerEntry: entry?.isObjectiveCInitializer == true
                )
            }
        }
        return result
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
        initializerEntry: Bool = false
    ) {
        if insn.controlFlow == .call {
            let site = Self.snapshot(registers)
            if let record {
                if !site.isEmpty { record(insn.address, site) }
            }
            let incomingX0 = registers["x0"] ?? .unknown
            // AAPCS64: x0–x17 are caller-saved, so a call clobbers them. x18 is
            // reserved, x19–x28 are callee-saved — and preserving those is what
            // carries `self` and locals across a call.
            for index in 1...17 { registers["x\(index)"] = .unknown }
            registers["x30"] = .unknown
            // The vector/floating-point bank: v0–v7 and v16–v31 are caller-saved
            // (only the low 64 bits of v8–v15 survive a call). Clobbering them is
            // what stops a stale `d0` from before the call being read as the
            // call's floating-point result after it.
            for index in 0...7 { registers["v\(index)"] = nil }
            for index in 16...31 { registers["v\(index)"] = nil }
            let outgoingKeys = registers.keys.filter { $0.hasPrefix(Self.outgoingPrefix) }
            for key in outgoingKeys { registers[key] = nil }
            let callee = DisassembledFunction.calleeName(of: insn) ?? ""
            if Self.identityRuntimeCalls.contains(where: callee.hasPrefix) {
                registers["x0"] = incomingX0
            } else if callee.contains("_allocateUninitializedArray") {
                // Returns the array in x0 (and its element buffer in x1); the
                // caller fills it next, so tag it with this site and its count —
                // the first argument — so those element stores can be gathered.
                let count: Int = { if case .immediate(let n) = incomingX0 { return Int(n) } else { return -1 } }()
                registers["x0"] = .arrayLiteral(site: insn.address, count: count)
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
            return
        }
        let hadSelf = registers[Self.selfFreshKey]
        apply(insn, into: &registers, recordAccess: recordAccess, recordArrayElement: recordArrayElement)
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
            stackArguments: stackArguments,
            // Only when freshly set for *this* Swift call — see selfFreshKey.
            selfValue: registers[selfFreshKey] != nil
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
        case ARM64_INS_STR, ARM64_INS_STUR, ARM64_INS_STP, ARM64_INS_STNP,
             ARM64_INS_CMP, ARM64_INS_CMN, ARM64_INS_TST, ARM64_INS_CCMP, ARM64_INS_CCMN:
            // These name a register first but read it.
            return false
        case ARM64_INS_LDP, ARM64_INS_LDNP:
            return detail.operands.prefix(2).contains { $0.operand.register?.key == "x20" }
        default:
            return detail.operands.first?.operand.register?.key == "x20"
        }
    }

    /// Meet (∧) of predecessor states: a register keeps its value only when all
    /// predecessors agree; otherwise it becomes unknown (absent).
    private static func meet(_ states: [State]) -> State {
        guard var accumulator = states.first else { return [:] }
        for state in states.dropFirst() {
            accumulator = accumulator.filter { state[$0.key] == $0.value }
        }
        return accumulator
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
        outState: [UInt64: State]
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
                blockByStart: blockByStart, predecessors: predecessors
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
        blockByStart: [UInt64: BasicBlock], predecessors: [UInt64: [UInt64]]
    ) -> [UInt64: State] {
        var outS: [UInt64: State] = [:]
        var worklist = [header]
        var queued: Set<UInt64> = [header]
        var iterations = 0
        let cap = body.count * 8 + 8
        while let addr = worklist.first {
            worklist.removeFirst(); queued.remove(addr)
            iterations += 1
            if iterations > cap { break }
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
                transfer(insn, into: &registers, record: nil, recordAccess: nil)
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
        case ARM64_INS_CBZ:
            return operandValue(0).map { .binary(.equal, $0, .immediate(0)) }
        case ARM64_INS_CBNZ:
            return operandValue(0).map { .binary(.notEqual, $0, .immediate(0)) }
        case ARM64_INS_TBZ, ARM64_INS_TBNZ:
            guard let value = operandValue(0), detail.operands.count >= 2,
                  let bit = detail.operands[1].operand.immediateValue,
                  (0..<64).contains(bit)
            else { return nil }
            let width = detail.operands[0].operand.register.map({ $0.widthBits }) ?? 64
            if bit == width - 1 {
                // Sign bit: tbz taken = non-negative, tbnz taken = negative.
                return .binary(detail.id == ARM64_INS_TBZ ? .greaterEqual : .less,
                               value, .immediate(0))
            }
            // Any other bit is an honest mask test — `(v & (1<<bit)) == 0` for
            // tbz (bit clear taken), `!= 0` for tbnz. This is how a `Bool` (bit 0)
            // condition arrives.
            let masked = AbstractValue.binary(.bitAnd, value, .immediate(1 << bit))
            return .binary(detail.id == ARM64_INS_TBZ ? .equal : .notEqual, masked, .immediate(0))
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
        recordArrayElement: ((UInt64, Int, AbstractValue) -> Void)? = nil
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

        switch detail.id {
        case ARM64_INS_ADRP, ARM64_INS_ADR:
            // Capstone resolves the page/PC-relative target into the immediate.
            guard let dest = destinationRegister(detail),
                  let target = detail.operands.count >= 2 ? detail.operands[1].operand.immediateValue : nil
            else { clobber(detail, into: &registers); return }
            write(dest, .address(UInt64(bitPattern: target)), into: &registers)

        case ARM64_INS_ADD, ARM64_INS_ADDS, ARM64_INS_SUB, ARM64_INS_SUBS:
            guard let dest = destinationRegister(detail), detail.operands.count >= 3 else {
                clobber(detail, into: &registers); return
            }
            let lhs = source(detail.operands[1], in: registers)
            let rhs = source(detail.operands[2], in: registers)
            let op: AbstractBinaryOperator = (detail.id == ARM64_INS_ADD || detail.id == ARM64_INS_ADDS)
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
                default:
                    break
                }
            }
            let result = expression(op, lhs, rhs)
            write(dest, result, into: &registers)
            // The S-variants (`adds`/`subs`) also set NZCV — the compiler emits
            // `subs x8, x8, x0; cset …` for a comparison as readily as `cmp`.
            if detail.id == ARM64_INS_ADDS || detail.id == ARM64_INS_SUBS {
                registers[Self.flagsKey] = result
            }

        case ARM64_INS_AND, ARM64_INS_ANDS, ARM64_INS_ORR, ARM64_INS_EOR,
             ARM64_INS_MUL, ARM64_INS_LSL, ARM64_INS_LSR, ARM64_INS_ASR,
             ARM64_INS_SDIV, ARM64_INS_UDIV:
            guard let dest = destinationRegister(detail), detail.operands.count >= 3 else {
                clobber(detail, into: &registers); return
            }
            let op: AbstractBinaryOperator = switch detail.id {
            case ARM64_INS_AND, ARM64_INS_ANDS: .bitAnd
            case ARM64_INS_ORR: .bitOr
            case ARM64_INS_EOR: .bitXor
            case ARM64_INS_MUL: .multiply
            case ARM64_INS_SDIV, ARM64_INS_UDIV: .divide
            case ARM64_INS_LSL: .shiftLeft
            case ARM64_INS_LSR: .shiftRight
            case ARM64_INS_ASR: .arithmeticShiftRight
            default: .add // unreachable: the outer case is exhaustive
            }
            let result = expression(
                op, source(detail.operands[1], in: registers),
                source(detail.operands[2], in: registers)
            )
            write(dest, result, into: &registers)
            if detail.id == ARM64_INS_ANDS { registers[Self.flagsKey] = result }

        case ARM64_INS_MADD, ARM64_INS_MSUB:
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
            write(dest, expression(detail.id == ARM64_INS_MADD ? .add : .subtract, addend, product),
                  into: &registers)

        case ARM64_INS_FADD, ARM64_INS_FSUB, ARM64_INS_FMUL, ARM64_INS_FDIV, ARM64_INS_FNMUL:
            guard let dest = destinationRegister(detail), detail.operands.count >= 3 else {
                clobber(detail, into: &registers); return
            }
            let op: AbstractBinaryOperator = switch detail.id {
            case ARM64_INS_FADD: .add
            case ARM64_INS_FSUB: .subtract
            case ARM64_INS_FDIV: .divide
            default: .multiply // FMUL, FNMUL
            }
            let product = floatBinary(op, source(detail.operands[1], in: registers),
                                      source(detail.operands[2], in: registers))
            // FNMUL negates the product: `-(a * b)`.
            write(dest, detail.id == ARM64_INS_FNMUL ? floatUnary(.negate, product) : product,
                  into: &registers)

        case ARM64_INS_FNEG, ARM64_INS_FSQRT, ARM64_INS_FABS:
            guard let dest = destinationRegister(detail), detail.operands.count >= 2 else {
                clobber(detail, into: &registers); return
            }
            let op: AbstractUnaryOperator = switch detail.id {
            case ARM64_INS_FSQRT: .squareRoot
            case ARM64_INS_FABS: .absoluteValue
            default: .negate // FNEG
            }
            write(dest, floatUnary(op, source(detail.operands[1], in: registers)), into: &registers)

        case ARM64_INS_FMOV, ARM64_INS_FCVT, ARM64_INS_SCVTF, ARM64_INS_UCVTF,
             ARM64_INS_FCVTZS, ARM64_INS_FCVTZU:
            // A register-to-register FP move or width/int conversion carries the
            // value through unchanged for display.
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

        case ARM64_INS_MOV, ARM64_INS_MOVZ:
            // Capstone pre-folds MOVZ's shift into the immediate.
            guard let dest = destinationRegister(detail), detail.operands.count >= 2 else {
                clobber(detail, into: &registers); return
            }
            write(dest, source(detail.operands[1], in: registers), into: &registers)

        case ARM64_INS_MOVK:
            // MOVK's shift is NOT pre-folded, and it merges into the existing value.
            guard let dest = destinationRegister(detail), detail.operands.count >= 2,
                  let imm = detail.operands[1].operand.immediateValue
            else { clobber(detail, into: &registers); return }
            let shift = detail.operands[1].shift.type == ARM64_SFT_LSL ? UInt64(detail.operands[1].shift.amount) : 0
            let base: UInt64 = { if case .immediate(let v) = registers[dest.key] { return v } else { return 0 } }()
            let mask = ~(UInt64(0xffff) << shift)
            write(dest, .immediate((base & mask) | (UInt64(bitPattern: imm) << shift)), into: &registers)

        case ARM64_INS_LDR, ARM64_INS_LDUR, ARM64_INS_LDRB, ARM64_INS_LDURB,
             ARM64_INS_LDRH, ARM64_INS_LDURH, ARM64_INS_LDRSB, ARM64_INS_LDURSB,
             ARM64_INS_LDRSH, ARM64_INS_LDURSH, ARM64_INS_LDRSW, ARM64_INS_LDURSW:
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
                let isPointerLoad = detail.id == ARM64_INS_LDR || detail.id == ARM64_INS_LDUR
                write(dest, isPointerLoad ? .loaded(address) : .unknown, into: &registers)
            case .selfField(let offset): write(dest, .selfFieldValue(offset: offset), into: &registers)
            case .vtableMethod(let offset):
                // The dispatch loads the vtable slot only through a pointer-width
                // read; a narrower load isn't a method pointer.
                let isPointerLoad = detail.id == ARM64_INS_LDR || detail.id == ARM64_INS_LDUR
                write(dest, isPointerLoad ? .selfVTableMethod(offset: offset) : .unknown, into: &registers)
            case .arrayElement, .none: write(dest, .unknown, into: &registers)
            }

        // A store writes memory, not a register — but it populates a stack slot,
        // which is how a value materialised before a branch reaches a call after it.
        case ARM64_INS_STR, ARM64_INS_STUR, ARM64_INS_STRB, ARM64_INS_STURB,
             ARM64_INS_STRH, ARM64_INS_STURH:
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
                // A full-width store establishes a useful equality: its source
                // register now also holds the current ivar value. Canonicalizing
                // that one register (without rewriting unrelated pointer aliases)
                // lets paths such as
                // `if (enabled) _count += delta; return _count` meet back at the
                // return even though one path performed arithmetic.
                if (detail.id == ARM64_INS_STR || detail.id == ARM64_INS_STUR),
                   value != .unknown, case .selfField(let offset)? = target,
                   let sourceRegister = first.operand.register {
                    write(sourceRegister, .selfFieldValue(offset: offset), into: &registers)
                }
            }
            applyWriteback(detail, into: &registers)

        case ARM64_INS_STP, ARM64_INS_STNP:
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
            }
            // Stores two registers; writes none. Writeback still applies —
            // `stp x29, x30, [sp, #-0x70]!` is the standard prologue, and missing
            // it desynchronises the frame for every stack slot that follows.
            applyWriteback(detail, into: &registers)

        case ARM64_INS_LDP, ARM64_INS_LDNP:
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
                case .absolute, .vtableMethod, .arrayElement, .none:
                    .unknown
                }
                write(register, value, into: &registers)
            }
            applyWriteback(detail, into: &registers)

        case ARM64_INS_CMP, ARM64_INS_CMN, ARM64_INS_TST, ARM64_INS_CCMP, ARM64_INS_CCMN:
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
                case ARM64_INS_CMP: registers[Self.flagsKey] = expression(.subtract, lhs, rhs)
                case ARM64_INS_CMN: registers[Self.flagsKey] = expression(.add, lhs, rhs)
                case ARM64_INS_TST: registers[Self.flagsKey] = expression(.bitAnd, lhs, rhs)
                default: registers[Self.flagsKey] = nil // CCMP/CCMN: conditional
                }
            } else {
                registers[Self.flagsKey] = nil
            }

        case ARM64_INS_CSET, ARM64_INS_CSETM:
            // `cset wd, <cc>` materialises the flags as a boolean. Reconstruct the
            // comparison from the recorded flags value and the condition code.
            guard let dest = destinationRegister(detail),
                  let op = Self.comparisonOperator(detail.conditionCode),
                  let flags = registers[Self.flagsKey]
            else { clobber(detail, into: &registers); return }
            write(dest, comparisonValue(flags: flags, op), into: &registers)

        case ARM64_INS_CSEL, ARM64_INS_CSINC, ARM64_INS_CSINV, ARM64_INS_CSNEG:
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
            case ARM64_INS_CSINC: expression(.add, falseOperand, .immediate(1))
            case ARM64_INS_CSINV: falseOperand == .unknown ? .unknown : .unary(.bitwiseNot, falseOperand)
            case ARM64_INS_CSNEG: falseOperand == .unknown ? .unknown : .unary(.negate, falseOperand)
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
        ARM64_INS_ST1, ARM64_INS_ST1B, ARM64_INS_ST1D, ARM64_INS_ST1H, ARM64_INS_ST1Q,
        ARM64_INS_ST1W, ARM64_INS_ST2, ARM64_INS_ST2B, ARM64_INS_ST2D, ARM64_INS_ST2G,
        ARM64_INS_ST2H, ARM64_INS_ST2W, ARM64_INS_ST3, ARM64_INS_ST3B, ARM64_INS_ST3D,
        ARM64_INS_ST3H, ARM64_INS_ST3W, ARM64_INS_ST4, ARM64_INS_ST4B, ARM64_INS_ST4D,
        ARM64_INS_ST4H, ARM64_INS_ST4W, ARM64_INS_ST64B, ARM64_INS_ST64BV, ARM64_INS_ST64BV0,
        ARM64_INS_STADD, ARM64_INS_STADDB, ARM64_INS_STADDH, ARM64_INS_STADDL,
        ARM64_INS_STADDLB, ARM64_INS_STADDLH, ARM64_INS_STCLR, ARM64_INS_STCLRB,
        ARM64_INS_STCLRH, ARM64_INS_STCLRL, ARM64_INS_STCLRLB, ARM64_INS_STCLRLH,
        ARM64_INS_STEOR, ARM64_INS_STEORB, ARM64_INS_STEORH, ARM64_INS_STEORL,
        ARM64_INS_STEORLB, ARM64_INS_STEORLH, ARM64_INS_STG, ARM64_INS_STGM, ARM64_INS_STGP,
        ARM64_INS_STLLR, ARM64_INS_STLLRB, ARM64_INS_STLLRH, ARM64_INS_STLR, ARM64_INS_STLRB,
        ARM64_INS_STLRH, ARM64_INS_STLUR, ARM64_INS_STLURB, ARM64_INS_STLURH, ARM64_INS_STNP,
        ARM64_INS_STNT1B, ARM64_INS_STNT1D, ARM64_INS_STNT1H, ARM64_INS_STNT1W, ARM64_INS_STP,
        ARM64_INS_STR, ARM64_INS_STRB, ARM64_INS_STRH, ARM64_INS_STSET, ARM64_INS_STSETB,
        ARM64_INS_STSETH, ARM64_INS_STSETL, ARM64_INS_STSETLB, ARM64_INS_STSETLH,
        ARM64_INS_STSMAX, ARM64_INS_STSMAXB, ARM64_INS_STSMAXH, ARM64_INS_STSMAXL,
        ARM64_INS_STSMAXLB, ARM64_INS_STSMAXLH, ARM64_INS_STSMIN, ARM64_INS_STSMINB,
        ARM64_INS_STSMINH, ARM64_INS_STSMINL, ARM64_INS_STSMINLB, ARM64_INS_STSMINLH,
        ARM64_INS_STTR, ARM64_INS_STTRB, ARM64_INS_STTRH, ARM64_INS_STUMAX, ARM64_INS_STUMAXB,
        ARM64_INS_STUMAXH, ARM64_INS_STUMAXL, ARM64_INS_STUMAXLB, ARM64_INS_STUMAXLH,
        ARM64_INS_STUMIN, ARM64_INS_STUMINB, ARM64_INS_STUMINH, ARM64_INS_STUMINL,
        ARM64_INS_STUMINLB, ARM64_INS_STUMINLH, ARM64_INS_STUR, ARM64_INS_STURB,
        ARM64_INS_STURH, ARM64_INS_STZ2G, ARM64_INS_STZG, ARM64_INS_STZGM
    ].map(\.rawValue))

    /// Atomic read-modify-write. The destination is operand **1**, not 0, and
    /// Capstone reports no operand accesses at all for these (`op.access` is 0
    /// on every operand; `cs_regs_access` claims they write nothing). Clobber
    /// every register operand: imprecise, since operand 0 is only read, but
    /// never a lie. 583 sites in CoreLocation's __text.
    private static let atomicReadModifyWrite: Set<UInt32> = Set([
        ARM64_INS_CAS, ARM64_INS_CASA, ARM64_INS_CASAB, ARM64_INS_CASAH, ARM64_INS_CASAL,
        ARM64_INS_CASALB, ARM64_INS_CASALH, ARM64_INS_CASB, ARM64_INS_CASH, ARM64_INS_CASL,
        ARM64_INS_CASLB, ARM64_INS_CASLH, ARM64_INS_CASP, ARM64_INS_CASPA, ARM64_INS_CASPAL,
        ARM64_INS_CASPL, ARM64_INS_LDADD, ARM64_INS_LDADDA, ARM64_INS_LDADDAB,
        ARM64_INS_LDADDAH, ARM64_INS_LDADDAL, ARM64_INS_LDADDALB, ARM64_INS_LDADDALH,
        ARM64_INS_LDADDB, ARM64_INS_LDADDH, ARM64_INS_LDADDL, ARM64_INS_LDADDLB,
        ARM64_INS_LDADDLH, ARM64_INS_LDCLR, ARM64_INS_LDCLRA, ARM64_INS_LDCLRAB,
        ARM64_INS_LDCLRAH, ARM64_INS_LDCLRAL, ARM64_INS_LDCLRALB, ARM64_INS_LDCLRALH,
        ARM64_INS_LDCLRB, ARM64_INS_LDCLRH, ARM64_INS_LDCLRL, ARM64_INS_LDCLRLB,
        ARM64_INS_LDCLRLH, ARM64_INS_LDEOR, ARM64_INS_LDEORA, ARM64_INS_LDEORAB,
        ARM64_INS_LDEORAH, ARM64_INS_LDEORAL, ARM64_INS_LDEORALB, ARM64_INS_LDEORALH,
        ARM64_INS_LDEORB, ARM64_INS_LDEORH, ARM64_INS_LDEORL, ARM64_INS_LDEORLB,
        ARM64_INS_LDEORLH, ARM64_INS_LDSET, ARM64_INS_LDSETA, ARM64_INS_LDSETAB,
        ARM64_INS_LDSETAH, ARM64_INS_LDSETAL, ARM64_INS_LDSETALB, ARM64_INS_LDSETALH,
        ARM64_INS_LDSETB, ARM64_INS_LDSETH, ARM64_INS_LDSETL, ARM64_INS_LDSETLB,
        ARM64_INS_LDSETLH, ARM64_INS_LDSMAX, ARM64_INS_LDSMAXA, ARM64_INS_LDSMAXAB,
        ARM64_INS_LDSMAXAH, ARM64_INS_LDSMAXAL, ARM64_INS_LDSMAXALB, ARM64_INS_LDSMAXALH,
        ARM64_INS_LDSMAXB, ARM64_INS_LDSMAXH, ARM64_INS_LDSMAXL, ARM64_INS_LDSMAXLB,
        ARM64_INS_LDSMAXLH, ARM64_INS_LDSMIN, ARM64_INS_LDSMINA, ARM64_INS_LDSMINAB,
        ARM64_INS_LDSMINAH, ARM64_INS_LDSMINAL, ARM64_INS_LDSMINALB, ARM64_INS_LDSMINALH,
        ARM64_INS_LDSMINB, ARM64_INS_LDSMINH, ARM64_INS_LDSMINL, ARM64_INS_LDSMINLB,
        ARM64_INS_LDSMINLH, ARM64_INS_LDUMAX, ARM64_INS_LDUMAXA, ARM64_INS_LDUMAXAB,
        ARM64_INS_LDUMAXAH, ARM64_INS_LDUMAXAL, ARM64_INS_LDUMAXALB, ARM64_INS_LDUMAXALH,
        ARM64_INS_LDUMAXB, ARM64_INS_LDUMAXH, ARM64_INS_LDUMAXL, ARM64_INS_LDUMAXLB,
        ARM64_INS_LDUMAXLH, ARM64_INS_LDUMIN, ARM64_INS_LDUMINA, ARM64_INS_LDUMINAB,
        ARM64_INS_LDUMINAH, ARM64_INS_LDUMINAL, ARM64_INS_LDUMINALB, ARM64_INS_LDUMINALH,
        ARM64_INS_LDUMINB, ARM64_INS_LDUMINH, ARM64_INS_LDUMINL, ARM64_INS_LDUMINLB,
        ARM64_INS_LDUMINLH, ARM64_INS_SWP, ARM64_INS_SWPA, ARM64_INS_SWPAB, ARM64_INS_SWPAH,
        ARM64_INS_SWPAL, ARM64_INS_SWPALB, ARM64_INS_SWPALH, ARM64_INS_SWPB, ARM64_INS_SWPH,
        ARM64_INS_SWPL, ARM64_INS_SWPLB, ARM64_INS_SWPLH
    ].map(\.rawValue))

    /// Two destinations: operands 0 and 1.
    private static let pairLoads: Set<UInt32> = Set([
        ARM64_INS_LDAXP, ARM64_INS_LDNP, ARM64_INS_LDP, ARM64_INS_LDPSW, ARM64_INS_LDXP
    ].map(\.rawValue))



    private func write(_ reg: PhysReg, _ value: AbstractValue, into registers: inout State) {
        guard reg.kind != .zero else { return }   // writes to xzr are discarded
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
            case .divide: right != 0 ? left / right : nil
            case .remainder: right != 0 ? left % right : nil
            case .bitAnd: left & right
            case .bitOr: left | right
            case .bitXor: left ^ right
            case .shiftLeft: right < 64 ? left &<< right : nil
            case .shiftRight: right < 64 ? left &>> right : nil
            case .arithmeticShiftRight:
                right < 64
                    ? UInt64(bitPattern: Int64(bitPattern: left) >> Int64(right))
                    : nil
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
            case .multiply, .bitAnd: return .immediate(0)
            case .divide, .remainder: return .unknown // by zero — don't simplify
            case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual,
                 .unsignedLess, .unsignedLessEqual, .unsignedGreater, .unsignedGreaterEqual:
                break // a comparison against 0 is meaningful; keep it symbolic
            }
        }
        // `a - (a / b) * b` is `a % b`, the shape the compiler lowers a remainder
        // to (sdiv, then mul + sub or msub). Fold it back to the modulo.
        if op == .subtract,
           case .binary(.multiply, let quotient, let divisor) = rhs,
           case .binary(.divide, let numerator, let denominator) = quotient,
           numerator == lhs, denominator == divisor {
            return .binary(.remainder, lhs, divisor)
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
        ARM64_INS_FCMP, ARM64_INS_FCMPE, ARM64_INS_FCCMP, ARM64_INS_FCCMPE,
        ARM64_INS_CCMP, ARM64_INS_CCMN, ARM64_INS_BICS, ARM64_INS_ADCS,
        ARM64_INS_SBCS,
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
    private static func comparisonOperator(_ cc: arm64_cc) -> AbstractBinaryOperator? {
        if cc == ARM64_CC_EQ { return .equal }
        if cc == ARM64_CC_NE { return .notEqual }
        // Signed ordered (LT/GE/GT/LE) and the sign-flag codes (MI/PL) map to the
        // signed operators; the unsigned ordered codes (LO/HS/HI/LS) map to the
        // unsigned operators — preserving, not merging, the machine's signedness.
        if cc == ARM64_CC_GE || cc == ARM64_CC_PL { return .greaterEqual }
        if cc == ARM64_CC_LT || cc == ARM64_CC_MI { return .less }
        if cc == ARM64_CC_GT { return .greater }
        if cc == ARM64_CC_LE { return .lessEqual }
        if cc == ARM64_CC_HS { return .unsignedGreaterEqual }
        if cc == ARM64_CC_LO { return .unsignedLess }
        if cc == ARM64_CC_HI { return .unsignedGreater }
        if cc == ARM64_CC_LS { return .unsignedLessEqual }
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
        case ARM64_SFT_INVALID: return value
        case ARM64_SFT_LSL:
            return expression(.shiftLeft, value, .immediate(UInt64(operand.shift.amount)))
        case ARM64_SFT_LSR, ARM64_SFT_ASR:
            let op: AbstractBinaryOperator = operand.shift.type == ARM64_SFT_ASR
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
        default: return nil
        }
    }

    /// Access width in bytes.
    ///
    /// `arm64_op_mem` carries no width, so it comes from the instruction id plus
    /// the destination register's width: `ldr w0` reads 4 bytes, `ldr x0` reads
    /// 8, and `ldp x19, x20` reads 16 — which is exactly how a 16-byte
    /// `Swift.String` field is loaded.
    private static func accessBytes(_ detail: StructuredInsn) -> Int? {
        let registerBytes = detail.operands.first?.operand.register.map { $0.widthBits / 8 }
        switch detail.id {
        case ARM64_INS_LDRB, ARM64_INS_LDURB, ARM64_INS_STRB, ARM64_INS_STURB,
             ARM64_INS_LDRSB, ARM64_INS_LDURSB:
            return 1
        case ARM64_INS_LDRH, ARM64_INS_LDURH, ARM64_INS_STRH, ARM64_INS_STURH,
             ARM64_INS_LDRSH, ARM64_INS_LDURSH:
            return 2
        case ARM64_INS_LDRSW, ARM64_INS_LDURSW:
            return 4
        case ARM64_INS_LDR, ARM64_INS_LDUR, ARM64_INS_STR, ARM64_INS_STUR:
            return registerBytes
        case ARM64_INS_LDP, ARM64_INS_LDNP, ARM64_INS_STP, ARM64_INS_STNP:
            return registerBytes.map { $0 * 2 }
        default:
            return nil
        }
    }

    private static let storeIDs: Set<UInt32> = Set([
        ARM64_INS_STR, ARM64_INS_STUR, ARM64_INS_STRB, ARM64_INS_STURB,
        ARM64_INS_STRH, ARM64_INS_STURH, ARM64_INS_STP, ARM64_INS_STNP,
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
            detail.id == ARM64_INS_STP || detail.id == ARM64_INS_STNP {
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
}
