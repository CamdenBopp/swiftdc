import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A value type's method takes its formal parameters from x0, then, unless
/// it is mutating, `self`'s words (`valuemethod.swift`).
struct ValueMethodArgumentTests {
    private func pseudo(_ name: String) async throws -> String? {
        let path = "Fixtures/Sample/libValueMethod.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        return try #require(functions.first { $0.displayName.hasPrefix("ValueMethod.\(name)(") }).renderPseudo()
    }

    /// Laid out positionally, a small literal's two words read
    /// `append(10, 0xe100000000000000)`.
    @Test func aStringParameterOfAValueMethodIsOneArgumentIfPresent() async throws {
        guard let text = try await pseudo("newline") else { return }
        #expect(text.contains("Swift.String.append(\"\\n\")"), Comment(rawValue: text))
    }

    /// With nothing tracked the positional trim left `append()` and
    /// `_combine()`, calls that take nothing.
    @Test func anUntrackedParameterOfAValueMethodIsUnknownIfPresent() async throws {
        guard let boxed = try await pseudo("appendBoxed"), let mix = try await pseudo("mix") else { return }
        #expect(boxed.contains("Swift.String.append(?)"), Comment(rawValue: boxed))
        #expect(mix.contains("Swift.Hasher._combine(?)"), Comment(rawValue: mix))
    }

    /// A call the tracer recorded nothing for still takes the parameters
    /// its signature proves: stripped, `appendTwo` is unnamed, its entry
    /// proves nothing, and its first call has no snapshot.
    @Test func aValueMethodCallWithNothingTrackedTakesItsParametersIfPresent() async throws {
        let path = "Fixtures/Sample/libValueMethod.stripped.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let unnamed = try #require(functions.first { $0.displayName.hasPrefix("sub_") && $0.renderPseudo().contains("String.append") })
        let text = unnamed.renderPseudo()
        #expect(text.components(separatedBy: "Swift.String.append(?)").count == 3, Comment(rawValue: text))
    }

    /// A non-mutating method's `self` follows its formal parameters and is
    /// kept: `scaled(k)` on a one-word Meter passes k in x0 and v in x1.
    @Test func aValueSelfAfterTheParametersIsKeptIfPresent() async throws {
        guard let text = try await pseudo("use") else { return }
        #expect(text.contains("ValueMethod.Meter.scaled(arg1, arg0)"), Comment(rawValue: text))
    }
}
