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
    let text = functions.map { expandingResultBindingsForAssertions($0.renderPseudo()) }.joined(separator: "\n")
    // churn's own four arguments are untracked C parameters.
    #expect(text.contains(#"stringWithFormat:@"%ld %ld", churn(?, ?, ?, ?), ?]"#), "\(text)")
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

/// A call counted as printed when a later call's registers held its result,
/// but a send prints only one argument per colon, past them only for a
/// variadic selector: `objc_dropped_result.m`'s secondValue fed only x3 of
/// an untyped `setSpan:` (an NSRange in x2 and x3) and was printed nowhere.
@Test func aCallOnlyAnUnprintedSendRegisterTakesStaysPrintedIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCDroppedResult.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName == "_spanSend" }).renderPseudo()
    #expect(text.contains("secondValue()"), Comment(rawValue: text))
    // A variadic send prints its arguments past the colons, so a call
    // there is printed once, inside it.
    let format = try #require(functions.first { $0.displayName == "_formatFirst" }).renderPseudo()
    #expect(format.components(separatedBy: "firstValue()").count == 2, Comment(rawValue: format))
}

/// `objc_unsafeClaimAutoreleasedReturnValue`, which ARC wraps a discarded
/// result in, is autorelease bookkeeping like the rest of its family:
/// `(void)[o description]` rendered
/// `objc_unsafeClaimAutoreleasedReturnValue([? description])`.
@Test func anUnsafeClaimIsHiddenLikeTheRestOfItsFamilyIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCDroppedResult.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName == "_discardDescription" }).renderPseudo()
    #expect(text.contains("    [? description]\n") && !text.contains("objc_unsafeClaim"), Comment(rawValue: text))
}

/// `objc_autorelease` returns the object it is handed. Modelled as
/// returning a new value, its result printed as the allocation it returned
/// at every use (`objc_autorelease.m`, no ARC): three
/// `[[NSMutableString alloc] init]` for one object.
@Test func anAutoreleasedObjectIsOneObjectIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCAutorelease.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName == "_autoreleasedTwice" }).renderPseudo()
    #expect(text.components(separatedBy: "[NSMutableString alloc]").count == 2, Comment(rawValue: text))
    #expect(text.contains("let r0 = [[NSMutableString alloc] init]") && text.contains("[r0 length]"),
            Comment(rawValue: text))
}

/// The runtime calls that return the object they are handed (objc4's
/// declarations), and one that does not: `objc_retainBlock` returns a copy.
@Test func theAutoreleaseFamilyReturnsItsArgument() {
    for callee in ["objc_autorelease", "_objc_retainAutorelease", "objc_retainAutoreleaseReturnValue",
                   "objc_unsafeClaimAutoreleasedReturnValue", "objc_retain"] {
        #expect(ValueTracer.CallFacts(callee: callee).returnsArgument, "\(callee)")
    }
    #expect(!ValueTracer.CallFacts(callee: "objc_retainBlock").returnsArgument)
    #expect(!ValueTracer.CallFacts(callee: "objc_release").returnsArgument)
}
