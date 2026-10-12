import Ccapstone
import Foundation

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
    /// Argument registers x0…x7 (by number) the body may read before writing
    /// them on some path from its entry. A call or tail call inside counts as
    /// reading every one not yet written, since it may pass them on.
    let argumentReads: Set<Int>
    /// Callee-saved registers (`x19`…`x29`) the body writes but never stores
    /// anywhere: not preserved for the caller. A function that follows the
    /// ABI spills each one it uses in its prologue.
    let clobberedCalleeSaved: Set<String>

    /// The integer arguments a call to this function can pass: through the
    /// highest argument register it reads. Unread registers below that are
    /// positional parameters it ignores.
    var argumentCount: Int { (argumentReads.max() ?? -1) + 1 }

    private static let argumentKeys = (0...7).map { "x\($0)" }
    private static let calleeSavedKeys = Set((19...29).map { "x\($0)" })

    /// Nil when any instruction lacks structured detail: nothing is claimed
    /// about a body that was not fully decoded.
    static func of(_ function: DisassembledFunction) -> CalleeRegisterSummary? {
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
        var worklist = [entry]
        var visits = 0
        while let start = worklist.popLast() {
            visits += 1
            // A pathological CFG must not hang the summary; giving up claims
            // nothing (every caller keeps its positional arguments).
            guard visits <= 64 * max(blocks.count, 1), let block = blockAt[start] else { return nil }
            var written = inState[start] ?? []
            for insn in block.instructions {
                guard let detail = insn.detail else { return nil }
                func read(_ key: String) {
                    if let index = argumentKeys.firstIndex(of: key), !written.contains(key) { reads.insert(index) }
                }
                let internalBranch = insn.branchTarget.map(addresses.contains) == true
                let leavesThroughCall = insn.controlFlow == .call
                    || (insn.controlFlow == .branch && !internalBranch && block.switchCases == nil)
                if leavesThroughCall {
                    // The callee may read any argument register still holding
                    // this function's incoming value.
                    argumentKeys.forEach(read)
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
                written.formUnion(detail.writtenRegisterKeys.intersection(argumentKeys))
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
        for insn in instructions {
            guard let detail = insn.detail else { return nil }
            writtenCalleeSaved.formUnion(detail.writtenRegisterKeys.intersection(calleeSavedKeys))
            if detail.operands.contains(where: { $0.operand.isMemory }) {
                for info in detail.operands {
                    if case .register(let register) = info.operand, info.isRead,
                       calleeSavedKeys.contains(register.key) {
                        storedCalleeSaved.insert(register.key)
                    }
                }
            }
        }
        return CalleeRegisterSummary(
            argumentReads: reads,
            clobberedCalleeSaved: writtenCalleeSaved.subtracting(storedCalleeSaved)
        )
    }
}
