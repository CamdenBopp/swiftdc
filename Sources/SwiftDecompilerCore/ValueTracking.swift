import CCapstone
import Foundation

/// Operators retained in source-level symbolic expressions. These are kept
/// deliberately small and side-effect free: when an instruction falls outside
/// this set, value tracking still degrades to `.unknown` rather than guessing.
public enum AbstractBinaryOperator: Equatable, Sendable {
    case add
    case subtract
    case multiply
    case bitAnd
    case bitOr
    case bitXor
    case shiftLeft
    case shiftRight
    case arithmeticShiftRight

    public var symbol: String {
        switch self {
        case .add: "+"
        case .subtract: "-"
        case .multiply: "*"
        case .bitAnd: "&"
        case .bitOr: "|"
        case .bitXor: "^"
        case .shiftLeft: "<<"
        case .shiftRight, .arithmeticShiftRight: ">>"
        }
    }
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
    /// A pure symbolic expression whose inputs are themselves proven values.
    /// Expression construction is bounded by `ValueTracer.expression` so loops
    /// and long instruction chains cannot create unbounded trees.
    case binary(AbstractBinaryOperator, AbstractValue, AbstractValue)
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
}

/// Register state that metadata proves at a method's entry point.
public enum MethodEntryConvention: Sendable, Equatable {
    /// Swift instance method: `self` is x20.
    case swiftInstance
    /// Objective-C class or instance method: `self` is x0, `_cmd` is x1, and
    /// explicit selector arguments begin in x2.
    case objectiveC(argumentCount: Int)
    /// An Objective-C initializer has the same register convention, but a
    /// metadata-proven `init…` entry lets a super-initializer result become the
    /// method's new `self` for subsequent ivar accesses.
    case objectiveCInitializer(argumentCount: Int)

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
    /// x0 immediately before a return or unconditional branch. The enrichment
    /// pass uses Objective-C return types and resolved tail helpers to decide
    /// which of these are honest source-level returns.
    public var exitValues: [UInt64: AbstractValue] = [:]
    /// Instruction address → the access it makes into `self`.
    public var selfFieldAccesses: [UInt64: SelfFieldAccess] = [:]
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
        case .swiftInstance:
            state["x20"] = .selfPointer
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
        analyze(function, entry: hasSelf ? .swiftInstance : nil)
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

        // Snapshot pass: replay from each block's fixed entry state, recording
        // call arguments and self-field accesses.
        var result = FunctionAnalysis()
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
                if insn.controlFlow == .branch {
                    let site = Self.snapshot(registers)
                    if !site.isEmpty { result.branchSites[insn.address] = site }
                }
                transfer(
                    insn, into: &registers,
                    record: { result.callSites[$0] = $1 },
                    recordAccess: { result.selfFieldAccesses[$0] = $1 },
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
            let outgoingKeys = registers.keys.filter { $0.hasPrefix(Self.outgoingPrefix) }
            for key in outgoingKeys { registers[key] = nil }
            let callee = DisassembledFunction.calleeName(of: insn) ?? ""
            if Self.identityRuntimeCalls.contains(where: callee.hasPrefix) {
                registers["x0"] = incomingX0
            } else if initializerEntry, callee.hasPrefix("objc_msgSendSuper") {
                // `self = [super init…]`: after the assignment, the returned
                // object is the initializer's current self even if the runtime
                // chose a different allocation.
                registers["x0"] = .selfPointer
            } else {
                registers["x0"] = .callResult(insn.address) // return value
            }
            registers[Self.selfFreshKey] = nil
            return
        }
        let hadSelf = registers[Self.selfFreshKey]
        apply(insn, into: &registers, recordAccess: recordAccess)
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
        recordAccess: ((UInt64, SelfFieldAccess) -> Void)? = nil
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
            write(dest, expression(op, lhs, rhs), into: &registers)

        case ARM64_INS_AND, ARM64_INS_ANDS, ARM64_INS_ORR, ARM64_INS_EOR,
             ARM64_INS_MUL, ARM64_INS_LSL, ARM64_INS_LSR, ARM64_INS_ASR:
            guard let dest = destinationRegister(detail), detail.operands.count >= 3 else {
                clobber(detail, into: &registers); return
            }
            let op: AbstractBinaryOperator = switch detail.id {
            case ARM64_INS_AND, ARM64_INS_ANDS: .bitAnd
            case ARM64_INS_ORR: .bitOr
            case ARM64_INS_EOR: .bitXor
            case ARM64_INS_MUL: .multiply
            case ARM64_INS_LSL: .shiftLeft
            case ARM64_INS_LSR: .shiftRight
            case ARM64_INS_ASR: .arithmeticShiftRight
            default: .add // unreachable: the outer case is exhaustive
            }
            write(
                dest,
                expression(op, source(detail.operands[1], in: registers), source(detail.operands[2], in: registers)),
                into: &registers
            )

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
            case .none: write(dest, .unknown, into: &registers)
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
                case .absolute, .none:
                    .unknown
                }
                write(register, value, into: &registers)
            }
            applyWriteback(detail, into: &registers)

        case ARM64_INS_CMP, ARM64_INS_CMN, ARM64_INS_TST, ARM64_INS_CCMP, ARM64_INS_CCMN:
            // Write only NZCV, which isn't tracked. Critically, these must NOT
            // reach the default: Capstone renders `cmp x1, #1` with x1 as its
            // first operand (it is an alias for `subs xzr, x1, #1`), so a
            // destination-clobbering default would destroy x1.
            break

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
            case .bitAnd: left & right
            case .bitOr: left | right
            case .bitXor: left ^ right
            case .shiftLeft: right < 64 ? left &<< right : nil
            case .shiftRight: right < 64 ? left &>> right : nil
            case .arithmeticShiftRight:
                right < 64
                    ? UInt64(bitPattern: Int64(bitPattern: left) >> Int64(right))
                    : nil
            }
            return folded.map(AbstractValue.immediate) ?? .unknown
        }
        if case .immediate(0) = rhs {
            switch op {
            case .add, .subtract, .bitOr, .bitXor, .shiftLeft, .shiftRight,
                 .arithmeticShiftRight:
                return lhs
            case .multiply, .bitAnd: return .immediate(0)
            }
        }
        guard Self.expressionDepth(lhs) < 8, Self.expressionDepth(rhs) < 8 else { return .unknown }
        return .binary(op, lhs, rhs)
    }

    private static func expressionDepth(_ value: AbstractValue) -> Int {
        guard case .binary(_, let lhs, let rhs) = value else { return 0 }
        return 1 + max(expressionDepth(lhs), expressionDepth(rhs))
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
