import Testing
import Foundation
@testable import SwiftDecompilerCore
import MachOKit

/// `declaredFunctionCount` is the **oracle** the empty-result rule leans on: an
/// empty parse throws when it disagrees, and an unfiltered run warns when
/// recovery falls under half of it. An oracle that is itself wrong quietly
/// miscalibrates both.
///
/// It was wrong. `LC_FUNCTION_STARTS` is a ULEB128 list of *deltas*, zero-padded
/// to alignment, and each padding byte decodes as a delta of zero — i.e. "another
/// function at the same address". The raw list therefore ends in a run of
/// repeats, and the count was inflated by that run.
///
/// The check here is against an **independent** tool rather than against a
/// number written down by the same reasoning that produced the bug: Apple's own
/// `dyld_info -function_starts`. Comparing swiftdc to itself is what made the
/// first byte-coverage measurement in this area vacuous.

private let fixtures = [
    "Fixtures/Sample/libReconstruction.dylib",
    "Fixtures/Sample/sample.release",
    "Fixtures/Sample/libSample.dylib",
    "Fixtures/Sample/sample.stripped",
]

/// Function-start count according to `dyld_info`, or nil when the tool or the
/// fixture is unavailable (a clean checkout, or a machine without Xcode's tools).
private func dyldInfoFunctionStarts(_ path: String) -> Int? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["dyld_info", "-function_starts", path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }

    let text = String(decoding: data, as: UTF8.self)
    let count = text.split(separator: "\n")
        .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("0x") }
        .count
    return count > 0 ? count : nil
}

@Test func declaredFunctionCountMatchesAnIndependentToolIfPresent() throws {
    var compared: [String] = []
    for path in fixtures {
        guard let expected = dyldInfoFunctionStarts(path),
              let machO = try? BinaryLoader.load(path: path)
        else { continue }

        let actual = Disassembler(preset: .default).declaredFunctionCount(in: machO)
        #expect(
            actual == expected,
            """
            \((path as NSString).lastPathComponent): declaredFunctionCount reported \(actual), \
            but `dyld_info -function_starts` lists \(expected). The oracle behind the \
            empty-result rule must agree with the binary's own table.
            """
        )
        compared.append((path as NSString).lastPathComponent)
    }

    // Naming what was compared, not just counting: if the fixtures stop building
    // or `dyld_info` disappears, this test would otherwise pass having checked
    // nothing at all.
    #expect(
        compared.count >= 2 || compared.isEmpty,
        "only \(compared.count) fixture(s) compared: \(compared)"
    )
}

@Test func declaredFunctionCountHasNoDuplicatesIfPresent() throws {
    // The direct statement of the defect, independent of any external tool: the
    // table's trailing zero-deltas must not be counted as extra functions.
    for path in fixtures {
        guard FileManager.default.fileExists(atPath: path),
              let machO = try? BinaryLoader.load(path: path),
              let raw = machO.functionStarts
        else { continue }

        let rawValues = raw.map { UInt64($0.offset) }
        let distinct = Set(rawValues).count
        let reported = Disassembler(preset: .default).declaredFunctionCount(in: machO)

        #expect(
            reported == distinct,
            "\((path as NSString).lastPathComponent): reported \(reported), distinct \(distinct), raw \(rawValues.count)"
        )
        // Adversarial: the fixtures must actually EXHIBIT padding, or this test
        // proves nothing. If a future toolchain stops padding the table, this
        // fires and the test should be re-grounded rather than deleted.
        if rawValues.count == distinct {
            Issue.record(
                """
                \((path as NSString).lastPathComponent) has no repeated function starts, \
                so it no longer exercises the padding case this test exists for.
                """
            )
        }
    }
}
