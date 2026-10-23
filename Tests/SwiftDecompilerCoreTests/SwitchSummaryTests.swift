import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The rendered pseudo statements of `name` on the array, filtered and
/// streaming paths.
private func statements(of name: String, in path: String, filter: String) async throws -> [(String, [String])] {
    let full = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: filter)
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    return try [("array", full), ("filtered", filtered), ("streaming", streamed)].map { label, functions in
        let function = try #require(functions.first { $0.displayName == name }, "\(label): no \(name)")
        return (label, function.renderPseudo().components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) })
    }
}

/// The register summaries were built before jump tables were recovered, so a
/// switch's `br` read as a tail call out of the body: the cases were never
/// reached, and the `br` counted as reading every argument register.
///
/// `switch_clobbers.s`: case 2 of `table_switch` calls `table_clobber`,
/// which leaves x19 changed. A caller keeping arg0 in x19 across
/// `table_switch` (or a wrapper that calls it, one or two levels down)
/// rendered `return arg0`, where native execution with (2, 5) returns 5.
@Test func aSwitchCaseClobberReachesItsCallersIfPresent() async throws {
    let path = "Fixtures/Sample/libSwitchClobbers.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Caller = @convention(c) (Int, Int) -> Int
    func native(_ name: String, _ a: Int, _ b: Int) throws -> Int {
        let symbol = try #require(dlsym(library, "$s11SwitchTable\(name)yS2i_SitF"))
        return unsafeBitCast(symbol, to: Caller.self)(a, b)
    }
    #expect(try native("6direct", 2, 5) == 5 && native("7wrapped", 2, 5) == 5 && native("4deep", 2, 5) == 5)
    #expect(try native("6direct", 1, 5) == 1 && native("7wrapped", 1, 5) == 1 && native("4deep", 1, 5) == 1)
    // A filtered run decodes its matches' callees a level at a time: with
    // `deep` alone matched, table_switch is three calls down.
    for (caller, filter) in [("direct", "SwitchTable"), ("wrapped", "SwitchTable"), ("deep", "SwitchTable.deep")] {
        for (label, lines) in try await statements(
            of: "SwitchTable.\(caller)(Swift.Int, Swift.Int) -> Swift.Int", in: path, filter: filter) {
            #expect(lines.contains("return ?") && !lines.contains("return arg0"), "\(label) \(caller): \(lines)")
        }
    }
}

/// `switchsummary.c` (-O2): `dispatchTable(void)` dispatches through a jump
/// table and reads only globals, yet its `br` made it read every argument
/// register, so the tail call after `printf` rendered
/// `dispatchTable(printf(…))`.
@Test func aSwitchDispatchTakesNoArgumentItDoesNotReadIfPresent() async throws {
    let path = "Fixtures/Sample/libSwitchSummary.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for (label, lines) in try await statements(of: "_printThenDispatch", in: path, filter: "Dispatch") {
        #expect(lines.contains("dispatchTable()"), "\(label): \(lines)")
        #expect(!lines.contains { $0.hasPrefix("dispatchTable(printf") }, "\(label): \(lines)")
    }
}
