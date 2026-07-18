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

/// The recovered pseudocode for every function matching `filter`, or nil when the
/// fixture hasn't been built.
private func reconstructionPseudo(_ filter: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: reconstructionFixture) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default)
            .disassemble(path: reconstructionFixture, functionFilter: filter)
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
