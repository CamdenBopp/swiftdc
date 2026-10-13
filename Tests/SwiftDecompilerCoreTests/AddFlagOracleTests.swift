import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func symbolicAdditionConditionsAgreeWithNativeNZCVIfPresent() async throws {
    let path = "Fixtures/Sample/libAddFlags.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path)
    }
    #expect(functions.count == 104)
    let edges: [UInt64] = [0, 1, 11, 0x7fffffff, 0x80000000, 0xffffffff, 1 << 32,
                           0x7fffffffffffffff, 0x8000000000000000, 0xfffffffffffffff5, .max]
    for function in functions {
        let pointer = try #require(dlsym(library, String(function.symbol.dropFirst())))
        let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64, UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        let ret = try #require(function.instructions.last)
        let value = try #require(analysis.exitValues[ret.address], "\(function.symbol) declined")
        for a in edges { for b in edges {
            let predicted = try ProbeValue.abstractValue(value).evaluateInteger(arguments: [a, b])
            #expect(predicted == native(a, b), "\(function.symbol): \(a), \(b)")
        } }
    }
}
