import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

// Evaluate the recovered bit-vector expression; the expected result comes
// independently from the native assembly in conditionalflags.s.
private func evaluateFlags(_ value: AbstractValue, arguments: [UInt64]) -> UInt64? {
    switch value {
    case .immediate(let n): return n
    case .argument(let n): return n < arguments.count ? arguments[n] : nil
    case .select(let condition, let yes, let no):
        guard let condition = evaluateFlags(condition, arguments: arguments) else { return nil }
        return evaluateFlags(condition != 0 ? yes : no, arguments: arguments)
    case .unary(.negate, let value):
        return evaluateFlags(value, arguments: arguments).map { 0 &- $0 }
    case .binary(let op, let a, let b):
        guard let a = evaluateFlags(a, arguments: arguments), let b = evaluateFlags(b, arguments: arguments) else { return nil }
        let signedA = Int64(bitPattern: a), signedB = Int64(bitPattern: b)
        switch op {
        case .subtract: return a &- b
        case .bitAnd: return a & b
        case .bitXor: return a ^ b
        case .shiftLeft: return a << b
        case .arithmeticShiftRight: return UInt64(bitPattern: signedA >> b)
        case .equal: return a == b ? 1 : 0
        case .notEqual: return a != b ? 1 : 0
        case .less: return signedA < signedB ? 1 : 0
        case .lessEqual: return signedA <= signedB ? 1 : 0
        case .greater: return signedA > signedB ? 1 : 0
        case .greaterEqual: return signedA >= signedB ? 1 : 0
        case .unsignedLess: return a < b ? 1 : 0
        case .unsignedLessEqual: return a <= b ? 1 : 0
        case .unsignedGreater: return a > b ? 1 : 0
        case .unsignedGreaterEqual: return a >= b ? 1 : 0
        default: return nil
        }
    default: return nil
    }
}

@Test func conditionalComparesAgreeWithNativeNZCVIfPresent() async throws {
    let path = "Fixtures/Sample/libConditionalFlags.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let compared = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "ccmp_")
    }
    let masks = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "flag_mask_")
    }
    try #require(compared.count == 896 && masks.count == 2)
    let edges: [UInt64] = [0, 1, 0x7fff_ffff, 0x8000_0000, 0xffff_ffff, 0x1_0000_0000,
                           0x7fff_ffff_ffff_ffff, 0x8000_0000_0000_0000, UInt64.max]
    var inputs: [[UInt64]] = []
    for a in edges { for b in edges {
        inputs.append([a, a, a, b])   // take EQ, exercise a comparison
        inputs.append([0, 1, a, b])   // take LT, exercise a comparison
        inputs.append([a, b, b, a])   // vary the incoming comparison across width/overflow boundaries
    } }
    for function in compared + masks {
        let symbol = function.symbol.hasPrefix("_") ? String(function.symbol.dropFirst()) : function.symbol
        let native = unsafeBitCast(try #require(dlsym(library, symbol)), to: (@convention(c) (UInt64, UInt64, UInt64, UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1, "x2": 2, "x3": 3]))
        let ret = try #require(function.instructions.last)
        let recovered = try #require(analysis.exitValues[ret.address], "\(symbol) declined")
        for args in inputs {
            #expect(evaluateFlags(recovered, arguments: args) == native(args[0], args[1], args[2], args[3]), "\(symbol): \(args)")
        }
    }
}
