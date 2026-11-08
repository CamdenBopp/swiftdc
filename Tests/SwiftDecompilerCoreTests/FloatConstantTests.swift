import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A float operation's constant operand is an IEEE bit pattern, and the
/// renderer read it as one only beside a float argument, a conversion or a
/// Swift call returning a float. Beside a C call's double it printed the
/// integer it is spelled as: `float_constants.c` (-O2) rendered
/// `glVertex2d((CFAbsoluteTimeGetCurrent() / 0x4059000000000000), 0.5)`,
/// an integer divide by 4.6e18.
@Test func aFloatOperationsConstantRendersAsItsDecimalIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatConstants.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func statements(_ name: String) throws -> [String] {
        let text = try #require(functions.first { $0.displayName == name }).renderPseudo()
        return text.components(separatedBy: "\n").dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "}" }
    }
    #expect(try statements("_scaledTime") == ["glVertex2d((CFAbsoluteTimeGetCurrent() / 100.0), 0.5)"])
    #expect(try statements("_quarterTime") == ["glVertex2d((CFAbsoluteTimeGetCurrent() * 0.25), 2.0)"])
}

/// Only an immediate read from a float register is a bit pattern. `scvtf
/// d0, w8` converts the integer in w8, so `mov w8, #5` stays the integer 5;
/// `fcvt s0, d2` converts the double in d2, so the 100.0 moved there from x9
/// is a float constant.
@Test func onlyAFloatRegistersImmediateIsAFloatConstant() throws {
    let engine = try #require(CapstoneEngine())
    func exit(_ words: [UInt32]) -> AbstractValue? {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil,
                        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        return ValueTracer().analyze(function, entry: nil).exitFloatValues[body.last!.address]
    }
    // mov w8, #5; scvtf d0, w8; ret
    #expect(exit([0x528000a8, 0x1e620100, 0xd65f03c0]) == .unary(.toFloat(bits: 64), .immediate(5)))
    // mov x9, #0x4059000000000000; fmov d2, x9; fcvt s0, d2; ret
    #expect(exit([0xd2e80b29, 0x9e670122, 0x1e624040, 0xd65f03c0])
        == .unary(.toFloat(bits: 32), .unary(.floatConstant(bits: 64), .immediate(0x4059000000000000))))
}
