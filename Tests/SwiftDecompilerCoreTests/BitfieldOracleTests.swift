import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The tracer's value for each bitfield move, extend, negation, bit clear,
/// negated multiply, inverted move, rotated operand and register rotate in
/// `bitfield.s` against the instruction executed natively, over edge and
/// random inputs. Unmodelled, each one cleared its destination: sound, but
/// `ubfx` alone is about 1 in 700 instructions in the perf set (25,768 of
/// 18.0M), most of them Swift extracting an enum tag or spare bits.
@Test func bitfieldMovesMatchNativeInstructionsIfPresent() async throws {
    let path = "Fixtures/Sample/libBitfield.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    #expect(functions.count == 33)
    let inputs = ResearchFixtures.inputs(seed: 11)
    let pairs = zip(inputs, inputs.reversed() + [0x8000_0000_0000_0000]).map { [$0, $1] }
    for function in functions {
        let pointer = try #require(dlsym(handle, String(function.symbol.dropFirst())))
        let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64, UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        let ret = try #require(function.instructions.last)
        guard let value = analysis.exitValues[ret.address], value != .unknown else {
            Issue.record("\(function.symbol) declined"); continue
        }
        for pair in pairs {
            let traced = try ProbeValue.abstractValue(value).evaluateInteger(arguments: pair)
            #expect(traced == native(pair[0], pair[1]),
                    "\(function.symbol)(0x\(String(pair[0], radix: 16)), 0x\(String(pair[1], radix: 16))): traced 0x\(String(traced, radix: 16)), native 0x\(String(native(pair[0], pair[1]), radix: 16))")
        }
    }
}
