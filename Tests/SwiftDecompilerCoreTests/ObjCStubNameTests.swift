import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `__objc_stubs` entries are named from the selref each stub loads, which is
/// what runs, not from a symbol. Nothing checked the standalone path: if the
/// selref lookup ever came back empty, every message send would render as a
/// call to a bare address and no test would go red (the empty-result class).
/// The unstripped fixture's own `objc_msgSend$<selector>` symbols, read by
/// `nm`, are the oracle; the stripped build has none and must name the same
/// stubs from code alone.
private func nmStubSymbols(_ path: String) throws -> [UInt64: String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["nm", "-m", path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    var symbols: [UInt64: String] = [:]
    for line in text.split(separator: "\n") where line.contains("(__TEXT,__objc_stubs)") {
        let fields = line.split(separator: " ")
        guard let address = fields.first.flatMap({ UInt64($0, radix: 16) }),
              let name = fields.last, name.hasPrefix("_objc_msgSend$")
        else { continue }
        symbols[address] = String(name.dropFirst())
    }
    return symbols
}

@Test func objcStubsAreNamedFromTheirSelrefsIfPresent() throws {
    let debug = "Fixtures/Sample/sample.debug"
    let stripped = "Fixtures/Sample/sample.stripped"
    guard FileManager.default.fileExists(atPath: debug),
          FileManager.default.fileExists(atPath: stripped) else { return }
    let oracle = try nmStubSymbols(debug)
    #expect(oracle.count == 5, "the fixture's stub symbols changed: \(oracle)")

    let disassembler = Disassembler(preset: .default)
    let named = disassembler.objcStubNames(in: try BinaryLoader.load(path: debug))
    #expect(named == oracle)

    #expect(try nmStubSymbols(stripped).isEmpty, "the stripped build kept its stub symbols")
    let fromCode = disassembler.objcStubNames(in: try BinaryLoader.load(path: stripped))
    #expect(Set(fromCode.values) == Set(oracle.values))
}
