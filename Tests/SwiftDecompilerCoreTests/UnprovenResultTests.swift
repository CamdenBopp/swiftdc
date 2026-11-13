import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A C function with no signature and no caller rendered a bare `return`,
/// which reads as void: `long konst(void) { return 42; }` said nothing of
/// its 42. Whether x0 is a result is not in the binary, so it is shown as
/// a comment on the return (`unprovenresult.c`, -O2). Left out: an x0 still
/// holding the first argument (every void function would show it), one
/// built from a call's result (the comment repeated the call), and any
/// function whose callers or body are evidence about its result.
@Test func aSignaturelessReturnShowsWhatX0HoldsIfPresent() async throws {
    let path = "Fixtures/Sample/libUnprovenResult.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let konst = try structured("_konst")
    #expect(konst.contains("return // x0 = 42"), Comment(rawValue: konst))
    let scaled = try structured("_scaled")
    #expect(scaled.contains("return // x0 = "), Comment(rawValue: scaled))
    #expect(scaled.contains("arg0") && scaled.contains("arg1"), Comment(rawValue: scaled))
    // Built from a call's result: shown, the call read as made twice.
    let two = try structured("_twoArgs")
    #expect(!two.contains("// x0"), Comment(rawValue: two))
    let quiet = try structured("_quiet")
    #expect(!quiet.contains("// x0"), Comment(rawValue: quiet))

    // A Swift symbol is outside the rule: its mangling names what it is,
    // and a metadata accessor's x0 is its result, not a guess about one.
    let swift = "Fixtures/Sample/libMixedSelf.dylib"
    guard FileManager.default.fileExists(atPath: swift) else { return }
    let swiftFunctions = try await withStableDependencies { try await Disassembler().disassemble(path: swift) }
    for function in swiftFunctions where function.displayName.hasPrefix("type metadata accessor") {
        #expect(!function.renderStructured().contains("// x0"), Comment(rawValue: function.renderStructured()))
    }
}
