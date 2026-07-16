import Foundation
import CCapstone

/// Control-flow classification of an instruction, from Capstone's instruction
/// groups. This is the structural information `llvm-objdump` text doesn't give.
public enum ControlFlow: String, Sendable {
    case sequential
    case branch             // unconditional (b, br)
    case conditionalBranch  // b.cond, cbz/cbnz, tbz/tbnz
    case call               // bl, blr
    case `return`           // ret
}

/// A structurally-decoded ARM64 instruction.
public struct DecodedInstruction: Sendable {
    public let address: UInt64
    public let size: Int
    public let mnemonic: String
    public let operands: String
    public let controlFlow: ControlFlow
    /// Resolved absolute target for direct branches/calls, when statically known.
    public let branchTarget: UInt64?
    /// Structured operands from Capstone's detail mode. Nil only if detail is
    /// unavailable.
    public let detail: StructuredInsn?

    /// `mnemonic` + `operands` as a single assembly string.
    public var text: String { operands.isEmpty ? mnemonic : "\(mnemonic)\t\(operands)" }
}

/// Thin wrapper over the Capstone C library for in-process ARM64 decoding.
///
/// Decodes raw `__text` bytes directly (no subprocess), and — unlike parsing
/// objdump text — yields each instruction's control-flow class and branch
/// target, the foundation for basic-block / CFG recovery.
final class CapstoneEngine {
    private var handle: csh = 0
    private let opened: Bool

    init?() {
        opened = cs_open(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN, &handle) == CS_ERR_OK
        guard opened else { return nil }
        // Detail mode is required for cs_insn_group (control-flow groups).
        _ = cs_option(handle, CS_OPT_DETAIL, Int(CS_OPT_ON.rawValue))
    }

    deinit {
        if opened { cs_close(&handle) }
    }

    /// Disassemble `code` as ARM64 starting at virtual address `address`.
    func disassemble(_ code: Data, address: UInt64) -> [DecodedInstruction] {
        guard opened, !code.isEmpty else { return [] }
        var results: [DecodedInstruction] = []

        code.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var insns: UnsafeMutablePointer<cs_insn>?
            let count = cs_disasm(handle, base, code.count, address, 0, &insns)
            guard count > 0, let insns else { return }
            defer { cs_free(insns, count) }

            results.reserveCapacity(count)
            for index in 0..<count {
                let pointer = insns + index
                let insn = pointer.pointee
                let detail = StructuredInsn.decode(insn)
                let flow = controlFlow(of: pointer, detail: detail)
                // The branch target is the last immediate operand — true for
                // every direct form (`b 0x…`, `cbz x0, 0x…`, `tbz w0, #3, 0x…`),
                // and absent for indirect ones, which is exactly right.
                let target: UInt64? = (flow == .branch || flow == .conditionalBranch || flow == .call)
                    ? detail?.branchTargetOperand.map(UInt64.init(bitPattern:))
                    : nil
                results.append(
                    DecodedInstruction(
                        address: insn.address,
                        size: Int(insn.size),
                        mnemonic: Self.string(insn.mnemonic),
                        operands: Self.string(insn.op_str),
                        controlFlow: flow,
                        branchTarget: target,
                        detail: detail
                    )
                )
            }
        }
        return results
    }

    // MARK: - Helpers

    private func inGroup(_ pointer: UnsafePointer<cs_insn>, _ group: cs_group_type) -> Bool {
        cs_insn_group(handle, pointer, UInt32(group.rawValue))
    }

    /// A jump is conditional iff it carries a real condition code, or is one of
    /// the compare-and-branch forms (which encode their condition in the opcode
    /// rather than in `cc`).
    ///
    /// This replaced a mnemonic denylist (`mnemonic == "b" || mnemonic == "br"`)
    /// that misclassified every pointer-auth branch — `braa`, `braaz`, `brab`,
    /// `brabz` — as conditional. Those are unconditional indirect tail calls, and
    /// calling them conditional made `CFG.successors` invent a fall-through edge
    /// that does not exist, on every arm64e stub island and tail call. arm64e is
    /// the default for shipping Apple binaries, so this was wrong nearly
    /// everywhere it mattered.
    private static let compareAndBranch: Set<UInt32> = [
        ARM64_INS_CBZ, ARM64_INS_CBNZ, ARM64_INS_TBZ, ARM64_INS_TBNZ,
    ].map(\.rawValue).reduce(into: Set()) { $0.insert($1) }

    private func controlFlow(of pointer: UnsafePointer<cs_insn>, detail: StructuredInsn?) -> ControlFlow {
        if inGroup(pointer, CS_GRP_RET) { return .return }
        if inGroup(pointer, CS_GRP_CALL) { return .call }
        guard inGroup(pointer, CS_GRP_JUMP) else { return .sequential }
        guard let detail else { return .conditionalBranch } // no detail: assume the weaker claim
        if Self.compareAndBranch.contains(detail.id.rawValue) { return .conditionalBranch }
        let cc = detail.conditionCode
        let conditional = cc != ARM64_CC_INVALID && cc != ARM64_CC_AL && cc != ARM64_CC_NV
        return conditional ? .conditionalBranch : .branch
    }

    /// Convert a fixed-size C char array (imported as a tuple) to a String.
    private static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

}
