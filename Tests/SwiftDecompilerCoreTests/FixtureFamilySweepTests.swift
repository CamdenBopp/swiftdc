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
private let families: [(image: String, returns: Int)] = [
    // cfa.swift: comparisons at every width and signedness, selects, range
    // and bit tests, switches, checked and wrapping arithmetic, division by
    // constants, loops.
    ("Fixtures/Sample/libCFA.Onone.dylib", 2000),
    ("Fixtures/Sample/libCFA.O.dylib", 2400),
    ("Fixtures/Sample/libCFA.Osize.dylib", 2100),
    // structfamily.swift: structs and tuples passed and returned in
    // registers, each field weighed into the result.
    ("Fixtures/Sample/libStructFamily.Onone.dylib", 40),
    ("Fixtures/Sample/libStructFamily.O.dylib", 26),
    ("Fixtures/Sample/libStructFamily.Osize.dylib", 110),
    // enumfam.swift: enum and Optional makers and weighers, by case.
    ("Fixtures/Sample/libEnumFam.Onone.dylib", 120),
    ("Fixtures/Sample/libEnumFam.O.dylib", 100),
    ("Fixtures/Sample/libEnumFam.Osize.dylib", 160),
    // f3errors.swift: untyped and typed throws, catches and rethrows.
    ("Fixtures/Sample/libF3Errors.Onone.dylib", 120),
    ("Fixtures/Sample/libF3Errors.O.dylib", 90),
    ("Fixtures/Sample/libF3Errors.Osize.dylib", 85),
    // f4closures.swift: function values built and invoked through an
    // opaque invoker.
    ("Fixtures/Sample/libF4.Onone.dylib", 95),
    ("Fixtures/Sample/libF4.O.dylib", 80),
    ("Fixtures/Sample/libF4.Osize.dylib", 120),
    // f6classes.swift: stored properties, vtable and static dispatch.
    ("Fixtures/Sample/libF6Classes.Onone.dylib", 165),
    ("Fixtures/Sample/libF6Classes.O.dylib", 165),
    ("Fixtures/Sample/libF6Classes.Osize.dylib", 240),
    // genexuse.swift: callers of generic functions, protocol witnesses and
    // existentials defined in another image, genexlib.swift. The library
    // itself is built and not listed: its returns are field reads and
    // calls, and no arithmetic mutation of the tracer turned its sweep
    // red, so listing it would guard nothing.
    ("Fixtures/Sample/libGenExUse.Onone.dylib", 25),
    ("Fixtures/Sample/libGenExUse.O.dylib", 25),
    ("Fixtures/Sample/libGenExUse.Osize.dylib", 25),
]

@Test(arguments: families.map(\.image))
func aFixtureFamilysReturnsAgreeWithTheEmulatorIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = String(path.dropFirst("Fixtures/Sample/".count))
    // No emulator (Unicorn not installed): the enforcing suite names it.
    guard let sweep = try await sweepAgainstEmulator(image) else { return }
    let floor = try #require(families.first { $0.image == path }).returns
    #expect(sweep.mismatches.isEmpty, "false statements:\n\(sweep.mismatches.sorted { $0.key < $1.key }.prefix(8).map { "\($0.key): \($0.value.first ?? "")" }.joined(separator: "\n"))")
    #expect(sweep.returnsChecked >= floor, "checked \(sweep.returnsChecked) returns in \(image)")
}
