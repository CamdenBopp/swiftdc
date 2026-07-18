import Testing
import Foundation
@testable import SwiftDecompilerCore

/// End-to-end assertions on the Swift-body pseudocode reconstruction, driven by
/// `Fixtures/Sample/libReconstruction.dylib` (build it with
/// `Fixtures/Sample/build.sh`). Each fixture function isolates one construct so
/// the recovered pseudocode can be asserted verbatim.
///
/// Absent the built fixture these skip, keeping `swift test` green on a clean
/// checkout — the same convention as the other `…IfPresent` tests.
private let reconstructionFixture = "Fixtures/Sample/libReconstruction.dylib"

/// The recovered pseudocode for every function matching `filter` in a fixture
/// variant, or nil when it hasn't been built.
private func reconstructionPseudo(
    _ filter: String, in fixture: String = reconstructionFixture
) async throws -> String? {
    guard FileManager.default.fileExists(atPath: fixture) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default)
            .disassemble(path: fixture, functionFilter: filter)
    }
    return functions.map { $0.renderPseudo() }.joined(separator: "\n")
}

// MARK: - Comparisons (NZCV + cset)

@Test func recoversComparisonReturnsIfPresent() async throws {
    guard let positive = try await reconstructionPseudo("isPositive") else { return }
    #expect(positive.contains("return (0 < arg0)")) // x > 0 lowered as 0 - x < 0

    guard let equal = try await reconstructionPseudo("isEqual") else { return }
    #expect(equal.contains("return (arg0 == arg1)"))

    guard let atLeast = try await reconstructionPseudo("atLeast") else { return }
    #expect(atLeast.contains("return (arg0 >= arg1)"))
}

// MARK: - Argument seeding (integer + floating-point)

@Test func recoversScalarArgumentsIfPresent() async throws {
    guard let addThree = try await reconstructionPseudo("addThree") else { return }
    #expect(addThree.contains("return ((arg0 + arg1) + arg2)"))

    guard let hypot = try await reconstructionPseudo("hypotenuse") else { return }
    #expect(hypot.contains("return sqrt(((arg0 * arg0) + (arg1 * arg1)))"))

    // Mixed: an integer parameter in x0, a floating-point one in v0.
    guard let scaled = try await reconstructionPseudo("scaleInt") else { return }
    #expect(scaled.contains("return (arg0 * arg1)"))
}

// MARK: - HFA struct decomposition

@Test func decomposesHFAStructSelfAndArgumentsIfPresent() async throws {
    // A computed-property getter: self decomposed into self.x / self.y.
    guard let magnitude = try await reconstructionPseudo("magnitudeSquared") else { return }
    #expect(magnitude.contains("return ((self.x * self.x) + (self.y * self.y))"))

    // A method taking a by-value struct parameter: arg0.x / arg0.y recovered.
    guard let dot = try await reconstructionPseudo("Vec2.dot") else { return }
    #expect(dot.contains("return ((arg0.x * self.x) + (arg0.y * self.y))"))
}

// MARK: - Class vtable property access

@Test func namesVTablePropertyAccessIfPresent() async throws {
    guard let doubled = try await reconstructionPseudo("doubled") else { return }
    #expect(doubled.contains("return (self.value + self.value)"))

    guard let advance = try await reconstructionPseudo("advance") else { return }
    #expect(advance.contains("self.value = (self.value + self.step)"))

    guard let reset = try await reconstructionPseudo("reset") else { return }
    #expect(reset.contains("self.value = 0"))
}

// MARK: - Dynamic casts

@Test func recoversDynamicCastsIfPresent() async throws {
    guard let optional = try await reconstructionPseudo("castOptional") else { return }
    #expect(optional.contains("as? Reconstruction.Dog"))

    guard let forced = try await reconstructionPseudo("castForced") else { return }
    #expect(forced.contains("as! Reconstruction.Dog"))

    guard let string = try await reconstructionPseudo("castToString") else { return }
    #expect(string.contains("as? Swift.String"))
}

// MARK: - Ternary / select reconstruction (control-flow value merge)

@Test func reconstructsTernarySelectIfPresent() async throws {
    // `-Onone` diamond: two arms store into a merge slot. Semantically
    // equivalent — the compiler tests `x >= 0`, not `x < 0`.
    guard let clamp = try await reconstructionPseudo("clampLow") else { return }
    #expect(clamp.contains("return ((arg0 >= 0) ? arg0 : 0)"))

    guard let maxOf = try await reconstructionPseudo("maxOf") else { return }
    #expect(maxOf.contains(" ? ") && maxOf.contains("arg0") && maxOf.contains("arg1"))

    // A Bool condition arrives as a bit-0 test, rendered honestly.
    guard let pick = try await reconstructionPseudo("pickInc") else { return }
    #expect(pick.contains("return (((arg0 & 1) == 0) ? (arg1 - 1) : (arg1 + 1))"))
}

/// The optimized build lowers the ternary to a branchless `csel`; it must
/// reconstruct the same select — and survive stripping, since the value tracer
/// needs no symbols for it.
@Test func reconstructsOptimizedTernaryIfPresent() async throws {
    for fixture in ["Fixtures/Sample/libReconstruction.opt.dylib",
                    "Fixtures/Sample/libReconstruction.opt.stripped.dylib"] {
        guard let maxOf = try await reconstructionPseudo("maxOf", in: fixture) else { continue }
        #expect(maxOf.contains("return ((arg1 > arg0) ? arg1 : arg0)"))
    }
}

/// Adversarial: a three-way merge is not a clean 2-arm diamond, so the tool must
/// decline to reconstruct a select rather than fabricate one.
@Test func declinesToGuessNonDiamondSelectIfPresent() async throws {
    guard let threeWay = try await reconstructionPseudo("threeWay") else { return }
    #expect(!threeWay.contains(" ? ")) // no fabricated select
}

/// Pointer-optional nil-coalescing: one register (nil == 0), so at -O it
/// reconstructs as a select — semantically `arg0 ?? arg1`.
@Test func reconstructsPointerNilCoalescingIfPresent() async throws {
    guard let ptr = try await reconstructionPseudo(
        "ptrOrElse", in: "Fixtures/Sample/libReconstruction.opt.dylib") else { return }
    #expect(ptr.contains("return ((arg0 == 0) ? arg1 : arg0)"))
}

/// Adversarial: a TAGGED optional (`Int?`, payload + tag byte in separate
/// registers) has no single-register nil check, so nil-coalescing over it must
/// decline rather than guess — in both debug and optimized builds.
@Test func declinesTaggedOptionalNilCoalescingIfPresent() async throws {
    for fixture in [reconstructionFixture, "Fixtures/Sample/libReconstruction.opt.dylib"] {
        guard let opt = try await reconstructionPseudo("intOrDefault", in: fixture) else { continue }
        #expect(!opt.contains(" ? ")) // no fabricated select over the tag
    }
}

// MARK: - Robustness edge cases

@Test func handlesArithmeticEdgeCasesIfPresent() async throws {
    // A constant return.
    guard let constant = try await reconstructionPseudo("constant") else { return }
    #expect(constant.contains("return 42"))

    // A deeply nested expression (exercises the bounded expression tree).
    guard let deep = try await reconstructionPseudo("deepNest") else { return }
    #expect(deep.contains("return (((arg0 + arg1) * (arg2 - arg3)) + ((arg0 - arg2) * (arg1 + arg3)))"))

    // All eight integer argument registers.
    guard let eight = try await reconstructionPseudo("eightArgs") else { return }
    #expect(eight.contains("arg7"))

    // Interleaved integer (x0/x1) and floating-point (v0/v1) parameters —
    // the two Doubles are arg1 and arg3.
    guard let mixed = try await reconstructionPseudo("interleaved") else { return }
    #expect(mixed.contains("return (arg1 + arg3)"))
}

// MARK: - Homogeneous array literals

@Test func recoversArrayLiteralsIfPresent() async throws {
    guard let triple = try await reconstructionPseudo("triple") else { return }
    #expect(triple.contains("return [10, 20, 30]"))

    guard let pair = try await reconstructionPseudo("pairOf") else { return }
    #expect(pair.contains("return [arg0, arg1]"))

    // A non-Int element type (Double stride) recovers too.
    guard let doubles = try await reconstructionPseudo("doublesOf") else { return }
    #expect(doubles.contains("return [arg0, arg1]"))
}

// MARK: - Wider arithmetic and layout edge cases

@Test func recoversWiderArithmeticIfPresent() async throws {
    guard let bits = try await reconstructionPseudo("bitOps") else { return }
    #expect(bits.contains("return ((arg0 & arg1) | (arg0 << 2))"))

    // Float parameters seed v-registers just as Double does.
    guard let float = try await reconstructionPseudo("floatMath") else { return }
    #expect(float.contains("return ((arg0 * arg1) + arg0)"))

    // Integer division (sdiv), distinct from the FP divide path.
    guard let div = try await reconstructionPseudo("intDivide") else { return }
    #expect(div.contains("return (arg0 / arg1)"))

    // Remainder — folded from the sdiv/mul/sub the compiler emits.
    guard let rem = try await reconstructionPseudo("remainder") else { return }
    #expect(rem.contains("return (arg0 % arg1)"))

    // Fused multiply-add (madd): `a + b * c`.
    guard let fma = try await reconstructionPseudo("fusedMultiplyAdd") else { return }
    #expect(fma.contains("return (arg0 + (arg1 * arg2))"))

    // A 3-field HFA struct decomposes self across d0, d1, d2.
    guard let luminance = try await reconstructionPseudo("luminance") else { return }
    #expect(luminance.contains("return ((self.r + self.g) + self.b)"))
}
