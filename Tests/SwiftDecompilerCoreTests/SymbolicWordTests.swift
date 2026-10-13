import Foundation
import Testing
@testable import SwiftDecompilerCore

private func symbolicWordFunction(_ words: [UInt32]) throws -> DisassembledFunction {
    var data = Data()
    for word in words { var little = word.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
    let engine = try #require(CapstoneEngine())
    let instructions = engine.disassemble(data, address: 0x1000).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    return DisassembledFunction(symbol: "word", demangledName: nil, startAddress: 0x1000,
                                instructions: instructions, source: .address)
}
private func predictedWord(_ words: [UInt32], input: UInt64) throws -> UInt64 {
    let function = try symbolicWordFunction(words)
    let result = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
    let returned = try #require(result.exitValues[function.instructions.last!.address])
    return try ProbeValue.abstractValue(returned).evaluateInteger(arguments: [input, 33])
}

@Test func scalarExtensionAliasesUseTheirSourceSignAndDestinationWidth() throws {
    for input: UInt64 in [0, 0x7f, 0x80, 0xff, 0x7fff, 0x8000, 0xffff,
                          0x7fffffff, 0x80000000, 0xffffffff, 0xdeadbeef80000080, .max] {
        let byte = UInt64(bitPattern: Int64(Int8(truncatingIfNeeded: input)))
        let half = UInt64(bitPattern: Int64(Int16(truncatingIfNeeded: input)))
        let word = UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: input)))
        for (encoding, expected): (UInt32, UInt64) in [
            (0x93401c00, byte), (0x93403c00, half), (0x93407c00, word),
            (0x13001c00, byte & 0xffffffff), (0x13003c00, half & 0xffffffff),
            (0x53001c00, input & 0xff), (0x53003c00, input & 0xffff)
        ] {
            #expect(try predictedWord([encoding, 0xd65f03c0], input: input) == expected)
        }
    }
}
@Test func aSymbolicWordMoveZeroExtendsIntoTheReturnRegister() throws {
    for input: UInt64 in [0, 1, UInt64(UInt32.max), 1 << 32, .max, 0xdeadbeef80000000] {
        #expect(try predictedWord([0x2a0003e0, 0xd65f03c0], input: input) == input & 0xffff_ffff)
    }
}
@Test func aSymbolicWordArithmeticWriteWrapsAt32Bits() throws {
    // add w0, w0, #1; ret. Reads alone do not prove the destination fits.
    for input: UInt64 in [0, .max, 0xffff_ffff, 0xdeadbeef80000000] {
        #expect(try predictedWord([0x11000400, 0xd65f03c0], input: input) == (input &+ 1) & 0xffff_ffff)
    }
}
@Test func aSymbolicUnsignedWordOperandIsTruncatedBeforeAnXResult() throws {
    // add x0, x1, w0, uxtw; ret. Destination is 64-bit: source must narrow.
    for input: UInt64 in [0, 1 << 32, .max, 0xdeadbeef80000000] {
        #expect(try predictedWord([0x8b204020, 0xd65f03c0], input: input) == (input & 0xffff_ffff) + 33)
    }
}

@Test func aSignedWordStackLoadSignExtendsItsStoredLowWord() throws {
    // sub sp,#16; str w0,[sp]; ldrsw x0,[sp]; add sp,#16; ret
    for input: UInt64 in [0, 0x80000000, 0xffffffff, .max, 0xdeadbeef80000000] {
        let expected = UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: input)))
        #expect(try predictedWord([0xd10043ff, 0xb90003e0, 0xb98003e0, 0x910043ff, 0xd65f03c0], input: input) == expected)
    }
}
@Test func byteStackLoadsRespectSignednessAndAccessWidth() throws {
    for input: UInt64 in [0, 0x7f, 0x80, 0xffffffff, .max] {
        #expect(try predictedWord([0xd10043ff, 0x390003e0, 0x394003e0, 0x910043ff, 0xd65f03c0], input: input) == input & 0xff)
        #expect(try predictedWord([0xd10043ff, 0x390003e0, 0x398003e0, 0x910043ff, 0xd65f03c0], input: input)
                == UInt64(bitPattern: Int64(Int8(truncatingIfNeeded: input))))
    }
}
@Test func aNarrowStackStoreDoesNotProveAnEntireWord() throws {
    let function = try symbolicWordFunction([0xd10043ff, 0x390003e0, 0xf94003e0, 0x910043ff, 0xd65f03c0])
    let result = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
    #expect(result.exitValues[function.instructions.last!.address] == nil || result.exitValues[function.instructions.last!.address] == .unknown)
}

@Test func symbolicWordSignedOperationsUseTheWordSignBit() throws {
    for input: UInt64 in [0, 0x7fffffff, 0x80000000, 0xffffffff, .max] {
        let signed = Int32(truncatingIfNeeded: input)
        #expect(try predictedWord([0x13077c00, 0xd65f03c0], input: input) == UInt64(UInt32(bitPattern: signed >> 7)))
        #expect(try predictedWord([0x1ac10c00, 0xd65f03c0], input: input) == UInt64(UInt32(bitPattern: signed / 33)))
        #expect(try predictedWord([0x8b20c020, 0xd65f03c0], input: input) == UInt64(bitPattern: Int64(signed) + 33))
    }
}
@Test func variableWordShiftsUseOnlyFiveShiftBits() throws {
    for input: UInt64 in [1, 0x80000000, 0xffffffff, .max] {
        #expect(try predictedWord([0x1ac12000, 0xd65f03c0], input: input) == (input << 1) & 0xffff_ffff)
    }
}
@Test func aPartialOverlappingStackStoreInvalidatesTheOldSnapshot() throws {
    let function = try symbolicWordFunction([0xd10043ff, 0xf90003e0, 0x390007e1, 0xf94003e0, 0x910043ff, 0xd65f03c0])
    let result = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
    #expect(result.exitValues[function.instructions.last!.address] == nil || result.exitValues[function.instructions.last!.address] == .unknown)
    #expect(try predictedWord([0xd10043ff, 0xf90003e0, 0x390023e1, 0xf94003e0, 0x910043ff, 0xd65f03c0], input: .max) == .max)
}
