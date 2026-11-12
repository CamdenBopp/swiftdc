import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The same Objective-C built with opcode rebases (`LC_DYLD_INFO`, macOS 11
/// target) and with chained fixups (macOS 13). Read only through chained
/// fixups, the opcode build lost every selector reference and CFString:
/// `NSLog(0x4000)`, sends as unresolved calls, and a tail-called send left
/// the function a leaf. Both builds now render the same.
@Test func anOpcodeRebasedImageReadsSelectorsAndStringsIfPresent() async throws {
    let opcode = "Fixtures/Sample/libOpcodeFixups.dylib"
    let chained = "Fixtures/Sample/libOpcodeFixups.chained.dylib"
    guard FileManager.default.fileExists(atPath: opcode), FileManager.default.fileExists(atPath: chained) else { return }
    func render(_ path: String) async throws -> [String: String] {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        return Dictionary(functions.map { ($0.displayName, $0.renderStructured()) }, uniquingKeysWith: { a, _ in a })
    }
    let old = try await render(opcode)
    let new = try await render(chained)
    let report = try #require(old["_report"])
    #expect(report.contains("NSLog(@\"n=%ld\", arg1)"), Comment(rawValue: report))
    #expect(report.contains("[arg0 removeAllObjects]"), Comment(rawValue: report))
    #expect(old["_tailClear"]?.contains("removeAllObjects]") == true, Comment(rawValue: old["_tailClear"] ?? ""))
    for name in ["_report", "_tailClear"] {
        #expect(old[name] == new[name], "\(name) differs:\n\(old[name] ?? "")\n---\n\(new[name] ?? "")")
    }
}
