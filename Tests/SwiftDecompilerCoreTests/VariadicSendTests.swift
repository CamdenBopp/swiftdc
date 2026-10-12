import Testing
import Foundation
@testable import SwiftDecompilerCore

/// On Apple arm64 a variadic argument goes on the stack, one 8-byte slot per
/// argument. A format send appended whatever stack slots were written and then
/// trimmed trailing unknowns, so `[NSString stringWithFormat:@"%ld %ld", k, a]`
/// with `a` unrecovered rendered one argument: a real argument silently
/// omitted. A format's conversions now fix the count, and an unknown slot is `?`.
@Test func aFormatSendShowsEveryConversionsArgumentIfPresent() async throws {
    let fixture = "Fixtures/Sample/libVariadic.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "describe")
    }
    let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains(#"stringWithFormat:@"%ld %ld", churn(), ?]"#), "\(text)")
}

@Test func theFormatParserCountsOnlyWhatItCanProve() {
    func count(_ literal: String) -> Int? { DisassembledFunction.MessageSend.formatArgumentCount(literal) }
    #expect(count(#"@"%ld %ld""#) == 2)
    #expect(count(#"@"%@: %.2f%%""#) == 2)
    #expect(count(#"@"no conversions""#) == 0)
    #expect(count(#""%-08.3lld and %hhu""#) == 2)
    // `*` consumes an extra argument, `$` reorders them, `…` means truncated,
    // and an unknown conversion cannot be sized.
    #expect(count(#"@"%*d""#) == nil)
    #expect(count(#"@"%1$d""#) == nil)
    #expect(count(#"@"%d and more text…""#) == nil)
    #expect(count(#"@"%k""#) == nil)
}

/// Stack values follow the register arguments by position. With x2 unknown
/// the register list was trimmed to x0, so `[NSArray arrayWithObjects:a, b,
/// nil]` received its stack values in the `_cmd` and first-object positions
/// and rendered `arrayWithObjects:0`: the nil sentinel as the first object.
/// The list now ends at its nil, and a format whose conversions are not
/// readable (a parameter) renders `…` instead of guessing a count from
/// contiguous stack slots, which may be spills.
@Test func variadicStackValuesKeepTheirPositionsIfPresent() async throws {
    let fixture = "Fixtures/Sample/libVariadic.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    func pseudo(_ name: String) async throws -> String {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: name)
        }
        return functions.map { $0.renderPseudo() }.joined(separator: "\n")
    }
    let list = try await pseudo("listOf")
    #expect(list.contains("[NSArray arrayWithObjects:?, ?, 0]"), "\(list)")
    let formatted = try await pseudo("describeWith")
    #expect(formatted.contains("[NSString stringWithFormat:?, …]"), "\(formatted)")
}
