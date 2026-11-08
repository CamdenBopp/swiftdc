import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func chainedSelectsFollowGraphDependenciesInsteadOfAddressOrderIfPresent() async throws {
    let path = "Fixtures/Sample/libSelectFlow.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    #expect(functions.count == 3)
    for name in ["forward", "shuffled"] {
        let function = try #require(functions.first { $0.symbol == "_selectflow_\(name)" })
        let pointer = try #require(dlsym(handle, "selectflow_\(name)"))
        let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        let ret = try #require(function.instructions.first { $0.controlFlow == .return })
        let value = try #require(analysis.exitValues[ret.address])
        for input: UInt64 in [0, 6, 7, 8, 18, 19, 20, 1 << 32, 1 << 63, .max] {
            #expect(try ProbeValue.abstractValue(value).evaluateInteger(arguments: [input]) == native(input))
        }
    }
    let cycle = try #require(functions.first { $0.symbol == "_selectflow_cycle" })
    let analysis = ValueTracer().analyze(cycle, entry: .swiftFunction(scalarArguments: ["x0": 0]))
    let ret = try #require(cycle.instructions.last)
    #expect(analysis.exitValues[ret.address] == nil || analysis.exitValues[ret.address] == .unknown)
}
