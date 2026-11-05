import Ccapstone
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func iteratorBytes(_ words: [UInt32]) -> Data {
    Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
}

private func iteratorCString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
}

/// Independent allocation path through the pinned C library. It deliberately
/// keeps the former batch API as the compatibility reference, not as a second
/// production decoder mode.
private func batchReference(_ code: Data, address: UInt64, text: Bool) throws -> [DecodedInstruction] {
    var handle: csh = 0
    try #require(cs_open(CS_ARCH_AARCH64, CS_MODE_LITTLE_ENDIAN, &handle) == CS_ERR_OK)
    defer { cs_close(&handle) }
    try #require(cs_option(handle, CS_OPT_DETAIL, UInt(CS_OPT_ON.rawValue)) == CS_ERR_OK)
    var result: [DecodedInstruction] = []
    code.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        var offset = 0
        while offset < code.count {
            var records: UnsafeMutablePointer<cs_insn>?
            let count = cs_disasm(handle, bytes + offset, code.count - offset, address &+ UInt64(offset), 4096, &records)
            if count > 0, let records {
                for index in 0..<count {
                    let pointer = records + index
                    let record = pointer.pointee
                    let detail = StructuredInsn.decode(record)
                    func group(_ value: cs_group_type) -> Bool { cs_insn_group(handle, pointer, UInt32(value.rawValue)) }
                    let flow: ControlFlow
                    if group(CS_GRP_RET) { flow = .return }
                    else if group(CS_GRP_CALL) { flow = .call }
                    else if !group(CS_GRP_JUMP) { flow = .sequential }
                    else if let detail {
                        let compare = [AARCH64_INS_CBZ, AARCH64_INS_CBNZ, AARCH64_INS_TBZ, AARCH64_INS_TBNZ].contains(detail.id)
                        flow = compare || ![AArch64CC_Invalid, AArch64CC_AL, AArch64CC_NV].contains(detail.conditionCode)
                            ? .conditionalBranch : .branch
                    } else { flow = .conditionalBranch }
                    let target = [.branch, .conditionalBranch, .call].contains(flow)
                        ? detail?.branchTargetOperand.map(UInt64.init(bitPattern:)) : nil
                    result.append(DecodedInstruction(address: record.address, size: Int(record.size),
                        mnemonic: text ? iteratorCString(record.mnemonic) : "",
                        operands: text ? iteratorCString(record.op_str) : "",
                        controlFlow: flow, branchTarget: target, detail: detail))
                }
                let last = records[count - 1]
                offset += max(Int(last.address &- (address &+ UInt64(offset))) + Int(last.size), 4)
                cs_free(records, count)
            } else {
                if let records { cs_free(records, 0) }
                offset += 4
            }
        }
    }
    return result
}

/// Compare every field the production pipeline retains. Floating values use
/// their exact bits so NaNs and signed zero do not defeat equality.
private func iteratorFingerprint(_ instruction: DecodedInstruction) -> [String] {
    func register(_ value: PhysReg?) -> String {
        value.map { "\($0.kind.rawValue):\($0.number):\($0.widthBits)" } ?? "nil"
    }
    var fields = [String(instruction.address), String(instruction.size), instruction.mnemonic,
                  instruction.operands, instruction.controlFlow.rawValue,
                  instruction.branchTarget.map(String.init) ?? "nil"]
    guard let detail = instruction.detail else { return fields + ["no-detail"] }
    fields += [String(detail.id.rawValue), String(detail.conditionCode.rawValue),
               String(detail.updatesFlags), String(detail.writeback), String(detail.postIndex)]
    for operand in detail.operands {
        switch operand.operand {
        case .register(let value): fields += ["reg", register(value)]
        case .immediate(let value): fields += ["imm", String(value)]
        case .floatingPoint(let value): fields += ["fp", String(value.bitPattern)]
        case .memory(let base, let index, let offset): fields += ["mem", register(base), register(index), String(offset)]
        case .other: fields += ["other"]
        }
        fields += [String(operand.shift.type.rawValue), String(operand.shift.amount),
                   String(operand.extender.rawValue), String(operand.access),
                   operand.vectorIndex.map(String.init) ?? "nil", String(operand.vectorArrangement.rawValue)]
    }
    return fields
}

@Test func capstoneIteratorPreservesBatchSemanticsAndOwnedResultsAcrossCalls() throws {
    let engine = try #require(CapstoneEngine())
    // Aliases, NZCV, shifts/extensions, scalar/packed widths, low/high lanes,
    // pre/post indexing, PAC/arm64e control flow, SVE/SME and invalid slots.
    let matrix: [UInt32] = [0x91000420, 0x11000420, 0x910043ff, 0xf100041f,
        0xf2800020, 0x54000060, 0x9a820020, 0xfa410000, 0xfc1f0fe8, 0x3cc107e8,
        0x4e181d28, 0x9eaf0128, 0x6f00e408, 0x1e6e1000, 0xd71f0a11, 0xd61f091f,
        0xd63f0100, 0xd503233f, 0xd65f0bff, 0x25f8c008, 0x858043e8, 0xc00800ff,
        0xffffffff, 0xdeadbeef, 0xd503201f, 0xd65f03c0]
    var random: UInt32 = 0x12345678
    let words: [UInt32] = (0..<512).map { _ in random = random &* 1664525 &+ 1013904223; return random }
    let cases = [Data(), iteratorBytes(matrix), iteratorBytes(matrix) + Data([1, 2, 3]),
                 iteratorBytes(words), (Data([0xaa]) + iteratorBytes(matrix)).dropFirst()]
    let retained = engine.disassemble(iteratorBytes(matrix), address: 0x1000)
    let retainedFields = retained.map(iteratorFingerprint)
    for address: UInt64 in [0, 0x1000, .max - 3] {
        for text in [true, false] {
            for code in cases {
                let actual = engine.disassemble(code, address: address, includeText: text)
                let expected = try batchReference(code, address: address, text: text)
                #expect(actual.count == expected.count)
                for (a, b) in zip(actual, expected) {
                    #expect(iteratorFingerprint(a) == iteratorFingerprint(b), Comment(rawValue: "at \(a.address)"))
                }
            }
        }
    }
    // Reusing the C record cannot mutate earlier calls' Swift arrays/strings.
    #expect(retained.map(iteratorFingerprint) == retainedFields)
}
