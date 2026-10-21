import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A call's or branch's callee is fixed where its target is named and kept
/// through every rebuild that only appends notes. Parsed again from the
/// final annotation it must read the same, unless a note appended later
/// reads as a name: that difference is the hazard the fact removes.
@Test func calleeFactsMatchTheirAnnotationsOnTheFixturesIfPresent() async throws {
    let directory = "Fixtures/Sample"
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    var mismatches: [String] = []
    var checked = 0
    for name in names.sorted() where name.hasSuffix(".dylib") || name == "sample.debug" || name == "sample.release" {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: "\(directory)/\(name)") }
        for function in functions {
            for insn in function.instructions where insn.controlFlow == .call || insn.controlFlow == .branch {
                checked += 1
                let parsed = DisassembledFunction.parsedCalleeName(text: insn.text, annotation: insn.annotation)
                if parsed != insn.callee {
                    mismatches.append("\(name) \(function.displayName) @\(String(insn.address, radix: 16)): fact \(insn.callee ?? "nil"), parsed \(parsed ?? "nil") | \(insn.annotation ?? "")")
                }
            }
        }
    }
    #expect(checked > 1000)
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(mismatches.prefix(40).joined(separator: "\n"))")
}
