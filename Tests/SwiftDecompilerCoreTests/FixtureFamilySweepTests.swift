import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Families of compiled functions, each written so that its result names
/// the path the machine took. The emulator runs every function on a spread
/// of inputs and each rendered return is held to what the machine returned
/// (`sweepAgainstEmulator`). A family is here to keep whole classes of
/// lowering true at every optimization level, not for one defect.
///
/// The floor under each image is what the sweep checked when the family
/// was added, less a margin: a sweep that silently checks nothing fails.
private let controlFlowFamily: [(image: String, returns: Int)] = [
    ("Fixtures/Sample/libCFA.Onone.dylib", 2000),
    ("Fixtures/Sample/libCFA.O.dylib", 2400),
    ("Fixtures/Sample/libCFA.Osize.dylib", 2100),
]

/// cfa.swift: comparisons at every width and signedness, selects, range
/// and bit tests, switches, checked and wrapping arithmetic, division by
/// constants, loops.
@Test(arguments: controlFlowFamily.map(\.image))
func theControlFlowFamilysReturnsAgreeWithTheEmulatorIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = String(path.dropFirst("Fixtures/Sample/".count))
    // No emulator (Unicorn not installed): the enforcing suite names it.
    guard let sweep = try await sweepAgainstEmulator(image) else { return }
    let floor = try #require(controlFlowFamily.first { $0.image == path }).returns
    #expect(sweep.mismatches.isEmpty, "false statements:\n\(sweep.mismatches.sorted { $0.key < $1.key }.prefix(8).map { "\($0.key): \($0.value.first ?? "")" }.joined(separator: "\n"))")
    #expect(sweep.returnsChecked >= floor, "checked \(sweep.returnsChecked) returns in \(image)")
}
