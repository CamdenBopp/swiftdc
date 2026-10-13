import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func extractedAndRotatedBitsMatchNativeInstructionsIfPresent() async throws {
    let path = "Fixtures/Sample/libExtract.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    #expect(functions.count == 42)
    let edges: [UInt64] = [0, 1, 0x80000000, UInt64(UInt32.max), 1 << 32,
                           0x0123456789abcdef, 0xfedcba9876543210, 1 << 63, .max]
    for function in functions {
        let name = String(function.symbol.dropFirst())
        let pointer = try #require(dlsym(handle, name))
        let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64, UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        let ret = try #require(function.instructions.last)
        let value = try #require(analysis.exitValues[ret.address], "\(name): \(function.instructions)")
        for high in edges {
            for low in edges {
                #expect(try ProbeValue.abstractValue(value).evaluateInteger(arguments: [high, low]) == native(high, low), "\(name)")
            }
        }
    }
}

@Test func zeroExtractIgnoresUnknownHighHalfAndRegisterRotateDeclines() throws {
    let engine = try #require(CapstoneEngine())
    for (word, width) in [(UInt32(0x93c100e0), 64), (UInt32(0x138100e0), 32), (UInt32(0x9ac12c00), 64)] {
        let bytes = [word, 0xd65f03c0].flatMap { word in (0..<4).map { UInt8((word >> ($0 * 8)) & 0xff) } }
        let instructions = engine.disassemble(Data(bytes), address: 0).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "_extract", demangledName: "extract", startAddress: 0,
                                            instructions: instructions, source: .symbol)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x1": 0]))
        if word == 0x9ac12c00 {
            #expect(analysis.exitValues[4] == nil || analysis.exitValues[4] == .unknown)
        } else {
            let value = try #require(analysis.exitValues[4])
            for input: UInt64 in [0, 1, 1 << 32, 1 << 63, .max] {
                #expect(try ProbeValue.abstractValue(value).evaluateInteger(arguments: [input]) ==
                        (width == 32 ? input & 0xffffffff : input))
            }
        }
    }
}

@Test func constantExtractFoldsToTheNativeBitPattern() throws {
    let engine = try #require(CapstoneEngine())
    // mov x0,#1; mov x1,#0xffff; extr x0,x0,x1,#1; ret
    let words: [UInt32] = [0xd2800020, 0xd29fffe1, 0x93c10400, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8((word >> ($0 * 8)) & 0xff) } }
    let instructions = engine.disassemble(Data(bytes), address: 0).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    let function = DisassembledFunction(symbol: "_constant", demangledName: "constant", startAddress: 0,
                                        instructions: instructions, source: .symbol)
    #expect(ValueTracer().analyze(function).exitValues[12] == .immediate(0x8000000000007fff))
}
