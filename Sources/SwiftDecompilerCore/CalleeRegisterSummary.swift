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
    var memoryEffect: CalleeMemoryEffect = .unknown
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

    /// The width each of those is read at (16 h, 32 s, 64 d), when every read
    /// of it agrees: a constant passed there is a float of that width.
    var floatArgumentWidths: [Int: Int] = [:]
    /// What this body reads of each in-image callee's result: after a `bl`
    /// to it and before the end of the block, which of x0, x1, v0 and v1 an
    /// instruction reads before anything writes it. Compiled code reads a
    /// result register after a call only when the callee returns one there,
    /// so these are evidence about the callee's result (`callerProvenResults`).
    var resultReads: [UInt64: ResultRead] = [:]

    struct ResultRead: OptionSet, Sendable, Hashable {
        let rawValue: UInt8
        static let x0 = ResultRead(rawValue: 1), x1 = ResultRead(rawValue: 2)
        static let v0 = ResultRead(rawValue: 4), v1 = ResultRead(rawValue: 8)
        /// x21, Swift's error register: a caller that reads it after the
        /// call is testing for a throw.
        static let x21 = ResultRead(rawValue: 16)
    }
    /// Calls and tail branches to other in-image functions, with the argument
    /// registers (bit n for xn) the body has not written at them on some
    /// path: the call reads those of them its target reads.
    var pendingReads: [PendingRead] = []
    /// Callee-saved registers (`x19`…`x29` and the low 64 bits of `v8`…`v15`)
    /// the body writes and does not provably hand back: at some exit (a `ret`
    /// or a tail branch out) the
    /// register does not hold its entry value. Anything unproven counts as
    /// clobbered.
    let clobberedCalleeSaved: Set<String>
    /// Every unproved vector low-lane clobber carries through calls, even
    /// when the body stored it without restoring it. For general registers,
    /// only those never stored carry through (an outlined fragment writing
    /// x19). A general register the body saves but whose save slot the
    /// analysis cannot prove intact (a frame address passed to a callee)
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
    /// Every call and tail branch out of the body, by target (nil when
    /// indirect), and whether every store the body makes is through
    /// sp, into its own stack. `closeOverFieldWrites` decides from these
    /// whether a call to the body can write a field of any object.
    ///
    /// It reads the calls only of a body that stores only to its stack, and
    /// asks of each distinct call alone, so the list is kept for such a body
    /// only, each call once, in order (`distinctOutgoingCalls`): one entry
    /// per call site for every function was 12.7 MB of a GoodLinks `xrefs`.
    var outgoingCalls: [OutgoingCall] = []
    /// Complete, immutable-body memory proof; unknown is the default.
    var memoryEffect: CalleeMemoryEffect = .unknown
    // Stored after the references so the bytes pack: a summary is held per
    // function for the whole run, in a table of 131,072 slots on GoodLinks.
    /// Argument registers x0…x7 (by number) the body may read before writing
    /// them on some path from its entry. A call or tail call inside counts as
    /// reading every one not yet written, since it may pass them on, unless
    /// its target's own reads are known: a callee of known arity reads its
    /// parameters, and a call to another in-image function waits in
    /// `pendingReads` until `closeOverReads` gives it that function's reads.
    let argumentReads: RegisterSet
    /// Of those, the registers the body's own instructions read, or an exact
    /// direct branch alias forwards to a body that proves them. An ordinary call
    /// proves no parameter: one of unknown arity may pass any unwritten
    /// register on (`swift_willThrowTyped`'s body reaches x6 and x7 only by
    /// calling `_stdlib_isOSVersionAtLeast…`, and it takes three), and even
    /// a known one's parameter may be whatever the register held (a lazy
    /// witness table accessor hands its untouched x2 to
    /// `swift_getWitnessTable`).
    var provenArgumentReads: RegisterSet = []
    /// The floating-point argument registers v0…v7 (by number) the body's own
    /// instructions read before writing them, including an exact direct branch
    /// alias's proven inputs. An ordinary call proves none, as for
    /// the integer registers. C passes floats on their own counter, so a
    /// body that reads one has parameters the integer reads do not count:
    /// `takef3(double, double, double)` rendered `takef3()`.
    var provenFloatArgumentReads: RegisterSet = []
    /// The body may leave a value in v0 for its caller: one of its own
    /// instructions writes v0, or it calls or tail-branches out (whatever it
    /// calls may return there). True when nothing is known.
    var mayWriteFloatResult = true
    /// The same for x0: one of the body's own instructions writes x0 (or
    /// w0), or it calls or tail-branches out. False proves that at every
    /// exit x0 still holds the caller's value, so a call's x0 result is the
    /// x0 it was called with: a lone `ret` (`gen<T>(_ a: Int, _: T) -> Int {
    /// a }` specialized) returns its argument. True when nothing is known.
    var mayWriteResult = true
    /// The body may use the caller's x29 as a pointer (`CalleeEffect`): it
    /// reads x29 before writing it, other than as the value a store to its
    /// own stack saves, directly or through a call to an in-image function
    /// that does (`closeOverReads`).
    var readsFramePointer = false
    /// The same for x22, the async context register: the body may write the
    /// context the caller holds there.
    var readsContextRegister = false
    /// Whether the body may read the x20 it was called with: as a value, or
    /// by a call that may (an in-image one that does, or one with no C
    /// arity, which may take it as `self`). A body that does not is no
    /// method of a `self` in x20, and a caller's x20 at a call to it is a
    /// temporary: `Mode.weight(self: r0, r0)` for a by-value enum method.
    /// True when nothing is known.
    var readsSelfRegister = true
    var storesOnlyToStack = false
    /// The body writes no field of any object, nor does anything it calls
    /// (`closeOverFieldWrites`): an outlined fragment that tail-calls
    /// `swift_beginAccess`. False until proven.
    var writesNoFields = false
    /// Where the decoded read analysis begins. Pure-alias closure checks this
    /// against the summary dictionary's actual entry key: Capstone can skip an
    /// undecodable prefix, and a function's displayed start alone is not proof.
    var inputProofEntry: UInt64? {
        get { hasInputProofEntry ? inputProofEntryAddress : nil }
        set { inputProofEntryAddress = newValue ?? 0; hasInputProofEntry = newValue != nil }
    }
    /// An immutable body consisting of exactly one direct unconditional B to
    /// another declared in-image function. No prologue, moves, calls, indirect
    /// branch or conditional branch can inherit its target's input proof.
    /// Stored as the branch's offset from the entry, which a `b` keeps
    /// within ±128 MB.
    var pureTailTarget: UInt64? {
        get {
            guard hasPureTailTarget, let entry = inputProofEntry else { return nil }
            return entry &+ UInt64(bitPattern: Int64(pureTailOffset))
        }
        set {
            guard let target = newValue, let entry = inputProofEntry,
                  let offset = Int32(exactly: Int64(bitPattern: target &- entry))
            else { pureTailOffset = 0; hasPureTailTarget = false; return }
            pureTailOffset = offset
            hasPureTailTarget = true
        }
    }
    private var inputProofEntryAddress: UInt64 = 0
    private var pureTailOffset: Int32 = 0
    private var hasInputProofEntry = false
    private var hasPureTailTarget = false

    init(
        argumentReads: RegisterSet, provenArgumentReads: RegisterSet = [], provenFloatArgumentReads: RegisterSet = [],
        floatArgumentWidths: [Int: Int] = [:], mayWriteFloatResult: Bool = true, mayWriteResult: Bool = true,
        resultReads: [UInt64: ResultRead] = [:], pendingReads: [PendingRead] = [], readsFramePointer: Bool = false,
        readsContextRegister: Bool = false, readsSelfRegister: Bool = true, clobberedCalleeSaved: Set<String>,
        definitelyClobbered: Set<String> = [], restoredFrom: [String: Int64] = [:], callees: [UInt64] = [],
        outgoingCalls: [OutgoingCall] = [], storesOnlyToStack: Bool = false, writesNoFields: Bool = false,
        memoryEffect: CalleeMemoryEffect = .unknown, inputProofEntry: UInt64? = nil, pureTailTarget: UInt64? = nil
    ) {
        self.floatArgumentWidths = floatArgumentWidths
        self.resultReads = resultReads
        self.pendingReads = pendingReads
        self.clobberedCalleeSaved = clobberedCalleeSaved
        self.definitelyClobbered = definitelyClobbered
        self.restoredFrom = restoredFrom
        self.callees = callees
        self.outgoingCalls = outgoingCalls
        self.memoryEffect = memoryEffect
        self.argumentReads = argumentReads
        self.provenArgumentReads = provenArgumentReads
        self.provenFloatArgumentReads = provenFloatArgumentReads
        self.mayWriteFloatResult = mayWriteFloatResult
        self.mayWriteResult = mayWriteResult
        self.readsFramePointer = readsFramePointer
        self.readsContextRegister = readsContextRegister
        self.readsSelfRegister = readsSelfRegister
        self.storesOnlyToStack = storesOnlyToStack
        self.writesNoFields = writesNoFields
        // The target is stored relative to the entry, so the entry first.
        self.inputProofEntry = inputProofEntry
        self.pureTailTarget = pureTailTarget
    }

    /// Each call once, indirect calls first, then by target.
    static func distinctOutgoingCalls(_ calls: [OutgoingCall]) -> [OutgoingCall] {
        var seen = Set<OutgoingCall>()
        return calls.filter { seen.insert($0).inserted }.sorted {
            ($0.target ?? 0, $0.target == nil ? 0 : 1, $0.isFunction ? 1 : 0)
                < ($1.target ?? 0, $1.target == nil ? 0 : 1, $1.isFunction ? 1 : 0)
        }
    }

    struct OutgoingCall: Sendable, Hashable {
        let target: UInt64?
        /// The target is an in-image function, judged by its body; anything
        /// else (a stub) is judged by its name.
        let isFunction: Bool
    }

    /// What a call to this function does to its caller's callee-saved
    /// registers, as far as it carries beyond the direct callers.
    var effect: CalleeEffect {
        CalleeEffect(clobbers: definitelyClobbered.subtracting(restoredFrom.keys), restores: restoredFrom,
                     readsFramePointer: readsFramePointer, memoryEffect: memoryEffect)
    }

    /// The integer arguments a call to this function can pass: through the
    /// highest argument register it reads. Unread registers below that are
    /// positional parameters it ignores.
    var argumentCount: Int { (argumentReads.max() ?? -1) + 1 }

    /// The parameters a call to this function has, as its own body proves
    /// them: through the highest register it reads itself or forwards through
    /// an exact direct branch alias to a body that proves it.
    var provenArgumentCount: Int { (provenArgumentReads.max() ?? -1) + 1 }

    /// The floating-point parameters the body proves: through the highest v
    /// register it reads itself or forwards through an exact direct branch alias.
    var provenFloatArgumentCount: Int { (provenFloatArgumentReads.max() ?? -1) + 1 }

    private static let argumentKeys = (0...7).map { "x\($0)" }
    private static let floatArgumentKeys = (0...7).map { "v\($0)" }
    private static let framePointerBit: UInt32 = 1 << 29
    private static let contextRegisterBit: UInt32 = 1 << 22
    private static let selfRegisterBit: UInt32 = 1 << 20
    private static let calleeSavedKeys = Set(Preservation.calleeSavedKeys)

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
        isFunction: (UInt64) -> Bool = { _ in false },
        isImportStub: (UInt64) -> Bool = { _ in false }
    ) -> CalleeRegisterSummary? {
        analyze(function, calleeEffects: calleeEffects, calleeArity: calleeArity,
                isFunction: isFunction, isImportStub: isImportStub, retainingReads: nil)
    }

    /// Rebuild preservation for the same immutable body after its reads have
    /// been closed over calls. Clobber closure retains those reads; redoing
    /// their argument/self-flow analyses cannot contribute any new fact.
    static func recomputingPreservation(
        _ function: DisassembledFunction, retainingReadsFrom summary: CalleeRegisterSummary,
        calleeEffects: (UInt64) -> CalleeEffect,
        calleeArity: (UInt64) -> Int? = { _ in nil },
        isFunction: (UInt64) -> Bool = { _ in false },
        isImportStub: (UInt64) -> Bool = { _ in false }
    ) -> CalleeRegisterSummary? {
        analyze(function, calleeEffects: calleeEffects, calleeArity: calleeArity,
                isFunction: isFunction, isImportStub: isImportStub, retainingReads: summary)
    }

    private static func analyze(
        _ function: DisassembledFunction, calleeEffects: (UInt64) -> CalleeEffect = { _ in CalleeEffect() },
        calleeArity: (UInt64) -> Int? = { _ in nil },
        isFunction: (UInt64) -> Bool = { _ in false },
        isImportStub: (UInt64) -> Bool = { _ in false },
        retainingReads readFacts: CalleeRegisterSummary?
    ) -> CalleeRegisterSummary? {
        let instructions = function.instructions
        guard !instructions.isEmpty, instructions.allSatisfy({ $0.detail != nil }) else { return nil }
        let addresses = Set(instructions.map(\.address))
        let blocks = function.basicBlocks()
        guard let entry = blocks.first?.startAddress else { return nil }
        let blockAt = readFacts == nil ? Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a }) : [:]

        // Forward must-analysis: the argument registers written on every path
        // into a block (intersection at joins). A read of one not in the set is
        // a possible argument read.
        var inState: [UInt64: Set<String>] = readFacts == nil ? [entry: []] : [:]
        var reads = readFacts?.argumentReads ?? RegisterSet()
        var provenReads = readFacts?.provenArgumentReads ?? RegisterSet()
        var provenFloatReads = readFacts?.provenFloatArgumentReads ?? RegisterSet()
        var floatWidths = readFacts?.floatArgumentWidths ?? [:]
        var writesFloatResult = readFacts?.mayWriteFloatResult ?? false
        var readsFramePointer = readFacts?.readsFramePointer ?? false
        var readsContextRegister = readFacts?.readsContextRegister ?? false
        // By call address: a block revisited with fewer registers written
        // widens the mask, as it widens `reads`.
        var pending: [UInt64: PendingRead] = [:]
        var worklist = readFacts == nil ? [entry] : []
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
                func read(_ key: String, proven: Bool = true) {
                    guard let index = argumentKeys.firstIndex(of: key), !written.contains(key) else { return }
                    reads.insert(index)
                    if proven { provenReads.insert(index) }
                }
                if !written.contains("x29"), Self.uses("x29", in: detail) { readsFramePointer = true }
                if !written.contains("x22"), Self.uses("x22", in: detail) { readsContextRegister = true }
                let internalBranch = insn.branchTarget.map(addresses.contains) == true
                let leavesThroughCall = insn.controlFlow == .call
                    || ((insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch)
                        && !internalBranch && block.switchCases == nil)
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
                        let known = insn.branchTarget.flatMap(calleeArity)
                        argumentKeys.prefix(known ?? argumentKeys.count).forEach { read($0, proven: false) }
                    }
                }
                // Operands without access flags are counted as read, so a gap
                // in Capstone's tables cannot hide an argument.
                for info in detail.operands {
                    if case .register(let register) = info.operand, register.kind == .gpr,
                       info.access == 0 || info.isRead {
                        read(register.key)
                    }
                    if case .register(let register) = info.operand, register.kind == .vector,
                       register.number < 8, info.access == 0 || info.isRead, !written.contains(register.key) {
                        provenFloatReads.insert(register.number)
                        // Disagreeing widths (or a vector read) leave it unmarked.
                        let width = info.vectorIndex == nil ? register.widthBits : 0
                        floatWidths[register.number] = floatWidths[register.number].map { $0 == width ? width : 0 } ?? width
                    }
                }
                // A whole-register write ends the argument; a lane insert
                // (`mov v0.s[1], w1`) keeps the rest of it.
                for info in detail.operands where info.isWritten && info.vectorIndex == nil {
                    if case .register(let register) = info.operand, register.kind == .vector, register.number < 8 {
                        written.insert(register.key)
                    }
                }
                for info in detail.operands where info.isWritten {
                    if case .register(let register) = info.operand, register.kind == .vector, register.number == 0 {
                        writesFloatResult = true
                    }
                }
                if leavesThroughCall { writesFloatResult = true }
                detail.readRegisterKeys.forEach { read($0) }
                written.formUnion(detail.writtenRegisterKeys.intersection(argumentKeys + ["x29", "x22"]))
                if insn.controlFlow == .call { written.formUnion(argumentKeys + floatArgumentKeys) }
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
        var storedGeneralCalleeSaved = Set<String>()
        var callees = Set<UInt64>()
        var outgoingCalls: [OutgoingCall] = []
        var storesOnlyToStack = true
        var writesResult = false
        for insn in instructions {
            guard let detail = insn.detail else { return nil }
            if detail.writtenRegisterKeys.contains("x0")
                || insn.controlFlow == .call
                || ((insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch)
                    && insn.branchTarget.map(addresses.contains) != true) {
                writesResult = true
            }
            writtenCalleeSaved.formUnion(Preservation.writtenRegisterKeys(in: detail).intersection(calleeSavedKeys))
            for info in detail.operands where info.isWritten {
                guard case .memory(let base, _, _) = info.operand else { continue }
                if base?.kind != .stackPointer { storesOnlyToStack = false }
            }
            if insn.controlFlow == .call
                || ((insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch)
                    && insn.branchTarget.map(addresses.contains) != true) {
                outgoingCalls.append(OutgoingCall(
                    target: insn.branchTarget, isFunction: insn.branchTarget.map(isFunction) ?? false))
            }
            if detail.operands.contains(where: { if case .memory = $0.operand { $0.isWritten } else { false } }) {
                for info in detail.operands where info.isRead {
                    if case .register(let register) = info.operand, register.kind == .gpr,
                       calleeSavedKeys.contains(register.key) {
                        storedGeneralCalleeSaved.insert(register.key)
                    }
                }
            }
            if insn.controlFlow == .call || insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch,
               let target = insn.branchTarget,
               !addresses.contains(target) || (insn.controlFlow == .call && target == entry) {
                callees.insert(target)
                let effect = calleeEffects(target)
                writtenCalleeSaved.formUnion(effect.clobbers)
                writtenCalleeSaved.formUnion(effect.restores.keys)
            }
        }
        func external(_ insn: Instruction) -> UInt64? {
            // A call to entry recurses; a branch to entry stays a CFG edge.
            guard let target = insn.branchTarget,
                  !addresses.contains(target) || (insn.controlFlow == .call && target == entry) else { return nil }
            return target
        }
        let callEffect = { (insn: Instruction) -> CalleeEffect in
            insn.controlFlow == .call ? external(insn).map(calleeEffects) ?? CalleeEffect() : CalleeEffect()
        }
        let callInputs = { (insn: Instruction) -> Set<String>? in
            guard let target = insn.branchTarget else {
                // An indirect call reaches no outlined fragment: the
                // machine outliner calls its fragments directly.
                return Preservation.abiCallInputs
            }
            // A callee of known arity is a named function, not a
            // fragment, and takes exactly its parameters, and x8 when
            // it returns a large struct through it.
            if let arity = calleeArity(target) { return Set((0..<min(arity, 8)).map { "x\($0)" } + ["x8"]) }
            return isImportStub(target) ? Preservation.abiCallInputs : nil
        }
        // Where the incoming x20 may be, through moves and spills. A call to
        // an in-image function with it still in x20 reads it if that
        // function does: its pending read carries the bit.
        let readsSelfRegister: Bool
        if let readFacts {
            readsSelfRegister = readFacts.readsSelfRegister
        } else {
            let selfFlow = Preservation.selfRegisterFlow(
                blocks: blocks, entry: entry, addresses: addresses, callEffect: callEffect, callInputs: callInputs,
                forwards: { insn in insn.branchTarget.map { calleeArity($0) == nil && isFunction($0) } ?? false })
            for (address, call) in pending where selfFlow?.forwardedAt.contains(address) ?? true {
                pending[address] = PendingRead(target: call.target, unwritten: call.unwritten | Self.selfRegisterBit)
            }
            readsSelfRegister = selfFlow?.reads ?? true
        }
        var clobbered = Set<String>()
        var restoredFrom: [String: Int64] = [:]
        if !writtenCalleeSaved.isEmpty {
            let exits = Preservation.exitValues(
                blocks: blocks, entry: entry, addresses: addresses,
                callEffect: callEffect,
                exitEffect: { insn in
                    insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch
                        ? external(insn).map(calleeEffects) ?? CalleeEffect() : CalleeEffect()
                },
                callInputs: callInputs,
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
        // The save-slot escape exception belongs to GPRs only. A stored but
        // unrestored vector must still invalidate its callers' low lanes.
        let definitelyClobbered = clobbered.subtracting(storedGeneralCalleeSaved).subtracting(["x21"])
        var summary = CalleeRegisterSummary(
            argumentReads: reads,
            provenArgumentReads: provenReads,
            provenFloatArgumentReads: provenFloatReads,
            floatArgumentWidths: floatWidths.filter { [16, 32, 64].contains($0.value) },
            mayWriteFloatResult: writesFloatResult,
            pendingReads: readFacts?.pendingReads ?? pending.keys.sorted().compactMap { pending[$0] },
            readsFramePointer: readsFramePointer,
            readsContextRegister: readsContextRegister,
            readsSelfRegister: readsSelfRegister,
            clobberedCalleeSaved: clobbered,
            definitelyClobbered: definitelyClobbered,
            restoredFrom: restoredFrom.filter { definitelyClobbered.contains($0.key) },
            callees: callees.sorted(),
            outgoingCalls: storesOnlyToStack ? Self.distinctOutgoingCalls(outgoingCalls) : [],
            storesOnlyToStack: storesOnlyToStack,
            memoryEffect: readFacts?.memoryEffect ?? CalleeMemoryEffect.discover(in: function),
            inputProofEntry: readFacts?.inputProofEntry ?? instructions.first?.address,
            pureTailTarget: readFacts?.pureTailTarget ?? pureTailTarget(of: function, isFunction: isFunction))
        summary.mayWriteResult = writesResult
        summary.resultReads = readFacts?.resultReads ?? Self.resultReads(
            instructions, blockStarts: Set(blocks.map(\.startAddress)), isFunction: isFunction,
            provenNonThrowing: DisassembledFunction.splitSignature(function.analysisDisplayName)
                .map { !$0.isThrowing } ?? false)
        return summary
    }

    private static func pureTailTarget(
        of function: DisassembledFunction, isFunction: (UInt64) -> Bool
    ) -> UInt64? {
        guard function.instructions.count == 1, let branch = function.instructions.first,
              branch.address == function.startAddress,
              branch.controlFlow == .branch, branch.detail?.id == AARCH64_INS_B,
              let target = branch.branchTarget, target != branch.address, isFunction(target)
        else { return nil }
        return target
    }

    /// Marks each body that writes no field of any object: it stores only
    /// into its own stack, makes no indirect call, and calls only runtime
    /// functions that write none (`CallFacts.writesNoFields`) or bodies
    /// already marked. A least fixpoint, so a cycle is never marked; a call
    /// to anything but an in-image function (a stub) is judged by its name. -Osize outlines
    /// `swift_beginAccess` into `OUTLINED_FUNCTION_3` (`mov x2, #0;
    /// mov x3, #0; b swift_beginAccess`), and a call to it forgot every field
    /// of self the caller held.
    /// `name` gives a stub's name: the summaries are built before any call
    /// is named.
    static func closeOverFieldWrites(
        _ summaries: inout [UInt64: CalleeRegisterSummary], name: (UInt64) -> String?
    ) {
        let starts = summaries.keys.sorted()
        var changed = true
        while changed {
            changed = false
            for start in starts {
                guard let summary = summaries[start], !summary.writesNoFields, summary.storesOnlyToStack else { continue }
                let preserving = summary.outgoingCalls.allSatisfy { call in
                    guard let target = call.target else { return false }
                    if call.isFunction { return summaries[target]?.writesNoFields ?? false }
                    return name(target).map { ValueTracer.CallFacts(callee: $0).writesNoFields } ?? false
                }
                if preserving {
                    summaries[start]?.writesNoFields = true
                    changed = true
                }
            }
        }
    }

    /// A summary that claims nothing about callee-saved registers.
    private func claimingNothing() -> CalleeRegisterSummary {
        CalleeRegisterSummary(
            argumentReads: argumentReads, provenArgumentReads: provenArgumentReads,
            provenFloatArgumentReads: provenFloatArgumentReads, floatArgumentWidths: floatArgumentWidths,
            mayWriteFloatResult: true, pendingReads: pendingReads,
            readsFramePointer: readsFramePointer,
            readsContextRegister: readsContextRegister, clobberedCalleeSaved: Self.calleeSavedKeys,
            definitelyClobbered: Self.calleeSavedKeys, callees: callees, memoryEffect: memoryEffect,
            inputProofEntry: inputProofEntry, pureTailTarget: pureTailTarget)
    }

    /// Initial read/preservation analyses precede the callee summaries. Once
    /// every immutable body effect is available, repeat only its callers so
    /// all three memory consumers see the same proof before reads are closed.
    /// This pass carries memory alone; call-clobber closure remains separate.
    static func refineMemory(
        _ summaries: inout [UInt64: CalleeRegisterSummary],
        recompute: (UInt64, (UInt64) -> CalleeEffect) -> CalleeRegisterSummary?
    ) {
        let effects = summaries.compactMapValues { summary -> CalleeEffect? in
            guard case .literalStores = summary.memoryEffect else { return nil }
            return CalleeEffect(memoryEffect: summary.memoryEffect)
        }
        guard !effects.isEmpty else { return }
        let callers = summaries.keys.sorted().filter { start in
            summaries[start]?.callees.contains { effects[$0] != nil } == true
        }
        for start in callers {
            summaries[start] = recompute(start, { effects[$0] ?? CalleeEffect() })
                ?? summaries[start]?.claimingNothing()
        }
    }

    /// After each `bl` to an in-image function, the result registers read
    /// before written, to the end of the call's block.
    ///
    /// A caller that returns right after the call with x21 as the callee
    /// left it may be handing on the callee's error: a throwing witness thunk
    /// is `bl f; and w0, w0, #1; ret`. Unless its own signature says it does
    /// not throw, that counts as reading x21.
    static func resultReads(
        _ instructions: [Instruction], blockStarts: Set<UInt64>, isFunction: (UInt64) -> Bool,
        provenNonThrowing: Bool = false
    ) -> [UInt64: ResultRead] {
        var reads: [UInt64: ResultRead] = [:]
        let keys: [(String, ResultRead)] = [("x0", .x0), ("x1", .x1), ("v0", .v0), ("v1", .v1), ("x21", .x21)]
        for (index, insn) in instructions.enumerated() where insn.controlFlow == .call {
            guard let target = insn.branchTarget, isFunction(target) else { continue }
            var read: ResultRead = []
            var written = Set<String>()
            var next = index + 1
            while next < instructions.count, !blockStarts.contains(instructions[next].address),
                  let detail = instructions[next].detail {
                let used = detail.readRegisterKeys
                for (key, bit) in keys where used.contains(key) && !written.contains(key) { read.insert(bit) }
                written.formUnion(detail.writtenRegisterKeys)
                let flow = instructions[next].controlFlow
                if !provenNonThrowing, !written.contains("x21"),
                   flow == .return || (flow == .branch && instructions[next].branchTarget == nil) {
                    read.insert(.x21)
                }
                if flow != .sequential { break }
                next += 1
            }
            if !read.isEmpty { reads[target, default: []].formUnion(read) }
        }
        return reads
    }

    /// Each in-image function whose callers prove its result is one integer
    /// or pointer in x0: some caller reads x0 after calling it and none reads
    /// x1, v0 or v1. A caller reading two registers, or both banks, proves no
    /// one register.
    /// A function that may throw proves none either: its exit can be a throw
    /// (an error in x21), and a stripped one has no `throws` to say so. A
    /// caller reading x21 after the call, or a body that leaves x21 changed,
    /// is that sign.
    static func callerProvenResults(
        _ summaries: [UInt64: CalleeRegisterSummary]
    ) -> [UInt64: Disassembler.SwiftReturnRegister] {
        var seen: [UInt64: ResultRead] = [:]
        for caller in summaries.keys.sorted() {
            for (callee, read) in summaries[caller]?.resultReads ?? [:] { seen[callee, default: []].formUnion(read) }
        }
        // Only x0: a float's width (Float or Double) is its type's, which a
        // function with no signature does not have, so v0 proves nothing
        // printable yet.
        return seen.filter { summaries[$0.key]?.clobberedCalleeSaved.contains("x21") == false }.compactMapValues { read in
            read == .x0 ? .integer : nil
        }
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
            var readsSelfRegister = summary.readsSelfRegister
            for call in summary.pendingReads {
                let targetReads = summaries[call.target]?.argumentReads ?? RegisterSet(0 ..< argumentKeys.count)
                for index in targetReads where call.unwritten & (1 << index) != 0 { reads.insert(index) }
                if call.unwritten & framePointerBit != 0, summaries[call.target]?.readsFramePointer ?? true {
                    readsFramePointer = true
                }
                if call.unwritten & contextRegisterBit != 0, summaries[call.target]?.readsContextRegister ?? true {
                    readsContextRegister = true
                }
                if call.unwritten & selfRegisterBit != 0, summaries[call.target]?.readsSelfRegister ?? true {
                    readsSelfRegister = true
                }
            }
            guard reads != summary.argumentReads || readsFramePointer != summary.readsFramePointer
                || readsContextRegister != summary.readsContextRegister
                || readsSelfRegister != summary.readsSelfRegister
            else { continue }
            summaries[start] = summary.replacingReads(
                reads, readsFramePointer: readsFramePointer, readsContextRegister: readsContextRegister,
                readsSelfRegister: readsSelfRegister)
            for caller in callers[start] ?? [] where queued.insert(caller).inserted {
                worklist.append(caller)
            }
        }
        for start in starts { summaries[start]?.pendingReads = [] }
        closeOverPureTailInputs(&summaries, starts: starts)
    }

    /// A single unconditional direct branch is an ABI alias: it changes no
    /// argument register and performs no work before entering its target.
    /// Carry only proved inputs, with their floating-point widths, backwards
    /// from a decoded non-alias entry. Ordinary calls keep their existing
    /// conservative policy, even when their possible reads close transitively.
    ///
    /// Seed no alias. A cycle, an unknown/interior target, a missing summary
    /// (including a bounded decode), or an undecoded entry cannot gain proof.
    /// Each resolved alias enters the queue once, so this needs neither
    /// recursion nor a depth cap and is bounded by the summary graph's size.
    private static func closeOverPureTailInputs(
        _ summaries: inout [UInt64: CalleeRegisterSummary], starts: [UInt64]
    ) {
        var aliases: [UInt64: [UInt64]] = [:]
        for start in starts {
            guard let summary = summaries[start] else { continue }
            if let target = summary.pureTailTarget {
                // Reclosing the same immutable summaries remains fail-closed:
                // a stale inherited proof cannot seed an alias cycle.
                summaries[start]?.provenArgumentReads = []
                summaries[start]?.provenFloatArgumentReads = []
                summaries[start]?.floatArgumentWidths = [:]
                guard summary.inputProofEntry == start,
                      summaries[target]?.inputProofEntry == target else { continue }
                aliases[target, default: []].append(start)
            }
        }
        // Only providers an alias actually reaches need queue space. Reuse the
        // caller's sorted entry list instead of sorting every summary again.
        var worklist = aliases.keys.sorted().filter { target in
            summaries[target]?.pureTailTarget == nil
        }
        var resolved = Set(worklist)
        var next = 0
        while next < worklist.count {
            let target = worklist[next]
            next += 1
            guard let proof = summaries[target] else { continue }
            for start in aliases[target] ?? [] where resolved.insert(start).inserted {
                summaries[start]?.provenArgumentReads = proof.provenArgumentReads
                summaries[start]?.provenFloatArgumentReads = proof.provenFloatArgumentReads
                summaries[start]?.floatArgumentWidths = proof.floatArgumentWidths
                worklist.append(start)
            }
        }
    }

    private func replacingReads(
        _ reads: RegisterSet, readsFramePointer: Bool, readsContextRegister: Bool, readsSelfRegister: Bool
    ) -> CalleeRegisterSummary {
        var summary = CalleeRegisterSummary(
            argumentReads: reads, provenArgumentReads: provenArgumentReads,
            provenFloatArgumentReads: provenFloatArgumentReads, floatArgumentWidths: floatArgumentWidths,
            mayWriteFloatResult: mayWriteFloatResult, pendingReads: pendingReads,
            readsFramePointer: readsFramePointer,
            readsContextRegister: readsContextRegister, readsSelfRegister: readsSelfRegister,
            clobberedCalleeSaved: clobberedCalleeSaved,
            definitelyClobbered: definitelyClobbered, restoredFrom: restoredFrom, callees: callees,
            outgoingCalls: outgoingCalls, storesOnlyToStack: storesOnlyToStack, memoryEffect: memoryEffect,
            inputProofEntry: inputProofEntry, pureTailTarget: pureTailTarget)
        summary.mayWriteResult = mayWriteResult
        summary.resultReads = resultReads
        return summary
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
    /// The callback also receives this body's existing, closed read facts.
    /// Its immutable body can reuse them while rebuilding preservation.
    static func closeOverCalls(
        _ summaries: inout [UInt64: CalleeRegisterSummary],
        cap fixedCap: Int? = nil,
        recompute: (UInt64, (UInt64) -> CalleeEffect, CalleeRegisterSummary) -> CalleeRegisterSummary?
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
            let rebuilt = recompute(start, { summaries[$0]?.effect ?? CalleeEffect() }, old) ?? old.claimingNothing()
            var new = CalleeRegisterSummary(
                argumentReads: old.argumentReads,
                provenArgumentReads: old.provenArgumentReads,
                provenFloatArgumentReads: old.provenFloatArgumentReads,
                floatArgumentWidths: old.floatArgumentWidths,
                mayWriteFloatResult: old.mayWriteFloatResult,
                pendingReads: old.pendingReads,
                readsFramePointer: old.readsFramePointer,
                readsContextRegister: old.readsContextRegister,
                // Reads are closed over already (`closeOverReads`); a
                // rebuild for clobbers keeps them. Left to its default, a
                // function calling a clobbering fragment read as reading x20
                // again, and a temporary its caller parked there as `self`.
                readsSelfRegister: old.readsSelfRegister,
                clobberedCalleeSaved: rebuilt.clobberedCalleeSaved,
                definitelyClobbered: rebuilt.definitelyClobbered,
                restoredFrom: rebuilt.restoredFrom,
                callees: old.callees,
                outgoingCalls: old.outgoingCalls,
                storesOnlyToStack: old.storesOnlyToStack, memoryEffect: old.memoryEffect,
                inputProofEntry: old.inputProofEntry, pureTailTarget: old.pureTailTarget)
            guard new != old else { continue }
            new.mayWriteResult = old.mayWriteResult
            new.resultReads = old.resultReads
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
/// overwrite it and never reload it. Over the CFG, each general register,
/// vector low 64 bits and 8-byte stack slot hold an abstract value: some register's entry
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
    /// A vector key proves only its low 64 bits, never the upper lane.
    static let calleeSavedKeys = (19...29).map { "x\($0)" } + (8...15).map { "v\($0)" }

    /// MachineDetail's shared keys intentionally cover general registers only.
    /// A vector write also ends what this analysis knows of that register.
    /// Missing access flags cannot prove that an operand was left untouched.
    static func writtenRegisterKeys(in detail: StructuredInsn) -> Set<String> {
        var keys = detail.writtenRegisterKeys
        for info in detail.operands where info.isWritten || info.access == 0 {
            if let register = info.operand.register, register.kind == .vector {
                keys.insert(register.key)
            }
        }
        if writesUnmodeledRegister(detail) {
            keys.formUnion((0..<32).map { "v\($0)" })
        }
        return keys
    }

    private static func writesUnmodeledRegister(_ detail: StructuredInsn) -> Bool {
        detail.operands.contains {
            ($0.isWritten || $0.access == 0) && $0.operand.register?.kind == .other
        }
    }

    enum Value: Hashable {
        case entry(String)
        case stack(Int64)
        /// The eight bytes at entry sp + k, as they were at entry.
        case incoming(Int64)
        /// An address inside a dynamic stack allocation that hangs below
        /// entry sp + k: `sub x9, sp, x12; mov sp, x9` with x12 its size.
        /// A store through it reaches no save at or above k plus its own
        /// displacement and extent, the same bound the tracer's
        /// `.frameDynamic` uses.
        case below(Int64)
        case unknown
    }

    /// The frame addresses a register may hold: these offsets, or any
    /// address inside a dynamic allocation below `below`.
    typealias FrameReach = FrameRegisterOrigins

    /// Frame offsets `[floor, bound)` an escaped address can reach.
    typealias EscapeRange = FrozenFrameRange

    struct State: Equatable {
        var registerFacts = PreservationFrameRegisterFacts()
        var registers: [String: Value] {
            _read { yield registerFacts.exactValues }
            _modify { yield &registerFacts.exactValues }
        }
        // Each fact covers exactly eight bytes. A store at a different start
        // address can still overwrite part of that saved register.
        var slots: FrameFacts<WordFrameFact<Value>>
        // MAY provenance is independent of the must-value facts above: a
        // join can lose an exact address while retaining a feasible alias.
        var stackAliases: Set<String> {
            _read { yield registerFacts.aliasKeys }
            _modify { yield &registerFacts.aliasKeys }
        }
        var reach = FrozenFrameReach()
        // Compatibility properties forward to the sole durable owner.
        var stackAddressEscaped: Bool {
            get { reach.hasWhole }
            set { reach[.whole] = newValue ? ReachPresence() : nil }
        }
        var escapedRanges: Set<EscapeRange> {
            get { reach.frozenRanges }
            set { reach.frozenRanges = newValue }
        }
        // No write since entry can have reached entry sp or above, so a load
        // there with no slot fact still reads the caller's bytes. Any call,
        // any write of unknown extent and any store reaching that far ends it.
        var incomingIntact = true
        // For a frame alias whose exact value a join lost, the frame
        // addresses it may hold: x1 is `sub x1, x29, #0x48` on one path and
        // no frame address on the other, x25 a dynamic allocation on one and
        // no frame address on the other. Absent means any.
        var aliasReach: [String: FrameReach] {
            _read { yield registerFacts.finiteOrigins }
            _modify { yield &registerFacts.finiteOrigins }
        }

        init(
            registers: [String: Value], slots: FrameFacts<WordFrameFact<Value>>,
            stackAliases: Set<String> = ["sp"], stackAddressEscaped: Bool = false,
            escapedRanges: Set<EscapeRange> = [], incomingIntact: Bool = true,
            aliasReach: [String: FrameReach] = [:]
        ) {
            self.slots = slots; self.registers = registers
            self.stackAliases = stackAliases; self.incomingIntact = incomingIntact
            self.aliasReach = aliasReach
            for range in escapedRanges { reach[.range(range)] = ReachPresence() }
            if stackAddressEscaped { reach[.whole] = ReachPresence() }
        }

        mutating func setRegister(_ key: String, to value: Value, mayAliasStack: Bool = false) {
            registerFacts.installPreservation(key, value: value, mayAlias: mayAliasStack)
        }

        func value(_ key: String) -> Value { registerFacts[key] ?? .unknown }

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
            var result = State(
                registers: [:],
                slots: slots.intersecting(with: other.slots),
                stackAliases: [],
                incomingIntact: incomingIntact && other.incomingIntact
            )
            result.registerFacts = registerFacts.mergedPreservation(with: other.registerFacts)
            result.reach = reach.union(other.reach)
            return result
        }

        /// The frame addresses `key` may hold here: a known stack address,
        /// a dynamic allocation's, nothing for a register that is no frame
        /// alias, and nil when it may be any.
        func frameReach(_ key: String) -> FrameReach? {
            registerFacts.origins(key)
        }

        /// The frame addresses in `keys` reach code this body does not see.
        /// One strictly below every save made so far reaches up to the
        /// lowest save; anything else may reach every slot.
        mutating func markEscape<Keys: Sequence>(_ keys: Keys) where Keys.Element == String {
            // Each saved or spilled entry value is a slot of its own. An
            // escaped address outside every one reaches up to the next one
            // above it, the extent of the object it points at: a local below
            // the save area, or one in a gap inside it (a byte local in the
            // padding word `str x28, [sp, #-0x60]!` leaves at sp + 8). An
            // address inside a saved value, or with no saved value above it,
            // may reach every slot.
            let entrySlots = slots.compactMap { offset, value -> Int64? in
                if case .entry = value { return offset }
                return nil
            }.sorted()
            let evidence = LiveEntrySaveEvidence(sortedEntryStarts: entrySlots)
            for (key, _) in registerFacts.selected(keys) {
                // Keep each selected register's transaction separate: an Any
                // input must not erase a different input's bounded ranges.
                let input = registerFacts.escapeOrigins(key)
                reach.recordEscape(input, against: evidence)
            }
        }

        mutating func invalidateSlotsForUnknownWrite(throughStackAlias: Bool) {
            incomingIntact = false
            if throughStackAlias || stackAddressEscaped {
                slots.removeAll()
                return
            }
            // Caller-owned reach is an operation policy, not a durable escape.
            let effect = reach.effect(using: NoFrameQueryEvidence(), arithmetic: .checked, includingCallerOwned: true)
            slots.forget(effect, removing: .value)
        }

        /// A saved entry value below sp occupies storage the next callee can
        /// reuse. A pointer there can also expose other slots before it is
        /// overwritten; retain that possible reach after losing the value.
        mutating func forgetCalleeStack() {
            let boundary: Int64?
            if case .stack(let top) = value("sp") { boundary = top }
            else { boundary = nil }
            var exposedFramePointer = false
            slots.forget(.calleeStack(below: boundary), removing: .value) { value in
                switch value {
                case .stack, .below: exposedFramePointer = true
                default: break
                }
            }
            if boundary.map({ $0 > 0 }) ?? true { incomingIntact = false }
            if exposedFramePointer { stackAddressEscaped = true }
        }

        mutating func invalidateSlots(at address: Int64, bytes: Int) {
            let (end, overflow) = address.addingReportingOverflow(Int64(bytes))
            guard bytes > 0, !overflow else {
                incomingIntact = false
                slots.removeAll()
                return
            }
            if end > 0 { incomingIntact = false }
            let effect = FrameMemoryEffect(.finite(lower: address, upper: end), arithmetic: .checked)
            slots.forget(effect, removing: .value)
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
        callInputs: (Instruction) -> Set<String>? = { _ in nil },
        clobbersMayAliasStack: Bool = true
    ) -> [UInt64: [String: Value]]? {
        let calleeSaved = calleeSavedKeys
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
                    || ((insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch)
                        && !internalBranch && block.switchCases == nil)
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
                    applyCall(
                        callEffect(insn), inputs: callInputs(insn), to: &state,
                        clobbersMayAliasStack: clobbersMayAliasStack)
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

    /// What a call does to the state: `effect` is the callee's, and
    /// `callInputs` the registers it can take an input in (nil when it may
    /// take any).
    @discardableResult
    static func applyCall(
        _ effect: CalleeEffect, inputs callInputs: Set<String>?, to state: inout State, clobbersMayAliasStack: Bool
    ) -> CalleeMemoryEffect.FramePlan? {
        // The callee reads its reloads before it can write anything.
        let reloaded = state.reloaded(effect)
        let memory = effect.memoryEffect.framePlan { register in
            if case .stack(let offset) = state.value(register.key) { return offset }
            return nil
        }
        // A callee may mutate any save whose address it can
        // reach. sp/x29 alone are ordinary frame bookkeeping;
        // any other frame alias can be an outgoing argument,
        // including an outlined fragment's nonstandard input.
        // A callee that keeps the calling convention (`callInputs`)
        // takes inputs only in the argument registers, x8, and
        // Swift's x20 and x21; x22 is an async context, never a
        // stack address. A frame alias parked in another
        // callee-saved register, the sp a dynamic allocation
        // restores (`mov x22, sp; …; bl String.init; mov sp,
        // x22`), is no argument to it. An outlined fragment may
        // take any register, so a call to an unknown in-image
        // target escapes every alias.
        // Borrowed Set views feed lazy selection; no compatibility Set copy.
        let inputs = state.registerFacts.aliasKeys.lazy.filter { key in
            callInputs.map { $0.contains(key) } ?? (key != "sp" && key != "x29")
        }
        if effect.readsFramePointer && state.stackAliases.contains("x29") {
            state.stackAddressEscaped = true
        }
        state.markEscape(inputs)
        if let memory {
            state.markEscape(memory.inputs.map(\.key))
            for store in memory.stores { state.invalidateSlots(at: store.start, bytes: Int(store.bytes)) }
        } else {
            state.forgetCalleeStack()
            state.invalidateSlotsForUnknownWrite(throughStackAlias: false)
        }
        // The callee keeps the ABI: x19–x29, sp and the low 64 bits of v8–v15 survive it.
        for index in 0...18 { state.setRegister("x\(index)", to: .unknown) }
        state.setRegister("x30", to: .unknown)
        for index in Array(0...7) + Array(16...31) { state.setRegister("v\(index)", to: .unknown) }
        state.apply(effect, reloaded: reloaded, clobbersMayAliasStack: clobbersMayAliasStack)
        return memory
    }

    /// The registers an unknown ABI-conforming callee may consume: general
    /// and vector arguments, x8, and Swift's x20 and x21. A double can carry
    /// pointer bits in its low word, and a short-vector parameter above that
    /// too. A known integer-only arity stays the precise path.
    static let abiCallInputs: Set<String> = Set((0...8).map { "x\($0)" } + (0...7).map { "v\($0)" } + ["x20", "x21"])

    /// The memory operand's address and the base's value after writeback.
    private static func access(_ detail: StructuredInsn, in state: State) -> (address: Int64?, base: String?, after: Value?) {
        guard let memory = detail.operands.first(where: { $0.operand.isMemory }),
              case .memory(let base?, let index, let displacement) = memory.operand, index == nil,
              case .stack(let k) = state.value(base.key)
        else { return (nil, nil, nil) }
        guard let plan = FrameCoordinatePlanner.exactAccess(
            .point(k), displacement: displacement, postIndex: detail.postIndex,
            writeback: detail.writeback, trailingImmediate: detail.operands.last?.operand.immediateValue)
        else { return (nil, nil, nil) }
        let after: Value? = if case .point(let shifted)? = plan.after { .stack(shifted) } else { nil }
        return (plan.start, base.key, after)
    }

    /// An access through an address inside a dynamic allocation below k
    /// (`Value.below`), with no index register: the highest offset it can
    /// start at, k plus a nonnegative displacement, and the base's value
    /// after writeback.
    private static func dynamicAccess(_ detail: StructuredInsn, in state: State) -> (limit: Int64, base: String, after: Value?)? {
        guard let memory = detail.operands.first(where: { $0.operand.isMemory }),
              case .memory(let base?, let index, let displacement) = memory.operand, index == nil,
              case .below(let k) = state.value(base.key)
        else { return nil }
        guard let plan = FrameCoordinatePlanner.belowAccess(
            .below(k), displacement: displacement, postIndex: detail.postIndex,
            writeback: detail.writeback, trailingImmediate: detail.operands.last?.operand.immediateValue)
        else { return nil }
        let after: Value? = if case .below(let shifted)? = plan.after { .below(shifted) } else { nil }
        return (plan.start, base.key, after)
    }

    private static func apply(_ detail: StructuredInsn, to state: inout State) {
        // SVE z registers overlap v registers, and other unmodeled register
        // groups may overlap several. Invalidate before modeled load/copy
        // paths can return, retaining possible aliases already in the bank.
        if writesUnmodeledRegister(detail) {
            let mayAliasStack = state.stackAliases.contains { $0.hasPrefix("v") }
                || !detail.readRegisterKeys.isDisjoint(with: state.stackAliases)
            for number in 0..<32 {
                state.setRegister("v\(number)", to: .unknown, mayAliasStack: mayAliasStack)
            }
        }
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
        case AARCH64_INS_MOV, AARCH64_INS_FMOV:
            // INS aliases MOV. A proven upper-half insertion does not touch
            // the low word's value, but it may add a frame address to the
            // register's independent may-alias facts.
            if operands.count == 2, let destination = register(0),
               destination.kind == .vector, destination.widthBits == 128,
               let index = operands[0].vectorIndex {
                let bits: Int
                switch operands[0].vectorArrangement {
                case AARCH64LAYOUT_VL_B: bits = 8
                case AARCH64LAYOUT_VL_H: bits = 16
                case AARCH64LAYOUT_VL_S: bits = 32
                case AARCH64LAYOUT_VL_D: bits = 64
                default: bits = 0
                }
                if bits > 0, index >= 64 / bits, index < 128 / bits {
                    if let source = register(1), state.stackAliases.contains(source.key) {
                        // One low-word value cannot bound two different lane
                        // pointers. Lose an exact low pointer rather than
                        // hide what the new upper pointer may reach.
                        switch state.value(destination.key) {
                        case .stack, .below:
                            state.setRegister(destination.key, to: .unknown, mayAliasStack: true)
                        default:
                            state.stackAliases.insert(destination.key)
                            state.aliasReach[destination.key] = nil
                        }
                    }
                    return
                }
            }
            // Full-width bit copies keep the low lane. A lane insert or a
            // narrow scalar move does not prove all 64 bits were copied.
            if let destination = register(0), let source = register(1),
               operands.allSatisfy({ $0.vectorIndex == nil }),
               (destination.widthBits == 64 && source.widthBits == 64
                || destination.kind == .vector && source.kind == .vector
                   && destination.widthBits == 128 && source.widthBits == 128) {
                state.registerFacts.copyPreservation(from: source.key, to: destination.key)
                return
            }
        case AARCH64_INS_ADD, AARCH64_INS_SUB:
            if let destination = register(0), let source = register(1), destination.widthBits == 64,
               operands.count == 3, let immediate = operands[2].shiftedImmediate,
               case .stack(let k) = state.value(source.key) {
                state.setRegister(destination.key, to: .stack(FrameCoordinatePlanner.shiftedPoint(k, by: immediate, subtracting: detail.id == AARCH64_INS_SUB)))
                return
            }
            // Within a dynamic allocation: a constant moves the bound by
            // as much at most.
            if let destination = register(0), let source = register(1), destination.widthBits == 64,
               operands.count == 3, let immediate = operands[2].shiftedImmediate,
               case .below(let k) = state.value(source.key) {
                let up = detail.id == AARCH64_INS_ADD ? max(immediate, 0) : 0
                state.setRegister(destination.key, to: .below(FrameCoordinatePlanner.shiftedPoint(k, by: up, subtracting: false)))
                return
            }
            // An address inside a dynamic allocation plus an offset in a
            // register stays inside it: `add x1, x27, x24` with x24 a field
            // offset read from metadata projects a field of the value the
            // buffer holds (the tracer's `allocationBase` reads the same).
            if detail.id == AARCH64_INS_ADD, let destination = register(0), destination.widthBits == 64,
               operands.count == 3, let lhs = register(1), let rhs = register(2) {
                let pair: (PhysReg, PhysReg)? = switch (state.value(lhs.key), state.value(rhs.key)) {
                case (.below, _): (lhs, rhs)
                case (_, .below): (rhs, lhs)
                default: nil
                }
                if let (base, offset) = pair, !state.stackAliases.contains(offset.key),
                   case .below(let k) = state.value(base.key) {
                    state.setRegister(destination.key, to: .below(k))
                    return
                }
            }
            // A stack address less a size in a register: the allocation
            // `sub x9, x9, x12` makes, below that address.
            if detail.id == AARCH64_INS_SUB, let destination = register(0), let source = register(1),
               destination.widthBits == 64, operands.count == 3, let size = register(2),
               operands[2].shift.1 == 0, !state.stackAliases.contains(size.key) {
                switch state.value(source.key) {
                case .stack(let k), .below(let k):
                    state.setRegister(destination.key, to: .below(k))
                    return
                default:
                    break
                }
            }
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP, AARCH64_INS_STNP,
             AARCH64_INS_STRB, AARCH64_INS_STURB, AARCH64_INS_STRH, AARCH64_INS_STURH:
            let (address, base, after) = access(detail, in: state)
            let count = detail.id == AARCH64_INS_STP || detail.id == AARCH64_INS_STNP ? 2 : 1
            // Even a pointer stored before a later save can expose that
            // future save. Do not tie escape lifetime to existing slot facts.
            for offset in 0..<count {
                if let source = register(offset), state.stackAliases.contains(source.key) {
                    state.markEscape([source.key])
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
                    // A GPR word or a vector's low 64 bits can save an entry
                    // value. A Q store invalidated all 16 bytes first; its
                    // upper word is not part of the low-lane proof.
                    if (bytes == 8 && source.kind == .gpr)
                        || (bytes >= 8 && source.kind == .vector) {
                        state.slots[slot] = state.value(source.key)
                    }
                }
            } else if let (limit, base, after) = dynamicAccess(detail, in: state) {
                // Inside a dynamic allocation below k: nothing at or above
                // k plus the access's own reach.
                let bytes = Int64(count * ((register(0)?.widthBits ?? 64) / 8))
                let (end, overflow) = limit.addingReportingOverflow(bytes)
                if overflow {
                    state.invalidateSlotsForUnknownWrite(throughStackAlias: true)
                } else {
                    if end > 0 { state.incomingIntact = false }
                    state.slots.forget(FrameMemoryEffect(.startsBelow(end), arithmetic: .checked), removing: .value)
                }
                if let after { state.setRegister(base, to: after) }
                return
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
                let bytes = destination.widthBits / 8
                if let address, bytes == 8 || (destination.kind == .vector && bytes == 16) {
                    state.setRegister(destination.key, to: state.load(at: address &+ Int64(offset * bytes)))
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
        let readsStackAlias = state.registerFacts.containsSelected(detail.readRegisterKeys) { key, _ in
                state.registerFacts.mayAlias(key)
            } || operands.contains { info in
                guard let reg = info.operand.register else { return false }
                return (info.isRead || info.access == 0) && state.stackAliases.contains(reg.key)
            }
        if operands.contains(where: { $0.operand.isMemory && ($0.isWritten || $0.access == 0) }), readsStackAlias {
            state.stackAddressEscaped = true
        }
        for key in writtenRegisterKeys(in: detail) {
            // The unmodeled overlapping bank was already invalidated above,
            // including aliases that an SVE register spelling cannot name.
            if writesUnmodeledRegister(detail) && key.hasPrefix("v") { continue }
            state.setRegister(key, to: .unknown, mayAliasStack: readsStackAlias)
        }
    }
}

/// Where the x20 a body was called with may live, and whether the body reads
/// it: `CalleeRegisterSummary.readsSelfRegister`.
///
/// A forward may-analysis over the CFG. The incoming x20 starts in x20 and
/// moves with the body: a 64-bit `mov` copies it to another register, an
/// eight-byte store to a known frame address spills it to that slot, and an
/// eight-byte load from such a slot (the epilogue's restore, or -Onone's
/// `str x20, [sp, #8]; ldr x20, [sp, #8]`) brings it back. Frame addresses
/// come from `Preservation`'s state, run alongside, so sp adjustments,
/// pre- and post-index writeback and x29-based addresses all resolve to
/// offsets from entry sp. Joins keep a register or slot that holds it on
/// any path.
///
/// Anything else that touches a register or slot holding it reads it: an
/// arithmetic use, a memory base or index, a narrow copy, a store to an
/// address that is not a known frame slot, a load overlapping such a slot
/// at another width, a call that takes one of those registers as an
/// input, or a `ret` with it in a result register. A load the body cannot place reads it when its address may reach
/// a slot holding it; so does a call while an escaped frame address may
/// reach one. A call to an in-image function with x20 still holding it reads
/// it only if that function does (`forwardedAt`, resolved by
/// `closeOverReads`).
extension Preservation {
    struct SelfRegisterFlow: Equatable {
        /// The body may read its incoming x20.
        var reads = false
        /// The in-image calls and tail branches, by address, where x20 may
        /// still hold it.
        var forwardedAt: Set<UInt64> = []
    }

    /// The registers a function returns its result in.
    private static let resultKeys: Set<String> = Set((0...7).map { "x\($0)" })

    private struct SelfState: Equatable {
        var frame: State
        /// Registers that may hold the incoming x20.
        var registers: Set<String> = ["x20"]
        /// Eight-byte frame slots (offsets from entry sp) that may hold it.
        var slots = MayFrameSlots()

        func merged(with other: SelfState) -> SelfState {
            SelfState(
                frame: frame.merged(with: other.frame),
                registers: registers.union(other.registers),
                slots: slots.mayUnion(with: other.slots))
        }

        /// A slot holding it overlaps `[address, address + bytes)`.
        func overlaps(_ address: Int64, bytes: Int64) -> Bool {
            slots.containsValue(affectedBy: .legacySelfRead(start: address, bytes: bytes))
        }

        /// An escaped frame address may reach a slot holding it.
        var escapeReachesSlot: Bool {
            guard !slots.isEmpty else { return false }
            if frame.reach.hasWhole { return true }
            let effect = frame.reach.effect(using: NoFrameQueryEvidence(), arithmetic: .wrapping)
            return slots.containsValue(affectedBy: effect)
        }
    }

    /// Nil when the body is not fully decoded or the fixpoint is capped:
    /// nothing is claimed then.
    ///
    /// `callInputs` gives the registers a call or tail branch can take an
    /// input in, nil when it may take any. `forwards` marks those to an
    /// in-image function of unknown arity: x20 there is judged by the
    /// target's own summary, and the call goes into `forwardedAt` instead.
    static func selfRegisterFlow(
        blocks: [BasicBlock], entry: UInt64, addresses: Set<UInt64>,
        callEffect: (Instruction) -> CalleeEffect,
        callInputs: (Instruction) -> Set<String>?,
        forwards: (Instruction) -> Bool
    ) -> SelfRegisterFlow? {
        var frame = State(registers: ["sp": .stack(0)], slots: [:])
        for index in 19...29 { frame.registers["x\(index)"] = .entry("x\(index)") }
        let blockAt = Dictionary(blocks.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        var inState: [UInt64: SelfState] = [entry: SelfState(frame: frame)]
        var flow = SelfRegisterFlow()
        var worklist = [entry]
        var visits = 0
        while let start = worklist.popLast() {
            visits += 1
            guard visits <= 64 * max(blocks.count, 1) else {
                Probe.record(.summaryCap, at: entry, ["pass": .label("self-register")])
                return nil
            }
            guard let block = blockAt[start], var state = inState[start] else { return nil }
            for insn in block.instructions {
                guard let detail = insn.detail else { return nil }
                let internalBranch = insn.branchTarget.map(addresses.contains) == true
                let isTailBranch = (insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch)
                    && !internalBranch && block.switchCases == nil
                if insn.controlFlow == .call || isTailBranch {
                    // An indirect target register is read as a value.
                    if !state.registers.isDisjoint(with: detail.readRegisterKeys) { flow.reads = true }
                    if forwards(insn) {
                        if state.registers.contains("x20") { flow.forwardedAt.insert(insn.address) }
                        // An in-image function may be an outlined fragment,
                        // which takes an input in any register.
                        if !state.registers.subtracting(["x20"]).isEmpty { flow.reads = true }
                    } else if let inputs = callInputs(insn) {
                        if !state.registers.isDisjoint(with: inputs) { flow.reads = true }
                    } else if !state.registers.isEmpty {
                        flow.reads = true
                    }
                    if isTailBranch { continue }
                    let effect = callEffect(insn)
                    let spBefore = state.frame.value("sp")
                    let memory = applyCall(effect, inputs: callInputs(insn), to: &state.frame, clobbersMayAliasStack: true)
                    if let memory {
                        // Literal stores read no old memory. A whole word
                        // replaces self there; partial writes retain MAY bits.
                        for store in memory.stores where store.bytes == 8 { state.slots.remove(store.start) }
                    } else if state.escapeReachesSlot { flow.reads = true }
                    for index in 0...18 { state.registers.remove("x\(index)") }
                    state.registers.remove("x30")
                    // A register the callee reloads from this frame holds
                    // what that slot holds. A clobbered one may still hold
                    // the value it had, so it keeps its membership.
                    for (key, offset) in effect.restores.sorted(by: { $0.key < $1.key }) {
                        var address: Int64?
                        if case .stack(let sp) = spBefore {
                            let (sum, overflow) = sp.addingReportingOverflow(offset)
                            address = overflow ? nil : sum
                        }
                        if let address, !state.overlaps(address, bytes: 8) {
                            state.registers.remove(key)
                        } else if address != nil || !state.slots.isEmpty {
                            state.registers.insert(key)
                        }
                    }
                    continue
                }
                if insn.controlFlow == .return {
                    // Returned: `mov x0, x20; …; ret` is an initializer
                    // handing back the self it was given.
                    if !state.registers.isDisjoint(with: resultKeys) { flow.reads = true }
                    continue
                }
                if transfer(detail, to: &state) { flow.reads = true }
                apply(detail, to: &state.frame)
            }
            for successor in block.successors where addresses.contains(successor) {
                let merged = inState[successor].map { $0.merged(with: state) } ?? state
                if merged != inState[successor] {
                    inState[successor] = merged
                    worklist.append(successor)
                }
            }
        }
        return flow
    }

    /// Moves the incoming x20 through one instruction that is no call or
    /// exit, with `state.frame` as it was before it. True when the
    /// instruction reads it.
    private static func transfer(_ detail: StructuredInsn, to state: inout SelfState) -> Bool {
        let operands = detail.operands
        func register(_ index: Int) -> PhysReg? {
            index < operands.count ? operands[index].operand.register : nil
        }
        var reads = false
        var memoryBase: PhysReg?
        for info in operands {
            guard case .memory(let base, let index, _) = info.operand else { continue }
            // Used as an address.
            if let base, state.registers.contains(base.key) { reads = true }
            if let index, state.registers.contains(index.key) { reads = true }
            memoryBase = base
        }
        // Whether an access the body cannot place may reach a slot holding it.
        func unplacedReachesSlot() -> Bool {
            guard !state.slots.isEmpty else { return false }
            if let memoryBase, state.frame.stackAliases.contains(memoryBase.key) { return true }
            return state.escapeReachesSlot
        }
        switch detail.id {
        case AARCH64_INS_MOV:
            if let destination = register(0), let source = register(1),
               destination.kind == .gpr, destination.widthBits == 64,
               source.kind == .gpr, source.widthBits == 64 {
                if state.registers.contains(source.key) { state.registers.insert(destination.key) }
                else { state.registers.remove(destination.key) }
                return reads
            }
        case AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STP, AARCH64_INS_STNP,
             AARCH64_INS_STRB, AARCH64_INS_STURB, AARCH64_INS_STRH, AARCH64_INS_STURH:
            let address = access(detail, in: state.frame).address
            let count = detail.id == AARCH64_INS_STP || detail.id == AARCH64_INS_STNP ? 2 : 1
            var spilled: [Int64] = []
            for offset in 0..<count {
                guard let source = register(offset) else { continue }
                let bytes: Int
                switch detail.id {
                case AARCH64_INS_STRB, AARCH64_INS_STURB: bytes = 1
                case AARCH64_INS_STRH, AARCH64_INS_STURH: bytes = 2
                default: bytes = source.widthBits / 8
                }
                let slot = address.map { $0 &+ Int64(offset * bytes) }
                if source.kind == .gpr, state.registers.contains(source.key) {
                    // A spill to a known slot moves it; anything else (a
                    // narrow store, a store into memory the body cannot
                    // place) uses its value.
                    if let slot, bytes == 8 { spilled.append(slot) } else { reads = true }
                } else if let slot, bytes == 8 {
                    // An exact overwrite ends it there; a partial one leaves
                    // the rest of it.
                    state.slots.remove(slot)
                }
            }
            state.slots.formUnion(spilled)
            // Writeback leaves an address in the base.
            for key in detail.writtenRegisterKeys { state.registers.remove(key) }
            return reads
        case AARCH64_INS_LDR, AARCH64_INS_LDUR, AARCH64_INS_LDP:
            let address = access(detail, in: state.frame).address
            let count = detail.id == AARCH64_INS_LDP ? 2 : 1
            var loaded: [(key: String, holdsIt: Bool)] = []
            for offset in 0..<count {
                guard let destination = register(offset) else { continue }
                let whole = destination.kind == .gpr && destination.widthBits == 64
                let bytes = Int64(max(destination.widthBits / 8, 1))
                if let address {
                    let start = address &+ Int64(offset) * bytes
                    if whole, state.slots.contains(start) {
                        loaded.append((destination.key, true))
                        continue
                    }
                    // Part of it, at another width or alignment.
                    if state.overlaps(start, bytes: bytes) { reads = true }
                    loaded.append((destination.key, false))
                } else if unplacedReachesSlot() {
                    if whole { loaded.append((destination.key, true)) } else { reads = true }
                } else {
                    loaded.append((destination.key, false))
                }
            }
            // Writeback leaves an address in the base.
            for key in detail.writtenRegisterKeys { state.registers.remove(key) }
            for (key, holdsIt) in loaded {
                if holdsIt { state.registers.insert(key) } else { state.registers.remove(key) }
            }
            return reads
        default:
            break
        }
        // Any other read of a register holding it uses its value.
        for info in operands {
            if case .register(let register) = info.operand, register.kind == .gpr,
               info.access == 0 || info.isRead, state.registers.contains(register.key) {
                reads = true
            }
        }
        if !state.registers.isDisjoint(with: detail.readRegisterKeys) { reads = true }
        // Any other memory read that may reach a slot holding it.
        if operands.contains(where: { $0.operand.isMemory && ($0.isRead || $0.access == 0) }) {
            if let address = access(detail, in: state.frame).address {
                // The widest access (`ld1` of four q registers) is 64 bytes.
                if state.overlaps(address, bytes: 64) { reads = true }
            } else if unplacedReachesSlot() {
                reads = true
            }
        }
        for key in detail.writtenRegisterKeys { state.registers.remove(key) }
        return reads
    }
}
