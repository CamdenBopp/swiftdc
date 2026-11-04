import Ccapstone
import Foundation

/// A fragment LLVM's machine outliner moved out of its callers (`-Osize`
/// Swift, `-Oz` C): a few straight-line instructions reached by `bl` or `b`
/// that end in `ret` or a tail branch, and keep no calling convention. Inputs
/// arrive in any register (w8, x19), results leave in any register (x1), and
/// callee-saved registers and sp are rewritten for the caller: `add x20, sp,
/// #8; b Hasher._finalize` hands `_finalize` its `self`, and `ldp x20, x19,
/// [sp, #0x50]; add sp, sp, #0x70; ret` is a caller's epilogue. Rendered as a
/// call, `ReconError.hashValue` read `OUTLINED_FUNCTION_36();
/// Hasher._combine(0); OUTLINED_FUNCTION_9(OUTLINED_FUNCTION_35())` where the
/// source is `Hasher(_seed: 0)`, `_combine`, `_finalize`.
///
/// A call site whose fragment the tracer can model whole is rewritten to
/// what the fragment does there (`plan`): the instructions before its
/// terminator run in the caller's tracer at the site, and the site becomes
/// the fragment's call, tail call, last instruction or return. Anything the
/// model cannot carry exactly keeps the call as it was.
struct OutlinedFragment: Sendable {
    let start: UInt64
    /// The straight-line instructions before the terminator.
    let body: [Instruction]
    /// `ret` (through x30), or a direct `b` out: a tail call.
    let terminator: Instruction

    /// Longer bodies stay calls. LLVM outlines sequences of two or more
    /// instructions; the longest of the Reconstruction fixture's 39 is 9.
    static let maximumBody = 12

    /// Nil unless `instructions` (decoded from `start`) begin with at most
    /// `maximumBody` straight-line instructions, every one decoded, and then
    /// a `ret` or a direct unconditional `b`.
    init?(start: UInt64, instructions: [Instruction]) {
        guard instructions.first?.address == start else { return nil }
        var body: [Instruction] = []
        for insn in instructions {
            guard let detail = insn.detail, !insn.isTrap else { return nil }
            switch insn.controlFlow {
            case nil, .sequential?:
                guard body.count < Self.maximumBody else { return nil }
                body.append(insn)
            case .return?:
                // `ret` through x30, not `ret x9`.
                guard detail.id == AARCH64_INS_RET,
                      detail.operands.allSatisfy({ $0.operand.register.map { $0.kind == .gpr && $0.number == 30 } ?? true })
                else { return nil }
                self.start = start
                self.body = body
                self.terminator = insn
                return
            case .branch?:
                guard insn.branchTarget != nil, detail.conditionCode == AArch64CC_Invalid else { return nil }
                self.start = start
                self.body = body
                self.terminator = insn
                return
            default:
                return nil
            }
        }
        return nil
    }

    var isTailCall: Bool { terminator.controlFlow == .branch }

    /// The body does what no AAPCS64 function does on entry, so it is no
    /// function of its own: a stripped binary has lost the
    /// `OUTLINED_FUNCTION_n` name, and this is the evidence left. It reads a
    /// register the convention gives no incoming value (x9–x19, x23–x29;
    /// x20–x22 are Swift's self, error and async context, x8 the indirect
    /// result), writes a callee-saved register (x19–x29) it never saved, or
    /// uses sp before any `sub sp` or pre-indexed push made a frame of its
    /// own: the caller's frame.
    var breaksCallingConvention: Bool {
        var written = Set<Int>()
        var saved = Set<Int>()
        var ownFrame = false
        for insn in body + [terminator] {
            guard let detail = insn.detail else { return false }
            var readsSP = false
            var writesSP = false
            for info in detail.operands {
                switch info.operand {
                case .register(let register):
                    if register.kind == .stackPointer {
                        if info.isRead { readsSP = true }
                        if info.isWritten { writesSP = true }
                    } else if register.kind == .gpr, info.isRead, !written.contains(register.number) {
                        if (9...19).contains(register.number) || (23...29).contains(register.number) { return true }
                    }
                case .memory(let base, let index, _):
                    if base?.kind == .stackPointer { readsSP = true }
                    for register in [base, index].compactMap({ $0 }) where register.kind == .gpr {
                        if !written.contains(register.number),
                           (9...19).contains(register.number) || (23...29).contains(register.number) { return true }
                    }
                default:
                    break
                }
            }
            let stores = detail.operands.contains { $0.operand.isMemory && $0.isWritten }
            if stores {
                for info in detail.operands where info.isRead {
                    if case .register(let register) = info.operand, register.kind == .gpr { saved.insert(register.number) }
                }
            }
            if readsSP || writesSP, !ownFrame {
                // A frame of its own starts with sp moved down: `sub sp, sp,
                // #k` or a pre-indexed push with a negative offset.
                let pushes = detail.writeback && !detail.postIndex && detail.operands.contains {
                    if case .memory(let base?, _, let displacement) = $0.operand {
                        base.kind == .stackPointer && displacement < 0
                    } else { false }
                }
                if detail.id == AARCH64_INS_SUB && writesSP || pushes { ownFrame = true } else { return true }
            }
            for key in detail.writtenRegisterKeys {
                guard key.hasPrefix("x"), let number = Int(key.dropFirst()) else { continue }
                if (19...29).contains(number), !saved.contains(number) { return true }
                written.insert(number)
            }
        }
        return false
    }

    /// What a call site reaching the fragment becomes.
    struct Plan {
        /// The instruction the site now is: the fragment's call or tail call,
        /// its last instruction, or its return, at the site's address.
        let visible: Instruction
        /// The fragment's instructions before `visible`, at the site's
        /// address, for the tracer to run first.
        let prefix: [Instruction]
        /// The general registers the prefix writes.
        let prefixWrites: Set<String>
        /// The kind of site, for the probe: call, tail-call, value, store or return.
        let kind: String
    }

    enum Outcome {
        case inlined(Plan)
        case declined(String)
    }

    /// The model of the fragment at `site`, a `bl` (`reachedByCall`) or a `b`
    /// to it, or why there is none. `annotated` is the body and terminator
    /// with the names the caller's own passes would give them; `name` is how
    /// the site's note names the fragment.
    ///
    /// - A `bl` to a fragment that tail-calls T is a call to T, its body run
    ///   first. Neither half may store, load, move sp, or touch x30, x21 or
    ///   x22, which no pass outside the tracer would see.
    /// - A `b` to it is a tail call to T, and may also restore the caller's
    ///   registers and pop its frame (loads through sp, sp moved up).
    /// - A `bl` to a fragment that returns is its last instruction, the rest
    ///   run first: those may only move values between registers below x19.
    /// - A `b` to one is the caller's return, the body an epilogue: loads
    ///   through sp and sp moved, nothing that writes a result register.
    func plan(
        site: Instruction, reachedByCall: Bool, annotated: OutlinedFragment, name: String,
        isFragment: (UInt64) -> Bool
    ) -> Outcome {
        let body = annotated.body
        let terminator = annotated.terminator
        let instructions = body + [terminator]
        guard instructions.allSatisfy({ $0.detail != nil }) else { return .declined("undecoded") }
        // x30 holds the return into the caller (`bl`), or the caller's own
        // return address after its epilogue (`b`): only `ret` reads it.
        for insn in body {
            guard let detail = insn.detail else { return .declined("undecoded") }
            let keys = detail.readRegisterKeys.union(detail.writtenRegisterKeys)
            if detail.readRegisterKeys.contains("x30") { return .declined("link-register") }
            if reachedByCall, detail.writtenRegisterKeys.contains("x30") { return .declined("link-register") }
            if keys.contains("x21") || keys.contains("x22") { return .declined("error-or-context-register") }
        }
        if let target = terminator.branchTarget, isTailCall {
            if target == start || isFragment(target) { return .declined("chained") }
        }
        func stores(_ insn: Instruction) -> Bool {
            insn.detail?.operands.contains { $0.operand.isMemory && $0.isWritten } ?? true
        }
        func accessesMemory(_ insn: Instruction) -> Bool {
            insn.detail?.operands.contains { $0.operand.isMemory } ?? true
        }
        func loadsThroughSPOnly(_ insn: Instruction) -> Bool {
            guard let detail = insn.detail else { return false }
            return detail.operands.allSatisfy {
                if case .memory(let base, let index, _) = $0.operand {
                    !$0.isWritten && base?.kind == .stackPointer && index == nil
                } else { true }
            }
        }
        func writesSP(_ insn: Instruction) -> Bool { insn.detail?.writtenRegisterKeys.contains("sp") ?? true }
        func writes(_ insns: [Instruction]) -> Set<String> {
            insns.reduce(into: Set<String>()) { $0.formUnion($1.detail?.writtenRegisterKeys ?? []) }
        }
        func calleeSaved(_ keys: Set<String>) -> Bool {
            keys.contains { key in key.hasPrefix("x") && Int(key.dropFirst()).map { (19...29).contains($0) } == true }
        }
        // The listing shows what the site does; the note says what it is.
        let note = "inlined \(reachedByCall ? "bl" : "b") \(name)"
        func rebased(_ insn: Instruction) -> Instruction {
            Instruction(address: site.address, text: insn.text, annotation: insn.annotation,
                        controlFlow: insn.controlFlow, branchTarget: insn.branchTarget, detail: insn.detail,
                        callee: .kept(insn.callee))
        }
        var origin = Instruction.Facts()
        origin.inlinedFragment = Instruction.InlinedFragment(address: start, reachedByCall: reachedByCall)

        func writesFloatArgument(_ insn: Instruction) -> Bool {
            insn.detail?.operands.contains { info in
                info.isWritten && info.operand.register.map { $0.kind == .vector && $0.number < 8 } == true
            } ?? true
        }
        if isTailCall {
            // An untyped send counts the v registers written before it in
            // the caller's own block (`setsFloatingPointArgument`), and a
            // prefix is in no block.
            if body.contains(where: writesFloatArgument) { return .declined("float-argument") }
            if reachedByCall {
                if body.contains(where: accessesMemory) { return .declined("memory") }
                if body.contains(where: writesSP) { return .declined("stack-pointer") }
            } else {
                if body.contains(where: { accessesMemory($0) && !loadsThroughSPOnly($0) }) { return .declined("memory") }
            }
            // `bl T` where the fragment says `b T`: the same target and name.
            let mnemonic = terminator.text.prefix { !$0.isWhitespace }
            guard mnemonic == "b" else { return .declined("terminator") }
            let text = reachedByCall ? "bl" + terminator.text.dropFirst() : terminator.text
            let annotation = [terminator.annotation, note].compactMap { $0 }.joined(separator: "  ")
            let visible = Instruction(
                address: site.address, text: text, annotation: annotation,
                controlFlow: reachedByCall ? .call : .branch, branchTarget: terminator.branchTarget,
                detail: reachedByCall ? site.detail : terminator.detail,
                callee: .kept(terminator.callee), facts: origin)
            return .inlined(Plan(visible: visible, prefix: body.map(rebased), prefixWrites: writes(body),
                                 kind: reachedByCall ? "call" : "tail-call"))
        }
        if reachedByCall {
            guard let last = body.last else { return .declined("empty") }
            let prefix = Array(body.dropLast())
            if prefix.contains(where: accessesMemory) { return .declined("memory") }
            if calleeSaved(writes(prefix)) || writes(prefix).contains("sp") { return .declined("callee-saved") }
            if writesSP(last) { return .declined("stack-pointer") }
            if stores(last), let detail = last.detail, !ValueTracer.plainStoreIDs.contains(detail.id.rawValue) {
                return .declined("memory")
            }
            let annotation = [last.annotation, note].compactMap { $0 }.joined(separator: "  ")
            let visible = Instruction(
                address: site.address, text: last.text, annotation: annotation,
                controlFlow: last.controlFlow, branchTarget: nil, detail: last.detail,
                callee: .kept(nil), facts: origin)
            return .inlined(Plan(visible: visible, prefix: prefix.map(rebased), prefixWrites: writes(prefix),
                                 kind: stores(last) ? "store" : "value"))
        }
        // The caller's epilogue: what it restores, then its return.
        if body.contains(where: { accessesMemory($0) && !loadsThroughSPOnly($0) }) { return .declined("memory") }
        let resultRegisters = Set((0...8).map { "x\($0)" })
        if !writes(body).isDisjoint(with: resultRegisters)
            || body.contains(where: { $0.detail?.operands.contains { info in
                info.isWritten && info.operand.register.map { $0.kind == .vector && $0.number < 8 } == true } ?? true }) {
            return .declined("result-register")
        }
        let annotation = [terminator.annotation, note].compactMap { $0 }.joined(separator: "  ")
        let visible = Instruction(
            address: site.address, text: terminator.text, annotation: annotation,
            controlFlow: .return, detail: terminator.detail, callee: .kept(nil), facts: origin)
        return .inlined(Plan(visible: visible, prefix: body.map(rebased), prefixWrites: writes(body), kind: "return"))
    }

}
