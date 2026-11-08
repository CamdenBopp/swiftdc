import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A store nothing else describes is shown as the write it is, at the width
/// it stores, with the instruction's registers for what the tracer did not
/// prove. Unshown, these functions rendered empty: the compiler-grounded
/// audit found 320 of 4,165 stripped swift-syntax functions empty or a bare
/// `return` while their code wrote memory. A store to the frame stays
/// hidden, as a spill.
@Test func aStoreNothingElseDescribesIsShownIfPresent() async throws {
    let path = "Fixtures/Sample/libMemoryWrites.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func body(_ name: String) throws -> String {
        try #require(functions.first { $0.symbol == "_\(name)" }).renderStructured()
    }
    let cases: [(String, String)] = [
        ("mw_field", "mem64[arg0 + 0x10] = arg1"),
        ("mw_release", "mem8[arg0] = (arg1 & 255)"),
        ("mw_indexed", "mem64[arg0 + (arg1 << 3)] = arg2"),
        ("mw_result", "mem64[&result] = arg0; mem64[&result + 0x8] = arg1"),
    ]
    for (name, expected) in cases {
        let text = try body(name)
        #expect(text.contains(expected), Comment(rawValue: text))
    }
    // sp addresses the stack even where the frame layout lost track of it.
    for name in ["mw_spill", "mw_dynamic"] {
        let text = try body(name)
        #expect(!text.contains("mem"), Comment(rawValue: text))
    }
}
