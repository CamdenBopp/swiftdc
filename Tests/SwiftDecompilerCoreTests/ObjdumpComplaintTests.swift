import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A dylib whose symbol values all point past its sections makes
/// llvm-objdump print `section data ends, _add lies outside valid range`
/// and no instruction. Plain `disasm` then said "This is a parser defect,
/// not an empty binary", blaming swiftdc for damaged input. The tool's own
/// complaint now decides which message reads.
@Test func llvmObjdumpsComplaintNamesDamagedInput() {
    let stdout = """
        /tmp/a.dylib:
        (__TEXT,__text) section
        section data ends, _add lies outside valid range
        """
    let report = Disassembler.objdumpComplaint(stdout: stdout, stderr: "")
    #expect(report == "section data ends, _add lies outside valid range")
    let damaged = Disassembler.DisassembleError.parsedNothing(lines: 3, knownStarts: 4, toolReport: report).description
    #expect(damaged.contains("The input looks damaged"), Comment(rawValue: damaged))
    #expect(!damaged.contains("parser defect"), Comment(rawValue: damaged))
    // Nothing reported: the empty parse is still ours.
    #expect(Disassembler.objdumpComplaint(stdout: "/tmp/a.dylib:\n(__TEXT,__text) section\n_f:\n", stderr: "") == nil)
    let ours = Disassembler.DisassembleError.parsedNothing(lines: 3, knownStarts: 4).description
    #expect(ours.contains("parser defect"), Comment(rawValue: ours))
}

/// End to end: every defined symbol's value of a copy of a C fixture is
/// moved past the image, and the listing path's error carries
/// llvm-objdump's own complaint.
@Test func aDylibWithDamagedSymbolsIsReportedAsDamagedIfPresent() async throws {
    let path = "Fixtures/Sample/libVariadicCalls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    var symbolOffset = 0, symbolCount = 0
    for command in image.loadCommands {
        if case .symtab(let table) = command {
            symbolOffset = Int(table.layout.symoff)
            symbolCount = Int(table.layout.nsyms)
        }
    }
    try #require(symbolCount > 0)
    var bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    for index in 0 ..< symbolCount {
        let entry = symbolOffset + index * 16
        // n_type & N_TYPE == N_SECT: defined in a section.
        guard bytes[entry + 4] & 0x0e == 0x0e else { continue }
        let far: UInt64 = 0xdead_beef_0000
        for byte in 0 ..< 8 { bytes[entry + 8 + byte] = UInt8(truncatingIfNeeded: far >> (8 * UInt64(byte))) }
    }
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("symfar-\(UUID().uuidString).dylib")
    try bytes.write(to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }
    do {
        _ = try await withStableDependencies { try await Disassembler().disassemble(path: copy.path) }
        Issue.record("disassembled a dylib whose symbols all lie outside it")
    } catch let error as Disassembler.DisassembleError {
        #expect(error.description.contains("The input looks damaged"), Comment(rawValue: error.description))
    }
}
