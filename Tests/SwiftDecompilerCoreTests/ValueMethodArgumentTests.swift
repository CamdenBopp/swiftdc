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
        // The `inout` String is `self`, by address in x20.
        #expect(text.contains("Swift.String.append(self: arg0, \"\\n\")"), Comment(rawValue: text))
    }

    /// With nothing tracked the positional trim left `append()` and
    /// `_combine()`, calls that take nothing.
    @Test func anUntrackedParameterOfAValueMethodIsUnknownIfPresent() async throws {
        guard let boxed = try await pseudo("appendBoxed"), let mix = try await pseudo("mix") else { return }
        #expect(boxed.contains("Swift.String.append(?)"), Comment(rawValue: boxed))
        // Seeded, the `inout` Hasher is `self` in x20 and v is x1, so the
        // call is mutating and x1 is its one parameter, not a `self` word:
        // as found it read `_combine(arg1, arg1)`.
        #expect(mix.contains("Swift.Hasher._combine(self: arg0, arg1)\n"), Comment(rawValue: mix))
    }

    /// A call still takes exactly the parameters its signature proves:
    /// stripped, `appendTwo` is unnamed and its entry seeds only what its
    /// body reads. The entry arguments still in x2-x4 at the first call
    /// are not more parameters of a stub (`append(self: arg0, ?, arg2,
    /// arg3, arg4)` for a one-String `append(_:)`).
    @Test func aValueMethodCallWithNothingTrackedTakesItsParametersIfPresent() async throws {
        let path = "Fixtures/Sample/libValueMethod.stripped.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let unnamed = try #require(functions.first { $0.displayName.hasPrefix("sub_") && $0.renderPseudo().contains("String.append") })
        let text = unnamed.renderPseudo()
        #expect(text.contains("Swift.String.append(self: arg0, ?)\n"), Comment(rawValue: text))
        #expect(text.contains("Swift.String.append(?)"), Comment(rawValue: text))
    }

    /// A non-mutating method's `self` follows its formal parameters and is
    /// kept: `scaled(k)` on a one-word Meter passes k in x0 and v in x1.
    @Test func aValueSelfAfterTheParametersIsKeptIfPresent() async throws {
        guard let text = try await pseudo("use") else { return }
        #expect(text.contains("ValueMethod.Meter.scaled(arg1, arg0)"), Comment(rawValue: text))
    }

    /// A StaticString is three words and one argument: `note("ready", 3)`
    /// read `note("ready", 5, 2, 3)`, its count and flags as two more
    /// arguments (`statictext.swift`).
    @Test func aStaticStringParameterIsOneArgumentIfPresent() async throws {
        let path = "Fixtures/Sample/libStaticText.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let text = try #require(functions.first { $0.displayName.hasPrefix("StaticText.report(") }).renderPseudo()
        #expect(text.contains("return StaticText.note(\"ready\", 3)"), Comment(rawValue: text))
    }

    /// Parameters past x7 go on the stack and are read from the call's
    /// stores; declined whole, `fatalError(m)`'s
    /// `_assertionFailure(_:_:file:line:flags:)` read x0-x7 as eight
    /// arguments: `("Fatal error", 11, 2, ?, ?, "StaticText/statictext.swift",
    /// 19, 2)`. A StaticString whose first word is in x6 keeps its text, and
    /// its flags byte is the first stack word: the stdlib's `("Fatal error",
    /// "Not enough bits…", "Swift/…swiftinterface", <line>, 1)` (`sample.debug`).
    @Test func parametersOnTheStackAreUnknownIfPresent() async throws {
        let path = "Fixtures/Sample/libStaticText.dylib"
        let debug = "Fixtures/Sample/sample.debug"
        guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: debug) else { return }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let die = try #require(functions.first { $0.displayName.hasPrefix("StaticText.die(") }).renderPseudo()
        #expect(die.contains("Swift._assertionFailure(\"Fatal error\", ?, \"StaticText/statictext.swift\", 14, 0)"),
                Comment(rawValue: die))
        let sample = try await withStableDependencies { try await Disassembler().disassemble(path: debug) }
            .map { $0.renderPseudo() }.joined(separator: "\n")
        #expect(sample.contains("Swift._assertionFailure(\"Fatal error\", \"Not enough bits to represent the passed value\", \"Swift/"))
        #expect(!sample.contains("Swift._assertionFailure(\"Fatal error\", 11, 2"))
        #expect(!sample.contains("swiftinterface\", ?, ?)"))
    }

    /// Apple arm64 packs stack words to their own alignment, and a word is
    /// read only from a slot whose store matches it: two `UInt32`s share
    /// the first slot, which this cannot split, and a store narrower than
    /// its parameter is not that parameter.
    @Test func stackWordsAreReadOnlyWhereTheirStoresMatch() {
        func layout(_ types: [String], split: Int = 0) -> Disassembler.SwiftArgumentLayout {
            Disassembler.SwiftArgumentLayout(slots: [], stack: types.map { ($0, .integer) }, splitStackWords: split)
        }
        let line = AbstractValue.immediate(14), flags = AbstractValue.immediate(0)
        let read = Disassembler.stackParameterWords(
            layout(["Swift.UInt", "Swift.UInt32"]), stackArguments: [line, flags], widths: [8, 4])
        #expect(read.map { $0 ?? [] } == [[line], [flags]])
        let narrow = Disassembler.stackParameterWords(
            layout(["Swift.UInt", "Swift.UInt32"]), stackArguments: [line, flags], widths: [4, 4])
        #expect(narrow.allSatisfy { $0 == nil })
        let packed = Disassembler.stackParameterWords(
            layout(["Swift.UInt32", "Swift.UInt32"]), stackArguments: [line], widths: [4])
        #expect(packed[0] == [line] && packed[1] == nil)
        let split = Disassembler.stackParameterWords(
            layout(["Swift.UInt", "Swift.UInt32"], split: 1),
            stackArguments: [.immediate(2), line, flags], widths: [1, 8, 4])
        #expect(split.map { $0 ?? [] } == [[line], [flags]])
    }
}
