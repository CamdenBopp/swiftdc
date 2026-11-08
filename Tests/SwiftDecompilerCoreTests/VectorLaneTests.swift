import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `movi v0.2d, #0` is how clang and Swift make every floating zero, and it
/// writes all 128 bits, which the tracer holds as two eight-byte lanes. A
/// scalar read of the register (`str d0`, a Double argument, a Double
/// return) took the whole pair, so a single 0.0 rendered as the tuple
/// `(0, 0)`. Each view is now the low lane.
private func pseudo(_ fixture: String, _ name: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: fixture) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: name)
    }
    return functions.map { $0.renderPseudo() }.joined(separator: "\n")
}

/// `movi v0.2d, #0; str d0, [x8]` stores one eight-byte variadic slot.
/// -O2 stores `xzr` instead and is the control. The `%f` slot is a
/// double, so its zero reads `0.0`.
@Test func aDoubleStoredFromAZeroedVectorIsOneLaneIfPresent() async throws {
    for fixture in ["Fixtures/Sample/libVectorLane.O0.dylib", "Fixtures/Sample/libVectorLane.O2.dylib"] {
        guard let format = try await pseudo(fixture, "laneZeroFormat"),
              let printf = try await pseudo(fixture, "laneZeroPrintf") else { return }
        #expect(format.contains(#"[NSString stringWithFormat:@"%f", 0.0]"#), "\(fixture)\n\(format)")
        #expect(printf.contains(#"printf("%f|%d", 0.0, 1)"#), "\(fixture)\n\(printf)")
        #expect(!format.contains("(0, 0)") && !printf.contains("(0, 0)"), "\(fixture)\n\(format)\n\(printf)")
    }
}

/// A Double argument is d0 and a Double return is d0: `movi v0.2d, #0; bl`
/// and `movi v0.2d, #0; ret`, at -Onone and -O alike.
@Test func aDoubleArgumentAndReturnFromAZeroedVectorAreOneLaneIfPresent() async throws {
    for fixture in ["Fixtures/Sample/libVectorLaneSwift.Onone.dylib", "Fixtures/Sample/libVectorLaneSwift.O.dylib"] {
        guard let call = try await pseudo(fixture, "laneZeroCall"),
              let ret = try await pseudo(fixture, "laneZeroReturn") else { return }
        #expect(call.contains("return VectorLane.laneTakes(0.0)"), "\(fixture)\n\(call)")
        #expect(ret.contains("return 0.0"), "\(fixture)\n\(ret)")
        #expect(!call.contains("(0, 0)") && !ret.contains("(0, 0)"), "\(fixture)\n\(call)\n\(ret)")
    }
}

/// A view narrower than a lane keeps only a constant's low bits; a lane that
/// is not a constant cannot be cut, so `s0` of it declines.
@Test func aNarrowViewOfAVectorKeepsOnlyWhatItCanProve() {
    let constant = AbstractValue.aggregate([.immediate(0x1_0000_0002), .immediate(7)])
    #expect(ValueTracer.scalarView(constant, bits: 64) == .immediate(0x1_0000_0002))
    #expect(ValueTracer.scalarView(constant, bits: 32) == .immediate(2))
    #expect(ValueTracer.scalarView(constant, bits: 16) == .immediate(2))
    #expect(ValueTracer.scalarView(constant, bits: 128) == constant)
    let loaded = AbstractValue.aggregate([.loaded(0x4000), .loaded(0x4008)])
    #expect(ValueTracer.scalarView(loaded, bits: 64) == .loaded(0x4000))
    #expect(ValueTracer.scalarView(loaded, bits: 32) == .unknown)
    #expect(ValueTracer.scalarView(.aggregate([]), bits: 64) == .unknown)
    #expect(ValueTracer.scalarView(.immediate(5), bits: 32) == .immediate(5))
}
