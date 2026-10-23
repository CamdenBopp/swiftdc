import Ccapstone
import Foundation

/// What a call or tail branch to an in-image function does to the caller's
/// callee-saved registers, as that function's body proves it.
struct CalleeEffect: Sendable, Equatable {
    /// Registers the callee leaves holding a value the caller cannot name.
    var clobbers: Set<String> = []
    /// Registers the callee reloads from the caller's frame: the eight bytes
    /// at the stack pointer of the call (or tail branch) plus this offset.
    /// LLVM's machine outliner moves an epilogue (`ldp x20, x19, [sp, #0x20];
    /// …; b objc_release`) into a fragment its functions tail-branch to; the
    /// fragment never saves x19, yet it hands back what the function saved.
    var restores: [String: Int64] = [:]
    /// The callee may use the caller's x29 as a pointer: it reads x29 before
    /// writing it, other than to save it on its own stack. Whatever the
    /// caller's x29 points at, its frame, the callee can then write.
    var readsFramePointer = false
}

/// What an in-image function's own body proves about the registers a call to
/// it uses, for callees no signature describes.
///
/// A call snapshotted x0–x7 positionally, so a register the callee never reads
/// rendered as an argument: clang -O0 `printf(…); return bump();` with
/// `long bump(void)` showed `bump(printf(…))`. And the value tracer kept
/// x19–x29 across every call, as AAPCS64 promises. LLVM's machine outliner
/// (`-Osize` Swift, `-Oz` C) breaks both: an `OUTLINED_FUNCTION_n` fragment is
/// reached by `bl` but takes inputs in any register and writes callee-saved
/// ones (`add x20, sp, #8; b Hasher._finalize` rewrites `self`). On an -Osize
/// build of the Reconstruction fixture, `ReconError.hashValue` rendered
/// `OUTLINED_FUNCTION_9(OUTLINED_FUNCTION_35(Swift.Hasher._combine(0)))`:
/// `_combine` returns nothing, and neither fragment takes an argument. The
/// fragments are local symbols, so a stripped binary has no name to go by;
/// the body is the evidence.
struct CalleeRegisterSummary: Sendable, Equatable {
    /// A call whose reads depend on its target's summary.
    struct PendingRead: Sendable, Equatable {
        let target: UInt64
        /// Bit n set when xn may still hold the body's incoming value there,
        /// for x0-x7 and x29.
        let unwritten: UInt32
    }

    /// Argument registers x0…x7 (by number) the body may read before writing
    /// them on some path from its entry. A call or tail call inside counts as
    /// reading every one not yet written, since it may pass them on, unless
    /// its target's own reads are known: a callee of known arity reads its
    /// parameters, and a call to another in-image function waits in
    /// `pendingReads` until `closeOverReads` gives it that function's reads.
    let argumentReads: Set<Int>
    /// Calls and tail branches to other in-image functions, with the argument
    /// registers (bit n for xn) the body has not written at them on some
    /// path: the call reads those of them its target reads.
    var pendingReads: [PendingRead] = []
    /// The body may use the caller's x29 as a pointer (`CalleeEffect`): it
    /// reads x29 before writing it, other than as the value a store to its
    /// own stack saves, directly or through a call to an in-image function
    /// that does (`closeOverReads`).
    var readsFramePointer = false
    /// The same for x22, the async context register: the body may write the
    /// context the caller holds there.
    var readsContextRegister = false
    /// Callee-saved registers (`x19`…`x29`) the body writes and does not
    /// provably hand back: at some exit (a `ret` or a tail branch out) the
    /// register does not hold its entry value. Anything unproven counts as
    /// clobbered.
    let clobberedCalleeSaved: Set<String>
    /// The clobbered registers the body never stores to memory: changed and
    /// not saved anywhere (an outlined fragment writing x19). Only these
    /// carry through calls. A register the body saves but whose save slot
    /// the analysis cannot prove intact (a frame address passed to a callee)
    /// is clobbered for its direct callers, as before, and goes no further:
    /// carried up the call graph, that caution cost thousands of correct
    /// lines on real apps. x21 is left out too: it is Swift's error
    /// register, which every throwing function changes, and each call site
    /// models it already (`callPreservesX21`); carried through callers it
    /// made a later store through x21 look like a store into their saves.
    var definitelyClobbered: Set<String> = []
    /// Of the definitely clobbered registers, those that hold at every exit
    /// the eight bytes at entry sp + k, read before the body could have
    /// written there: an outlined epilogue reloading what its caller saved.
    var restoredFrom: [String: Int64] = [:]
    /// The other functions this body calls or tail-branches to directly, in
    /// address order: the ones whose clobbers can reach through it.
    var callees: [UInt64] = []

    /// What a call to this function does to its caller's callee-saved
    /// registers, as far as it carries beyond the direct callers.
    var effect: CalleeEffect {
        CalleeEffect(clobbers: definitelyClobbered.subtracting(restoredFrom.keys), restores: restoredFrom,
                     readsFramePointer: readsFramePointer)
    }

    /// The integer arguments a call to this function can pass: through the
    /// highest argument register it reads. Unread registers below that are
    /// positional parameters it ignores.
    var argumentCount: Int { (argumentReads.max() ?? -1) + 1 }

    private static let argumentKeys = (0...7).map { "x\($0)" }
    private static let framePointerBit: UInt32 = 1 << 29
    private static let contextRegisterBit: UInt32 = 1 << 22
    private static let calleeSavedKeys = Set((19...29).map { "x\($0)" })

    /// Nil when any instruction lacks structured detail: nothing is claimed
    /// about a body that was not fully decoded.
    ///
    /// `calleeEffects` names, for another function's start, the callee-saved
    /// registers it definitely changes and those it reloads from its caller's
    /// frame. A call to it leaves them changed, and a tail branch to it hands
    /// them to the caller changed: a body that never writes x19 itself still
    /// clobbers it through `bl clobber` or `b clobber`, and one whose
    /// epilogue is an outlined fragment still restores what it saved.
    ///
    /// `calleeArity` gives, for a call target, how many argument registers it
    /// takes when that is known (`DisassembledFunction.knownCArity`). A call to
    /// it reads only those. A call to a target `isFunction` names waits in
    /// `pendingReads`; any other call may read every argument register.
    static func of(
        _ function: DisassembledFunction, calleeEffects: (UInt64) -> CalleeEffect = { _ in CalleeEffect() },
        calleeArity: (UInt64) -> Int? = { _ in nil },
        isFunction: (UInt64) -> Bool = { _ in false }
    ) -> CalleeRegisterSummary? {
        let instructions = function.instructions
        guard !instructions.isEmpty, instructions.allSatisfy({ $0.detail != nil }) else { return nil }
        let addresses = Set(instructions.map(\.address))
        let blocks = function.basicBlocks()
        guard let entry = blocks.first?.startAddress else { return nil }
        let blockAt = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })

        // Forward must-analysis: the argument registers written on every path
        // into a block (intersection at joins). A read of one not in the set is
        // a possible argument read.
        var inState: [UInt64: Set<String>] = [entry: []]
        var reads = Set<Int>()
        var readsFramePointer = false
        var readsContextRegister = false
        // By call address: a block revisited with fewer registers written
        // widens the mask, as it widens `reads`.
        var pending: [UInt64: PendingRead] = [:]
        var worklist = [entry]
        var visits = 0
        while let start = worklist.popLast() {
            visits += 1
            // A pathological CFG must not hang the summary; giving up claims
            // nothing (every caller keeps its positional arguments).
            guard visits <= 64 * max(blocks.count, 1) else {
                Probe.record(.summaryCap, at: function.startAddress, ["pass": .label("argument-reads")])
                return nil
            }
            guard let block = blockAt[start] else { return nil }
            var written = inState[start] ?? []
            for insn in block.instructions {
                guard let detail = insn.detail else { return nil }
                func read(_ key: String) {
                    if let index = argumentKeys.firstIndex(of: key), !written.contains(key) { reads.insert(index) }
                }
                if !written.contains("x29"), Self.uses("x29", in: detail) { readsFramePointer = true }
                if !written.contains("x22"), Self.uses("x22", in: detail) { readsContextRegister = true }
                let internalBranch = insn.branchTarget.map(addresses.contains) == true
                let leavesThroughCall = insn.controlFlow == .call
                    || (insn.controlFlow == .branch && !internalBranch && block.switchCases == nil)
                if leavesThroughCall {
                    // The callee may read any argument register still holding
                    // this function's incoming value, or only its parameters:
                    // a metadata accessor whose one call is `objc_opt_self`
                    // of an address it loads reads no argument, and its
                    // callers printed x1-x3 as arguments to it.
                    if let target = insn.branchTarget, calleeArity(target) == nil, isFunction(target) {
                        var unwritten = pending[insn.address]?.unwritten ?? 0
                        for (index, key) in argumentKeys.enumerated() where !written.contains(key) {
                            unwritten |= 1 << index
                        }
                        if !written.contains("x29") { unwritten |= Self.framePointerBit }
                        if !written.contains("x22") { unwritten |= Self.contextRegisterBit }
                        pending[insn.address] = PendingRead(target: target, unwritten: unwritten)
                    } else {
                        let arity = insn.branchTarget.flatMap(calleeArity) ?? argumentKeys.count
                        argumentKeys.prefix(arity).forEach(read)
                    }
                }
                // Operands without access flags are counted as read, so a gap
                // in Capstone's tables cannot hide an argument.
                for info in detail.operands {
                    if case .register(let register) = info.operand, register.kind == .gpr,
                       info.access == 0 || info.isRead {
                        read(register.key)
                    }
                }
                detail.readRegisterKeys.forEach(read)
                written.formUnion(detail.writtenRegisterKeys.intersection(argumentKeys + ["x29", "x22"]))
                if insn.controlFlow == .call { written.formUnion(argumentKeys) }
            }
            for successor in block.successors where addresses.contains(successor) {
                let merged = inState[successor].map { $0.intersection(written) } ?? written
                if merged != inState[successor] {
                    inState[successor] = merged
                    worklist.append(successor)
                }
            }
        }

        var writtenCalleeSaved = Set<String>()
        var storedCalleeSaved = Set<String>()
        var callees = Set<UInt64>()
        for insn in instructions {
            guard let detail = insn.detail else { return nil }
            writtenCalleeSaved.formUnion(detail.writtenRegisterKeys.intersection(calleeSavedKeys))
            if detail.operands.contains(where: { if case .memory = $0.operand { $0.isWritten } else { false } }) {
                for info in detail.operands where info.isRead {
                    if case .register(let register) = info.operand, register.kind == .gpr,
                       calleeSavedKeys.contains(register.key) {
                        storedCalleeSaved.insert(register.key)
                    }
                }
            }
            if insn.controlFlow == .call || insn.controlFlow == .branch,
               let target = insn.branchTarget, !addresses.contains(target) {
                callees.insert(target)
                let effect = calleeEffects(target)
                writtenCalleeSaved.formUnion(effect.clobbers)
                writtenCalleeSaved.formUnion(effect.restores.keys)
            }
        }
        func external(_ insn: Instruction) -> UInt64? {
            guard let target = insn.branchTarget, !addresses.contains(target) else { return nil }
            return target
        }
        var clobbered = Set<String>()
        var restoredFrom: [String: Int64] = [:]
        if !writtenCalleeSaved.isEmpty {
            let exits = Preservation.exitValues(
                blocks: blocks, entry: entry, addresses: addresses,
                callEffect: { insn in insn.controlFlow == .call ? external(insn).map(calleeEffects) ?? CalleeEffect() : CalleeEffect() },
                exitEffect: { insn in insn.controlFlow == .branch ? external(insn).map(calleeEffects) ?? CalleeEffect() : CalleeEffect() },
                // A callee's definite clobber is an unknown value, not a frame
                // address: read as one, a later store through it unproved
                // every save the caller made, and a method one call up lost
                // `self` across a call it never passed self to.
                clobbersMayAliasStack: false)
            if let exits {
                for values in exits.values {
                    clobbered.formUnion(writtenCalleeSaved.filter { values[$0] != .entry($0) })
                }
                // A reload holds only if every exit reloads the same slot.
                for key in clobbered {
                    let offsets = Set(exits.values.map { values -> Int64? in
                        if case .incoming(let offset)? = values[key] { offset } else { nil }
                    })
                    if offsets.count == 1, let offset = offsets.first ?? nil { restoredFrom[key] = offset }
                }
            } else {
                clobbered = writtenCalleeSaved
            }
        }
        let definitelyClobbered = clobbered.subtracting(storedCalleeSaved).subtracting(["x21"])
        return CalleeRegisterSummary(
            argumentReads: reads,
            pendingReads: pending.keys.sorted().compactMap { pending[$0] },
            readsFramePointer: readsFramePointer,
            readsContextRegister: readsContextRegister,
            clobberedCalleeSaved: clobbered,
            definitelyClobbered: definitelyClobbered,
            restoredFrom: restoredFrom.filter { definitelyClobbered.contains($0.key) },
            callees: callees.sorted())
    }

    /// A summary that claims nothing about callee-saved registers.
    private func claimingNothing() -> CalleeRegisterSummary {
        CalleeRegisterSummary(
            argumentReads: argumentReads, pendingReads: pendingReads, readsFramePointer: readsFramePointer,
            readsContextRegister: readsContextRegister, clobberedCalleeSaved: Self.calleeSavedKeys,
            definitelyClobbered: Self.calleeSavedKeys, callees: callees)
    }

    /// Carries argument reads through calls to in-image functions: each
    /// pending call reads the registers its target reads, among those the
    /// body had not written there. A target with no summary reads every one.
    /// This is the least fixpoint, from each body's own reads up, so a
    /// register counts only through a finite chain of calls that reads it,
    /// which every real read is. Reads only grow, eight registers a
    /// function, so the iteration ends without a cap; the pending calls are
    /// then resolved and dropped.
    ///
    /// A helper whose body calls another in-image function counted as
    /// reading every unwritten register, and its callers passed it whatever
    /// those held: a Terminal helper reached x4 and x5 only through such a
    /// call, and a caller rendered it with two of its own arguments.
    static func closeOverReads(_ summaries: inout [UInt64: CalleeRegisterSummary]) {
        let starts = summaries.keys.sorted()
        var callers: [UInt64: [UInt64]] = [:]
        for start in starts {
            for target in Set((summaries[start]?.pendingReads ?? []).map(\.target)).sorted() {
                callers[target, default: []].append(start)
            }
        }
        var worklist = starts.filter { summaries[$0]?.pendingReads.isEmpty == false }
        var queued = Set(worklist)
        var next = 0
        while next < worklist.count {
            let start = worklist[next]
            next += 1
            queued.remove(start)
            guard let summary = summaries[start] else { continue }
            var reads = summary.argumentReads
            var readsFramePointer = summary.readsFramePointer
            var readsContextRegister = summary.readsContextRegister
            for call in summary.pendingReads {
                let targetReads = summaries[call.target]?.argumentReads ?? Set(0 ..< argumentKeys.count)
                for index in targetReads where call.unwritten & (1 << index) != 0 { reads.insert(index) }
                if call.unwritten & framePointerBit != 0, summaries[call.target]?.readsFramePointer ?? true {
                    readsFramePointer = true
                }
                if call.unwritten & contextRegisterBit != 0, summaries[call.target]?.readsContextRegister ?? true {
                    readsContextRegister = true
                }
            }
            guard reads != summary.argumentReads || readsFramePointer != summary.readsFramePointer
                || readsContextRegister != summary.readsContextRegister
            else { continue }
            summaries[start] = summary.replacingReads(
                reads, readsFramePointer: readsFramePointer, readsContextRegister: readsContextRegister)
            for caller in callers[start] ?? [] where queued.insert(caller).inserted {
                worklist.append(caller)
            }
        }
        for start in starts { summaries[start]?.pendingReads = [] }
    }

    private func replacingReads(
        _ reads: Set<Int>, readsFramePointer: Bool, readsContextRegister: Bool
    ) -> CalleeRegisterSummary {
        CalleeRegisterSummary(
            argumentReads: reads, pendingReads: pendingReads, readsFramePointer: readsFramePointer,
            readsContextRegister: readsContextRegister, clobberedCalleeSaved: clobberedCalleeSaved,
            definitelyClobbered: definitelyClobbered, restoredFrom: restoredFrom, callees: callees)
    }

    /// Whether an instruction uses a callee-saved register (`key`, x29 or
    /// x22) as a value: as a memory base, or read by anything but a store of
    /// it to a stack-pointer address (the save a prologue makes, `stp x29,
    /// x30, [sp, #-16]!`).
    static func uses(_ key: String, in detail: StructuredInsn) -> Bool {
        let operands = detail.operands
        var memoryBase: String?
        for info in operands {
            if case .memory(let base?, let index, _) = info.operand {
                if base.key == key || index?.key == key { return true }
                memoryBase = base.key
            }
        }
        let readsIt = operands.contains { info in
            if case .register(let register) = info.operand, register.key == key { return info.access == 0 || info.isRead }
            return false
        } || detail.readRegisterKeys.contains(key)
        guard readsIt else { return false }
        let isStore = operands.contains { $0.operand.isMemory && $0.isWritten }
        return !(isStore && memoryBase == "sp")
    }

    /// Carries callee effects through calls: a function whose callees change
    /// a register may not hand it back either, and one whose epilogue is an
    /// outlined fragment gets back what that fragment reloads. Each summary
    /// whose callees change anything is rebuilt from their current effects
    /// (`recompute`), and its callers again whenever its own effect changes,
    /// until nothing changes. Every summary is then built from its callees'
    /// final effects, which is what makes it sound: by induction over a
    /// returning call's depth, each callee keeps the effect its caller
    /// assumed. A rebuild replaces the summary rather than merging with it,
    /// since a first summary built before its callees' effects were known is
    /// not a claim to keep: merged in, a function that writes x19 itself
    /// kept that clobber after its outlined epilogue was seen to reload it.
    ///
    /// A run still changing at the cap claims nothing for the functions
    /// waiting to be rebuilt and for every function that calls one of them,
    /// directly or not: those were built on effects that are now stale.
    static func closeOverCalls(
        _ summaries: inout [UInt64: CalleeRegisterSummary],
        cap fixedCap: Int? = nil,
        recompute: (UInt64, (UInt64) -> CalleeEffect) -> CalleeRegisterSummary?
    ) {
        var callers: [UInt64: [UInt64]] = [:]
        for start in summaries.keys.sorted() {
            for callee in summaries[start]?.callees ?? [] where summaries[callee] != nil {
                callers[callee, default: []].append(start)
            }
        }
        var worklist = summaries.keys.sorted().filter { start in
            summaries[start]?.callees.contains {
                summaries[$0]?.definitelyClobbered.isEmpty == false || summaries[$0]?.readsFramePointer == true
            } == true
        }
        var queued = Set(worklist)
        var rounds = 0
        // A run that settles rebuilds each function a few times at most; the
        // cap stops only one whose effects keep feeding each other (a cycle).
        let edges = callers.values.reduce(0) { $0 + $1.count }
        let cap = fixedCap ?? (summaries.count + (2 * calleeSavedKeys.count + 1) * edges + 64)
        while !worklist.isEmpty {
            let start = worklist.removeFirst()
            queued.remove(start)
            rounds += 1
            guard rounds <= cap else {
                Probe.record(.summaryCap, at: start, ["pass": .label("call-clobbers")])
                var unsettled = Set([start] + worklist)
                var pending = unsettled.sorted()
                while let next = pending.popLast() {
                    for caller in callers[next] ?? [] where unsettled.insert(caller).inserted {
                        pending.append(caller)
                    }
                }
                for function in unsettled.sorted() {
                    summaries[function] = summaries[function]?.claimingNothing()
                }
                return
            }
            guard let old = summaries[start] else { continue }
            // A body that cannot be summarised again claims nothing, rather
            // than keeping a summary built before its callees were known.
            let rebuilt = recompute(start, { summaries[$0]?.effect ?? CalleeEffect() }) ?? old.claimingNothing()
            let new = CalleeRegisterSummary(
                argumentReads: old.argumentReads,
                pendingReads: old.pendingReads,
                readsFramePointer: old.readsFramePointer,
                readsContextRegister: old.readsContextRegister,
                clobberedCalleeSaved: rebuilt.clobberedCalleeSaved,
                definitelyClobbered: rebuilt.definitelyClobbered,
                restoredFrom: rebuilt.restoredFrom,
                callees: old.callees)
            guard new != old else { continue }
            summaries[start] = new
            guard new.effect != old.effect else { continue }
            for caller in callers[start] ?? [] where !queued.contains(caller) {
                worklist.append(caller)
                queued.insert(caller)
            }
        }
    }
}

/// Which callee-saved registers a body hands back with their entry values.
///
/// Being stored somewhere is not being preserved: a function can spill x19,
/// overwrite it and never reload it. Over the CFG, each general register and
/// each 8-byte stack slot holds an abstract value: some register's entry
/// value, an address `entry sp + k`, or unknown. Moves copy values; `add`/`sub`
/// of an immediate move addresses; stores and loads through a known stack
/// address (pre- and post-index included) save and reload them; anything else
/// a register is written with is unknown. A load from entry sp or above that
/// no write since entry can have reached reads the caller's own bytes,
/// `incoming(k)`: what an outlined epilogue reloads. At every exit, a `ret`
/// or a tail branch out, a register holding anything but its own entry value
/// is not preserved. Joins keep only what every path agrees on, and an
/// unfinished fixpoint gives up on every written register.
enum Preservation {
    enum Value: Hashable {
        case entry(String)
        case stack(Int64)
        /// The eight bytes at entry sp + k, as they were at entry.
        case incoming(Int64)
        case unknown
    }

    struct State: Equatable {
        var registers: [String: Value]
        // Each fact covers exactly eight bytes. A store at a different start
        // address can still overwrite part of that saved register.
        var slots: [Int64: Value]
        // MAY provenance is independent of the must-value facts above: a
        // join can lose an exact address while retaining a feasible alias.
        var stackAliases: Set<String> = ["sp"]
        var stackAddressEscaped = false
        // No write since entry can have reached entry sp or above, so a load
        // there with no slot fact still reads the caller's bytes. Any call,
        // any write of unknown extent and any store reaching that far ends it.
        var incomingIntact = true

        mutating func setRegister(_ key: String, to value: Value, mayAliasStack: Bool = false) {
            registers[key] = value == .unknown ? nil : value
            if case .stack = value { stackAliases.insert(key) }
            else if mayAliasStack { stackAliases.insert(key) }
            else { stackAliases.remove(key) }
        }

        func value(_ key: String) -> Value { registers[key] ?? .unknown }

        /// The value of the eight bytes at entry sp + `address`.
        func load(at address: Int64) -> Value {
            if let value = slots[address] { return value }
            return address >= 0 && incomingIntact ? .incoming(address) : .unknown
        }

        /// What a callee's reloads (`CalleeEffect.restores`) hand back, read
        /// from this state at the call or tail branch: the callee's entry sp
        /// is the stack pointer here.
        func reloaded(_ effect: CalleeEffect) -> [String: Value] {
            var values: [String: Value] = [:]
            for (key, offset) in effect.restores {
                guard case .stack(let sp) = value("sp") else {
                    values[key] = .unknown
                    continue
                }
                let (address, overflow) = sp.addingReportingOverflow(offset)
                values[key] = overflow ? .unknown : load(at: address)
            }
            return values
        }

        /// A callee's clobbers and reloads, the reloads already read with
        /// `reloaded` before the call could change memory.
        mutating func apply(_ effect: CalleeEffect, reloaded: [String: Value], clobbersMayAliasStack: Bool) {
            for key in effect.clobbers { setRegister(key, to: .unknown, mayAliasStack: clobbersMayAliasStack) }
            for (key, value) in reloaded { setRegister(key, to: value) }
        }

        func merged(with other: State) -> State {
            State(
                registers: registers.filter { other.registers[$0.key] == $0.value },
                slots: slots.filter { other.slots[$0.key] == $0.value },
                stackAliases: stackAliases.union(other.stackAliases),
                stackAddressEscaped: stackAddressEscaped || other.stackAddressEscaped,
                incomingIntact: incomingIntact && other.incomingIntact
            )
        }

        mutating func invalidateSlotsForUnknownWrite(throughStackAlias: Bool) {
            incomingIntact = false
            if throughStackAlias || stackAddressEscaped {
                slots.removeAll()
                return
            }
            // Incoming pointers can reach caller-owned memory at entry SP
            // or above it. A save is private only if all eight bytes lie
            // below entry SP; testing its start alone misses straddling saves.
            slots = slots.filter { start, _ in
                let (end, overflow) = start.addingReportingOverflow(8)
                return !overflow && end <= 0
            }
        }

        mutating func invalidateSlots(at address: Int64, bytes: Int) {
            let (end, overflow) = address.addingReportingOverflow(Int64(bytes))
            guard bytes > 0, !overflow else {
                incomingIntact = false
                slots.removeAll()
                return
            }
            if end > 0 { incomingIntact = false }
            slots = slots.filter { start, _ in
                let (slotEnd, slotOverflow) = start.addingReportingOverflow(8)
                return !slotOverflow && (slotEnd <= address || start >= end)
            }
        }
    }

    /// For each exit (a `ret`, or a tail branch out), the callee-saved
    /// registers that hold their entry values there on every path. Nil when
    /// the body is not fully decoded or the fixpoint is capped: nothing is
    /// claimed then. An exit no path from the entry reaches is absent.
    static func entryValuesAtExits(
        blocks: [BasicBlock], entry: UInt64, addresses: Set<UInt64>,
        excluding excludedEdges: Set<CFGEdge> = [],
        callEffect: (Instruction) -> CalleeEffect = { _ in CalleeEffect() },
        exitEffect: (Instruction) -> CalleeEffect = { _ in CalleeEffect() },
        clobbersMayAliasStack: Bool = true
    ) -> [UInt64: Set<String>]? {
        exitValues(
            blocks: blocks, entry: entry, addresses: addresses, excluding: excludedEdges,
            callEffect: callEffect, exitEffect: exitEffect, clobbersMayAliasStack: clobbersMayAliasStack
        )?.mapValues { values in Set(values.filter { $0.value == .entry($0.key) }.keys) }
    }

    /// For each exit, what each callee-saved register holds there on every
    /// path (a register absent is unknown). Nil when the body is not fully
    /// decoded or the fixpoint is capped: nothing is claimed then.
    ///
    /// `callEffect` names registers a call does not hand back despite the
    /// ABI (a callee that may throw redefines x21; an outlined fragment can
    /// write any of them, or reload them from this frame). Its clobbers may
    /// hold a frame address afterwards unless `clobbersMayAliasStack` is
    /// false. `excluding` drops edges whose paths are accounted for elsewhere
    /// (a throw merged into a shared epilogue); exits are judged without
    /// them. `exitEffect` is what a tail branch's target does after this body
    /// exits through it.
    static func exitValues(
        blocks: [BasicBlock], entry: UInt64, addresses: Set<UInt64>,
        excluding excludedEdges: Set<CFGEdge> = [],
        callEffect: (Instruction) -> CalleeEffect = { _ in CalleeEffect() },
        exitEffect: (Instruction) -> CalleeEffect = { _ in CalleeEffect() },
        clobbersMayAliasStack: Bool = true
    ) -> [UInt64: [String: Value]]? {
        let calleeSaved = (19...29).map { "x\($0)" }
        var initial = State(registers: ["sp": .stack(0)], slots: [:])
        for key in calleeSaved { initial.registers[key] = .entry(key) }
        let blockAt = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        var inState: [UInt64: State] = [entry: initial]
        // States only shrink, so the last visit of an exit is the smallest;
        // intersecting every visit yields it without tracking which was last.
        var exits: [UInt64: [String: Value]] = [:]
        var worklist = [entry]
        var visits = 0
        while let start = worklist.popLast() {
            visits += 1
            guard visits <= 64 * max(blocks.count, 1) else {
                Probe.record(.summaryCap, at: entry, ["pass": .label("preservation")])
                return nil
            }
            guard let block = blockAt[start], var state = inState[start] else { return nil }
            for insn in block.instructions {
                guard let detail = insn.detail else { return nil }
                let internalBranch = insn.branchTarget.map(addresses.contains) == true
                let isExit = insn.controlFlow == .return
                    || (insn.controlFlow == .branch && !internalBranch && block.switchCases == nil)
                if isExit {
                    var exitState = state
                    let effect = exitEffect(insn)
                    exitState.apply(
                        effect, reloaded: exitState.reloaded(effect), clobbersMayAliasStack: clobbersMayAliasStack)
                    var values: [String: Value] = [:]
                    for key in calleeSaved where exitState.value(key) != .unknown { values[key] = exitState.value(key) }
                    exits[insn.address] = exits[insn.address].map { $0.filter { values[$0.key] == $0.value } } ?? values
                    continue
                }
                if insn.controlFlow == .call {
                    let effect = callEffect(insn)
                    // The callee reads its reloads before it can write anything.
                    let reloaded = state.reloaded(effect)
                    // A callee may mutate any save whose address it can
                    // reach. sp/x29 alone are ordinary frame bookkeeping;
                    // any other frame alias can be an outgoing argument,
                    // including an outlined fragment's nonstandard input.
                    if !state.stackAliases.subtracting(["sp", "x29"]).isEmpty
                        || (effect.readsFramePointer && state.stackAliases.contains("x29")) {
                        state.stackAddressEscaped = true
                    }
                    state.invalidateSlotsForUnknownWrite(throughStackAlias: false)
                    // The callee keeps the ABI: x19–x29 and sp survive it.
                    for index in 0...18 { state.setRegister("x\(index)", to: .unknown) }
                    state.setRegister("x30", to: .unknown)
                    state.apply(effect, reloaded: reloaded, clobbersMayAliasStack: clobbersMayAliasStack)
                    continue
                }
                apply(detail, to: &state)
            }
            for successor in block.successors where addresses.contains(successor) {
                if let end = block.instructions.last?.address,
                   excludedEdges.contains(CFGEdge(from: end, to: successor)) { continue }
                let merged = inState[successor].map { $0.merged(with: state) } ?? state
                if merged != inState[successor] {
                    inState[successor] = merged
                    worklist.append(successor)
                }
            }
        }
        return exits
    }

    /// The memory operand's address and the base's value after writeback.
    private static func access(_ detail: StructuredInsn, in state: State) -> (address: Int64?, base: String?, after: Value?) {
        guard let memory = detail.operands.first(where: { $0.operand.isMemory }),
              case .memory(let base?, let index, let displacement) = memory.operand, index == nil,
              case .stack(let k) = state.value(base.key)
        else { return (nil, nil, nil) }
        if detail.postIndex {
            let delta = detail.operands.last?.operand.immediateValue ?? 0
            return (k, base.key, .stack(k &+ delta))
        }
        return (k &+ displacement, base.key, detail.writeback ? .stack(k &+ displacement) : nil)
    }

    private static func apply(_ detail: StructuredInsn, to state: inout State) {
        let operands = detail.operands
        let hasStackBase = operands.contains { info in
            guard case .memory(let base?, _, _) = info.operand else { return false }
            return state.stackAliases.contains(base.key)
        }
        // A writeback through a base that is no known stack address still
        // moves that base.
        if detail.writeback, access(detail, in: state).address == nil,
           let memory = operands.first(where: { $0.operand.isMemory }),
           case .memory(let base?, _, _) = memory.operand {
            state.setRegister(base.key, to: .unknown, mayAliasStack: state.stackAliases.contains(base.key))
        }
        func register(_ index: Int) -> PhysReg? {
            index < operands.count ? operands[index].operand.register : nil
        }
        switch detail.id {
        case AARCH64_INS_MOV:
            if let destination = register(0), let source = register(1), destination.widthBits == 64 {
                state.setRegister(destination.key, to: state.value(source.key), mayAliasStack: state.stackAliases.contains(source.key))
                return
            }
        case AARCH64_INS_ADD, AARCH64_INS_SUB:
            if let destination = register(0), let source = register(1), destination.widthBits == 64,
               operands.count == 3, let immediate = operands[2].shiftedImmediate,
               case .stack(let k) = state.value(source.key) {
                state.setRegister(destination.key, to: .stack(detail.id == AARCH64_INS_ADD ? k &+ immediate : k &- immediate))
                return
            }
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP, AARCH64_INS_STNP,
             AARCH64_INS_STRB, AARCH64_INS_STURB, AARCH64_INS_STRH, AARCH64_INS_STURH:
            let (address, base, after) = access(detail, in: state)
            let count = detail.id == AARCH64_INS_STP || detail.id == AARCH64_INS_STNP ? 2 : 1
            // Even a pointer stored before a later save can expose that
            // future save. Do not tie escape lifetime to existing slot facts.
            for offset in 0..<count {
                if let source = register(offset), state.stackAliases.contains(source.key) {
                    state.stackAddressEscaped = true
                }
            }
            if let address {
                for offset in 0..<count {
                    guard let source = register(offset) else { continue }
                    let bytes: Int
                    switch detail.id {
                    case AARCH64_INS_STRB, AARCH64_INS_STURB: bytes = 1
                    case AARCH64_INS_STRH, AARCH64_INS_STURH: bytes = 2
                    default: bytes = source.widthBits / 8
                    }
                    let slot = address &+ Int64(offset * bytes)
                    state.invalidateSlots(at: slot, bytes: bytes)
                    // Only a whole 64-bit GPR is a saved entry value. A SIMD
                    // store invalidates its complete extent, including both
                    // adjacent eight-byte saves when it writes a Q register.
                    if bytes == 8, source.kind == .gpr {
                        state.slots[slot] = state.value(source.key)
                    }
                }
            } else {
                state.invalidateSlotsForUnknownWrite(throughStackAlias: hasStackBase)
            }
            if let base, let after { state.setRegister(base, to: after) }
            return
        case AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDP:
            let (address, base, after) = access(detail, in: state)
            let count = detail.id == AARCH64_INS_LDP ? 2 : 1
            for offset in 0..<count {
                guard let destination = register(offset) else { continue }
                if let address, destination.widthBits == 64 {
                    state.setRegister(destination.key, to: state.load(at: address &+ Int64(offset * 8)))
                } else {
                    state.setRegister(destination.key, to: .unknown)
                }
            }
            if let base, let after { state.setRegister(base, to: after) }
            return
        default:
            break
        }
        // An unsupported memory write (or missing memory access flags) has no
        // proven extent. Forget the saves when its base points into the frame.
        // Flags are used only to decline; supported stores use actual widths.
        if operands.contains(where: { $0.operand.isMemory && ($0.isWritten || $0.access == 0) }) {
            state.invalidateSlotsForUnknownWrite(throughStackAlias: hasStackBase)
        }
        // An unmodelled transform of a frame address loses its exact offset,
        // not its ability to alias the frame. Keep that MAY fact at joins too.
        let readsStackAlias = !detail.readRegisterKeys.intersection(state.stackAliases).isEmpty
            || operands.contains { info in
                guard let reg = info.operand.register else { return false }
                return (info.isRead || info.access == 0) && state.stackAliases.contains(reg.key)
            }
        if operands.contains(where: { $0.operand.isMemory && ($0.isWritten || $0.access == 0) }), readsStackAlias {
            state.stackAddressEscaped = true
        }
        for key in detail.writtenRegisterKeys {
            state.setRegister(key, to: .unknown, mayAliasStack: readsStackAlias)
        }
    }
}
