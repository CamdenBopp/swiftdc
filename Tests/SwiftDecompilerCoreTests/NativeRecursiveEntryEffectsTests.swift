import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

// Six public callers and six private helpers. Independent function-start
// and text-symbol inventories are recorded with the fixture proof artifacts.
@Test func recursiveEntryCallersStopReturningStaleConstantsIfPresent() async throws {
    let path = "Fixtures/Sample/libRecursiveSummaryEffects.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let cases = [
        (suffix: "6gprOnes6UInt64VyF", floating: false, kept: false),
        (suffix: "6gprTwos6UInt64VyF", floating: false, kept: false),
        (suffix: "7gprKepts6UInt64VyF", floating: false, kept: true),
        (suffix: "9vectorOneSdyF", floating: true, kept: false),
        (suffix: "9vectorTwoSdyF", floating: true, kept: false),
        (suffix: "10vectorKeptSdyF", floating: true, kept: true),
    ]
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    for test in cases {
        let symbol = "$s16SummaryRecursion" + test.suffix
        let pointer = try #require(dlsym(library, symbol))
        if test.floating {
            let native = unsafeBitCast(pointer, to: (@convention(c) () -> Double).self)
            #expect(native() == (test.kept ? 2.0 : 1.0))
        } else {
            let native = unsafeBitCast(pointer, to: (@convention(c) () -> UInt64).self)
            #expect(native() == (test.kept ? 2 : 1))
        }
    }
    let array = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "SummaryRecursion")
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    try #require(array.count == 12 && streamed.count == 12 && filtered.count == 6)
    let symbols = Set(cases.map { "_$s16SummaryRecursion" + $0.suffix })
    try #require(Set(filtered.map(\.symbol)) == symbols)
    for (mode, functions) in [("array", array), ("filtered", filtered), ("streaming", streamed)] {
        for test in cases {
            let matches = functions.filter { $0.symbol == "_$s16SummaryRecursion" + test.suffix }
            try #require(matches.count == 1, "\(mode): \(test.suffix)")
            let function = try #require(matches.first)
            let exits = function.instructions.compactMap { $0.exit?.statement }
            try #require(exits.count == 1, "\(mode): \(function.renderPseudo())")
            let expected = test.kept ? (test.floating ? "return 2.0" : "return 2")
                                     : (test.floating ? "return 1.0" : "return 1")
            // Summary closure can soundly decline; it need not inline recursion.
            #expect(exits == [expected] || (!test.kept && exits == ["return ?"]),
                    "\(mode): \(function.renderPseudo())")
        }
    }
}
