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
                let mnemonic = Self.string(insn.mnemonic)
                let operands = Self.string(insn.op_str)
                let flow = controlFlow(of: pointer, mnemonic: mnemonic)
                results.append(
                    DecodedInstruction(
                        address: insn.address,
                        size: Int(insn.size),
                        mnemonic: mnemonic,
                        operands: operands,
                        controlFlow: flow,
                        branchTarget: (flow == .branch || flow == .conditionalBranch || flow == .call)
                            ? Self.lastHex(in: operands) : nil
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

    private func controlFlow(of pointer: UnsafePointer<cs_insn>, mnemonic: String) -> ControlFlow {
        if inGroup(pointer, CS_GRP_RET) { return .return }
        if inGroup(pointer, CS_GRP_CALL) { return .call }
        if inGroup(pointer, CS_GRP_JUMP) {
            // Unconditional `b`/`br` vs. conditional (`b.eq`, `cbz`, `tbnz`, …).
            return (mnemonic == "b" || mnemonic == "br") ? .branch : .conditionalBranch
        }
        return .sequential
    }

    /// Convert a fixed-size C char array (imported as a tuple) to a String.
    private static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    /// The last `0x…` hex value in an operand string (the branch target in
    /// `b 0x…`, `cbz x0, 0x…`, `tbz w0, #3, 0x…`).
    private static func lastHex(in operands: String) -> UInt64? {
        var result: UInt64?
        var scalars = Substring(operands)
        while let range = scalars.range(of: "0x") {
            let hex = scalars[range.upperBound...].prefix { $0.isHexDigit }
            if let value = UInt64(hex, radix: 16) { result = value }
            scalars = scalars[range.upperBound...]
        }
        return result
    }
}
