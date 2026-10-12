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
