import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Same input, same output — a production requirement, since diffing two builds
/// of a binary is a primary use of this tool and spurious reordering makes that
/// worthless.
///
/// Why subprocesses. Swift seeds `Hasher` **per process**, so `Set` and
/// `Dictionary` iteration order is permuted between runs but *constant within*
/// one. Repeating a call in-process would therefore prove nothing: it would
/// reuse the same seed and reorder nothing. Verified on this toolchain — a
/// 12-element `Set` prints in three different orders across three processes.
///
/// What this actually guards. The decompiler has **no concurrent fan-out** (no
/// task groups, no `async let`, no `Task {}`, no `concurrentPerform`; the one
/// worker thread is joined before its result is read), so scheduling is not a
/// source of variation. The real dependency is the ~16 explicit `.sorted()`
/// calls placed where an unordered collection reaches output. Nothing enforces
/// them: emitting straight from a `Dictionary` or `Set` in a future change
/// would reorder output silently, and only a cross-process comparison notices.

private let binary = URL(fileURLWithPath: ".build/debug/swiftdc")

/// Cases chosen to cover distinct pipelines rather than one convenient path:
/// Swift metadata, the ObjC index, field layout, and the call graph. Each runs
/// in well under a tenth of a second, so repeating them is cheap.
private let cases: [(label: String, arguments: [String])] = [
    ("dump", ["dump", "Fixtures/Sample/libSample.dylib"]),
    ("interface", ["interface", "Fixtures/Sample/libSample.dylib"]),
    ("objc --methods", ["objc", "Fixtures/Sample/libSample.dylib", "--methods"]),
    ("layout", ["layout", "Fixtures/Sample/libSample.dylib"]),
    // The call graph is the likeliest place for iteration order to leak: it is
    // built from dictionaries keyed by address, and `--unreferenced` is a set
    // difference.
    ("xrefs --unreferenced", ["xrefs", "Fixtures/Sample/libReconstruction.dylib", "--unreferenced"]),
    ("disasm --structured", ["disasm", "Fixtures/Sample/libSample.dylib", "--structured"]),
]

private func capture(_ arguments: [String]) throws -> Data {
    let output = Pipe()
    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return data
}

@Test func outputIsIdenticalAcrossProcessesIfPresent() throws {
    guard FileManager.default.fileExists(atPath: binary.path),
          FileManager.default.fileExists(atPath: "Fixtures/Sample/libSample.dylib")
    else { return }

    var compared: [String] = []
    for (label, arguments) in cases {
        let first = try capture(arguments)
        // Non-empty is part of the assertion: comparing two empty outputs would
        // pass while proving nothing, which is the failure mode this project
        // keeps hitting.
        guard !first.isEmpty else {
            Issue.record("\(label): produced no output, so determinism was not exercised")
            continue
        }
        for attempt in 2...4 {
            let next = try capture(arguments)
            #expect(
                next == first,
                """
                \(label): run \(attempt) differs from run 1 \
                (\(first.count) vs \(next.count) bytes). Output is not reproducible \
                across processes — most likely an unordered Set/Dictionary reaching \
                output without a `.sorted()`.
                """
            )
        }
        compared.append(label)
    }

    // Named, not counted. If the fixtures stop building, every case would skip
    // and an empty pass would look like success.
    #expect(
        compared.contains("xrefs --unreferenced") || compared.isEmpty,
        "expected the call-graph case among those compared, got \(compared)"
    )
}

/// The premise the test above rests on: iteration order really does vary between
/// processes on this toolchain. If a future toolchain made hashing deterministic
/// by default, the guard would still pass while having lost its power, and that
/// should be visible rather than silent.
@Test func hashOrderVariesBetweenProcessesOnThisToolchain() throws {
    let script = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-hashseed-\(ProcessInfo.processInfo.processIdentifier).swift")
    try """
    var set = Set<String>()
    for index in 0 ..< 32 { set.insert("key\\(index)") }
    print(set.joined(separator: ","))
    """.write(to: script, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: script) }

    var orders: Set<String> = []
    for _ in 0 ..< 4 {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swift", script.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }   // no toolchain here
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return }
        orders.insert(String(decoding: data, as: UTF8.self))
    }

    guard !orders.isEmpty else { return }
    #expect(
        orders.count > 1,
        """
        Set iteration order was identical across \(orders.count) process(es). \
        Per-process hash seeding is what gives `outputIsIdenticalAcrossProcesses` \
        its power; without it that test still passes but no longer detects \
        unordered iteration reaching output.
        """
    )
}
