import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let partialWriteFixture = "Fixtures/Sample/libPartialWrites.dylib"

/// Probes whose result the tracer must claim; the rest may decline.
private let claimingProbes: Set<String> = [
    "movk_argument_low", "movk_argument_high", "movk_argument_w", "movk_constant",
]

/// Each probe replaces part of a value. Whatever the tracer claims at the
/// return must be what the machine computes, for every input.
@Test func partialWritesMatchNativeExecutionIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: partialWriteFixture) else { return }
    let handle = try #require(dlopen(partialWriteFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: partialWriteFixture) }
    #expect(functions.count == 5)
    let edges: [UInt64] = [0, 1, 0xffff, 0x10000, UInt64(UInt32.max), 1 << 32,
                           0x0123456789abcdef, 0xfedcba9876543210, 1 << 63, .max]
    for function in functions {
        let name = String(function.symbol.dropFirst())
        let pointer = try #require(dlsym(handle, name))
        let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64, UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        let ret = try #require(function.instructions.last { $0.controlFlow == .return })
        guard let value = analysis.exitValues[ret.address] else {
            #expect(!claimingProbes.contains(name), "\(name) claimed nothing")
            continue
        }
        for first in edges {
            for second in edges {
                #expect(try ProbeValue.abstractValue(value).evaluateInteger(arguments: [first, second])
                    == native(first, second), "\(name): \(value) at (\(first), \(second))")
            }
        }
    }
}
