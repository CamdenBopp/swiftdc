import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func scalarByteReversalMatchesNativeInstructionsIfPresent() async throws {
    let path = "Fixtures/Sample/libByteReversal.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    #expect(functions.count == 5)
    let inputs = ResearchFixtures.inputs(seed: 7)
    for function in functions {
        let pointer = try #require(dlsym(handle, String(function.symbol.dropFirst())))
        let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        let ret = try #require(function.instructions.last)
        let value = try #require(analysis.exitValues[ret.address])
        for input in inputs {
            #expect(try ProbeValue.abstractValue(value).evaluateInteger(arguments: [input]) == native(input), "\(function.symbol)")
        }
    }
}
