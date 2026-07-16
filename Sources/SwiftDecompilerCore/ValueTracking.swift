import CCapstone
import Foundation

/// A small abstract-value lattice for intra-block data-flow. Deliberately tiny:
/// enough to recover constants and `adrp`/`add` addresses flowing into calls.
public enum AbstractValue: Equatable, Sendable {
    case unknown
    case immediate(UInt64)
    case address(UInt64)
    /// The return value (x0) of the call at this instruction address — lets a
    /// result flow into a later call's argument as a nested expression.
    case callResult(UInt64)
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
    /// A frame-relative address: the stack pointer on function entry, plus this
    /// (usually negative) offset.
    ///
    /// Keying stack slots off a symbolic frame base rather than a literal `sp`
    /// value is what lets them survive the prologue's `sub sp, sp, #k` and
    /// `stp …, [sp, #-k]!` — after those, the same local is at a different `sp`
    /// offset, but the same frame offset.
    case frame(Int64)
}

/// The values reaching one call, snapshotted just before it executes.
public struct CallSite: Equatable, Sendable {
    /// x0–x7, trailing unknowns trimmed.
    public var arguments: [AbstractValue] = []
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
        arguments.isEmpty && selfValue == .unknown
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
    /// True when the instruction forms the field's ADDRESS rather than loading
    /// it (`add x0, x20, #0x20` -> `&self.breed`).
    public var isAddressOf: Bool = false
}

/// Everything one pass over a function recovers.
public struct FunctionAnalysis: Sendable {
    public var callSites: [UInt64: CallSite] = [:]
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

    /// Entry state: `sp` anchors the frame at offset 0, and — only when the
    /// caller has established that this really is a Swift instance method —
    /// x20 holds `self`.
    private static func initialState(hasSelf: Bool) -> State {
        var state: State = ["sp": .frame(0)]
        if hasSelf { state["x20"] = .selfPointer }
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
            let entry = preds.isEmpty ? Self.initialState(hasSelf: hasSelf) : Self.meet(preds.compactMap { outState[$0] })
            inState[addr] = entry
            var registers = entry
            for insn in block.instructions { transfer(insn, into: &registers, record: nil, recordAccess: nil) }
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
                transfer(
                    insn, into: &registers,
                    record: { result.callSites[$0] = $1 },
                    recordAccess: { result.selfFieldAccesses[$0] = $1 }
                )
            }
        }
        return result
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
        for insn in instructions { transfer(insn, into: &registers, record: nil, recordAccess: nil) }
        return registers
    }


    /// One instruction's effect on the register state. At a call, snapshot the
    /// argument registers (via `record`) then apply AAPCS64 clobbering.
    private func transfer(
        _ insn: Instruction,
        into registers: inout State,
        record: ((UInt64, CallSite) -> Void)?,
        recordAccess: ((UInt64, SelfFieldAccess) -> Void)?
    ) {
        if insn.controlFlow == .call {
            if let record {
                let args = (0...7).map { registers["x\($0)"] ?? .unknown }
                let site = CallSite(
                    arguments: Self.trimTrailingUnknown(args) ?? [],
                    // Only when freshly set for *this* call — see selfFreshKey.
                    selfValue: registers[Self.selfFreshKey] != nil
                        ? (registers["x20"] ?? .unknown) : .unknown,
                    errorValue: registers["x21"] ?? .unknown,
                    indirectResult: registers["x8"] ?? .unknown
                )
                if !site.isEmpty { record(insn.address, site) }
            }
            // AAPCS64: x0–x17 are caller-saved, so a call clobbers them. x18 is
            // reserved, x19–x28 are callee-saved — and preserving those is what
            // carries `self` and locals across a call.
            for index in 1...17 { registers["x\(index)"] = .unknown }
            registers["x30"] = .unknown
            registers["x0"] = .callResult(insn.address) // return value
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
            // `shiftedImmediate` is the fix for `sub sp, sp, #0x2, lsl #12`:
            // reading the immediate alone yields 2 where the real value is 8192.
            guard let delta = detail.operands[2].shiftedImmediate else {
                // A register operand (`add x0, x1, x2`) — not modelled.
                write(dest, .unknown, into: &registers)
                return
            }
            let adding = detail.id == ARM64_INS_ADD || detail.id == ARM64_INS_ADDS
            let magnitude = UInt64(bitPattern: delta)
            switch source(detail.operands[1], in: registers) {
            case .address(let a): write(dest, .address(adding ? a &+ magnitude : a &- magnitude), into: &registers)
            case .immediate(let v): write(dest, .immediate(adding ? v &+ magnitude : v &- magnitude), into: &registers)
            case .frame(let f): write(dest, .frame(adding ? f &+ delta : f &- delta), into: &registers)
            case .selfPointer where adding:
                recordAccess?(insn.address, SelfFieldAccess(offset: Int(delta), bytes: 0, isWrite: false, isAddressOf: true))
                write(dest, .selfField(offset: Int(delta)), into: &registers)
            case .selfField(let base) where adding:
                recordAccess?(insn.address, SelfFieldAccess(offset: base + Int(delta), bytes: 0, isWrite: false, isAddressOf: true))
                write(dest, .selfField(offset: base + Int(delta)), into: &registers)
            case .unknown, .callResult, .loaded, .selfPointer, .selfField:
                write(dest, .unknown, into: &registers)
            }

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

        // Only the full 64-bit forms: a sub-word load can't produce a pointer.
        case ARM64_INS_LDR, ARM64_INS_LDUR:
            guard let dest = destinationRegister(detail) else { clobber(detail, into: &registers); return }
            noteFieldAccess(insn, detail, in: registers, recordAccess)
            let target = memoryTarget(detail, in: registers)
            applyWriteback(detail, into: &registers)
            switch target {
            case .stackSlot(let key): write(dest, registers[key] ?? .unknown, into: &registers)
            case .absolute(let address): write(dest, .loaded(address), into: &registers)
            // The heap contents of a self field are not tracked; the *access*
            // was already recorded for naming, which is what matters.
            case .selfField: write(dest, .unknown, into: &registers)
            case .none: write(dest, .unknown, into: &registers)
            }

        // A store writes memory, not a register — but it populates a stack slot,
        // which is how a value materialised before a branch reaches a call after it.
        case ARM64_INS_STR, ARM64_INS_STUR:
            noteFieldAccess(insn, detail, in: registers, recordAccess)
            if case .stackSlot(let key)? = memoryTarget(detail, in: registers),
               let first = detail.operands.first {
                registers[key] = source(first, in: registers)
            }
            applyWriteback(detail, into: &registers)

        case ARM64_INS_STP, ARM64_INS_STNP:
            noteFieldAccess(insn, detail, in: registers, recordAccess)
            // Stores two registers; writes none. Writeback still applies —
            // `stp x29, x30, [sp, #-0x70]!` is the standard prologue, and missing
            // it desynchronises the frame for every stack slot that follows.
            applyWriteback(detail, into: &registers)

        case ARM64_INS_LDP, ARM64_INS_LDNP:
            // A 16-byte Swift.String field arrives exactly here.
            noteFieldAccess(insn, detail, in: registers, recordAccess)
            for operand in detail.operands.prefix(2) {
                if let reg = operand.operand.register { write(reg, .unknown, into: &registers) }
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

    /// The value an operand supplies: a register's tracked value, or a literal.
    private func source(_ operand: StructuredOperandInfo, in registers: State) -> AbstractValue {
        if let shifted = operand.shiftedImmediate { return .immediate(UInt64(bitPattern: shifted)) }
        guard let reg = operand.operand.register else { return .unknown }
        if reg.kind == .zero { return .immediate(0) }
        // A shifted register operand (`x2, lsl #3`) is not a plain copy.
        guard operand.shift.type == ARM64_SFT_INVALID else { return .unknown }
        return registers[reg.key] ?? .unknown
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
        recordAccess(insn.address, SelfFieldAccess(
            offset: offset,
            bytes: bytes,
            isWrite: Self.storeIDs.contains(detail.id.rawValue)
        ))
    }

    /// Stack slots share the register map, under a key no register can collide with.
    private static func stackKey(_ frameOffset: Int64) -> String { "stack@\(frameOffset)" }

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
