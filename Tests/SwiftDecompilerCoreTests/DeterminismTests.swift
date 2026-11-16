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
/// What this actually guards. The one concurrent fan-out is pass 2 of a
/// standalone image's streamed views, which analyses functions across the
/// cores and hands them on in input order; `parallelAnalysisMatchesSerial`
/// compares it with the serial loop (`SWIFTDC_SERIAL`). Otherwise scheduling
/// is not a source of variation. The real dependency is the ~16 explicit `.sorted()`
/// calls placed where an unordered collection reaches output. Nothing enforces
/// them: emitting straight from a `Dictionary` or `Set` in a future change
/// would reorder output silently, and only a cross-process comparison notices.

private let binary = URL(fileURLWithPath: ".build/debug/swiftdc")

/// Cases chosen to cover distinct pipelines rather than one convenient path:
/// Swift metadata, the ObjC index, field layout, and the call graph. Each runs
/// in well under a tenth of a second, so repeating them is cheap.
private let cases: [(label: String, arguments: [String])] = [
    ("disasm --structured callee stack lifetime", ["disasm", "Fixtures/Sample/libStackLifetime.dylib", "--structured"]),
    ("disasm --pseudo callee stack lifetime", ["disasm", "Fixtures/Sample/libStackLifetime.dylib", "--pseudo"]),
    ("disasm listing callee stack lifetime", ["disasm", "Fixtures/Sample/libStackLifetime.dylib"]),
    ("disasm --json callee stack lifetime", ["disasm", "Fixtures/Sample/libStackLifetime.dylib", "--json"]),
    ("disasm --structured possible FP reach", ["disasm", "Fixtures/Sample/libFrameMay.dylib", "--structured"]),
    ("disasm --pseudo possible FP reach", ["disasm", "Fixtures/Sample/libFrameMay.dylib", "--pseudo"]),
    ("disasm listing possible FP reach", ["disasm", "Fixtures/Sample/libFrameMay.dylib"]),
    ("disasm --json possible FP reach", ["disasm", "Fixtures/Sample/libFrameMay.dylib", "--json"]),
    ("disasm --structured indirect retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.indirect.dylib", "--structured"]),
    ("disasm --pseudo indirect retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.indirect.dylib", "--pseudo"]),
    ("disasm listing indirect retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.indirect.dylib"]),
    ("disasm --json indirect retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.indirect.dylib", "--json"]),
    ("disasm --structured legacy indirect retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.legacy.indirect.dylib", "--structured"]),
    ("disasm --pseudo legacy indirect retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.legacy.indirect.dylib", "--pseudo"]),
    ("disasm listing legacy indirect retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.legacy.indirect.dylib"]),
    ("disasm --json legacy indirect retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.legacy.indirect.dylib", "--json"]),
    ("disasm --structured legacy retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.legacy.dylib", "--structured"]),
    ("disasm --pseudo legacy retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.legacy.dylib", "--pseudo"]),
    ("disasm listing legacy retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.legacy.dylib"]),
    ("disasm --json legacy retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.legacy.dylib", "--json"]),
    ("disasm --structured retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.dylib", "--structured"]),
    ("disasm --pseudo retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.dylib", "--pseudo"]),
    ("disasm listing retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.dylib"]),
    ("disasm --json retained result identity", ["disasm", "Fixtures/Sample/libResultIdentity.dylib", "--json"]),
    ("disasm --structured local ARC twin", ["disasm", "Fixtures/Sample/libArcOriginLocal.O.dylib", "--structured"]),
    ("disasm --pseudo local ARC twin", ["disasm", "Fixtures/Sample/libArcOriginLocal.O.dylib", "--pseudo"]),
    ("disasm listing local ARC twin", ["disasm", "Fixtures/Sample/libArcOriginLocal.O.dylib"]),
    ("disasm --json local ARC twin", ["disasm", "Fixtures/Sample/libArcOriginLocal.O.dylib", "--json"]),
    ("disasm --structured foreign ARC twin", ["disasm", "Fixtures/Sample/libArcOriginImport.O.dylib", "--structured"]),
    ("disasm --pseudo foreign ARC twin", ["disasm", "Fixtures/Sample/libArcOriginImport.O.dylib", "--pseudo"]),
    ("disasm listing foreign ARC twin", ["disasm", "Fixtures/Sample/libArcOriginImport.O.dylib"]),
    ("disasm --json foreign ARC twin", ["disasm", "Fixtures/Sample/libArcOriginImport.O.dylib", "--json"]),
    ("disasm --structured query identity", ["disasm", "Fixtures/Sample/libUniquenessResult.O.dylib", "--structured"]),
    ("disasm --pseudo query identity", ["disasm", "Fixtures/Sample/libUniquenessResult.O.dylib", "--pseudo"]),
    ("disasm listing query identity", ["disasm", "Fixtures/Sample/libUniquenessResult.O.dylib"]),
    ("disasm --json query identity", ["disasm", "Fixtures/Sample/libUniquenessResult.O.dylib", "--json"]),
    ("disasm --structured query object identity", ["disasm", "Fixtures/Sample/libFactorySnapshot.O.dylib", "--structured"]),
    ("disasm --pseudo query object identity", ["disasm", "Fixtures/Sample/libFactorySnapshot.O.dylib", "--pseudo"]),
    ("disasm listing query object identity", ["disasm", "Fixtures/Sample/libFactorySnapshot.O.dylib"]),
    ("disasm --json query object identity", ["disasm", "Fixtures/Sample/libFactorySnapshot.O.dylib", "--json"]),
    ("disasm --structured resilient operator ABI", ["disasm", "Fixtures/Sample/libResilientOperator.O.dylib", "--structured"]),
    ("disasm --pseudo resilient operator ABI", ["disasm", "Fixtures/Sample/libResilientOperator.O.dylib", "--pseudo"]),
    ("disasm listing resilient operator ABI", ["disasm", "Fixtures/Sample/libResilientOperator.O.dylib"]),
    ("disasm --json resilient operator ABI", ["disasm", "Fixtures/Sample/libResilientOperator.O.dylib", "--json"]),
    ("disasm --structured operator arity", ["disasm", "Fixtures/Sample/libOperatorArity.O.dylib", "--structured"]),
    ("disasm --pseudo operator arity", ["disasm", "Fixtures/Sample/libOperatorArity.O.dylib", "--pseudo"]),
    ("disasm listing operator arity", ["disasm", "Fixtures/Sample/libOperatorArity.O.dylib"]),
    ("disasm --json operator arity", ["disasm", "Fixtures/Sample/libOperatorArity.O.dylib", "--json"]),
    ("dump", ["dump", "Fixtures/Sample/libSample.dylib"]),
    ("interface", ["interface", "Fixtures/Sample/libSample.dylib"]),
    ("objc --methods", ["objc", "Fixtures/Sample/libSample.dylib", "--methods"]),
    ("layout", ["layout", "Fixtures/Sample/libSample.dylib"]),
    // The call graph is the likeliest place for iteration order to leak: it is
    // built from dictionaries keyed by address, and `--unreferenced` is a set
    // difference.
    ("xrefs --unreferenced", ["xrefs", "Fixtures/Sample/libReconstruction.dylib", "--unreferenced"]),
    ("disasm --structured", ["disasm", "Fixtures/Sample/libSample.dylib", "--structured"]),
    // Loops in catch handlers tie for immediate post-dominator; the tie was
    // broken by hash order (five outputs in six runs before the fix).
    ("disasm --structured landing pads", ["disasm", "Fixtures/Sample/libLandingPadLoop.dylib", "--structured"]),
    // Physical register iteration now comes from the shared fact owner.
    // Keep its native copy/writeback fixture reproducible in every view.
    ("disasm --structured register facts", ["disasm", "Fixtures/Sample/libFrameRegisterModel.dylib", "--structured"]),
    ("disasm --pseudo register facts", ["disasm", "Fixtures/Sample/libFrameRegisterModel.dylib", "--pseudo"]),
    ("disasm listing register facts", ["disasm", "Fixtures/Sample/libFrameRegisterModel.dylib"]),
    ("disasm --json register facts", ["disasm", "Fixtures/Sample/libFrameRegisterModel.dylib", "--json"]),
    ("disasm --structured frame layout aliases", ["disasm", "Fixtures/Sample/libFrameLayoutAlias.dylib", "--structured"]),
    ("disasm --pseudo frame layout aliases", ["disasm", "Fixtures/Sample/libFrameLayoutAlias.dylib", "--pseudo"]),
    ("disasm listing frame layout aliases", ["disasm", "Fixtures/Sample/libFrameLayoutAlias.dylib"]),
    ("disasm --json frame layout aliases", ["disasm", "Fixtures/Sample/libFrameLayoutAlias.dylib", "--json"]),
    // MAY self slots share the frame-fact owner but retain union at joins.
    // Reconstruction's -Onone initializers spill and reload incoming x20.
    ("disasm --structured MAY self slots", ["disasm", "Fixtures/Sample/libReconstruction.dylib", "--structured"]),
    ("disasm --pseudo MAY self slots", ["disasm", "Fixtures/Sample/libReconstruction.dylib", "--pseudo"]),
    ("disasm listing MAY self slots", ["disasm", "Fixtures/Sample/libReconstruction.dylib"]),
    ("disasm --json MAY self slots", ["disasm", "Fixtures/Sample/libReconstruction.dylib", "--json"]),
    // Result bindings are assigned from producer PCs, including x20 uses and
    // indirect returns whose consumers are separated by an effect.
    ("disasm --structured context results", ["disasm", "Fixtures/Sample/libContextResultUse.opt.dylib", "--structured"]),
    ("disasm --pseudo context results", ["disasm", "Fixtures/Sample/libContextResultUse.opt.dylib", "--pseudo"]),
    ("disasm listing context results", ["disasm", "Fixtures/Sample/libContextResultUse.opt.dylib"]),
    ("disasm --json context results", ["disasm", "Fixtures/Sample/libContextResultUse.opt.dylib", "--json"]),
    ("disasm --structured indirect result order", ["disasm", "Fixtures/Sample/libIndirectResultOrder.opt.dylib", "--structured"]),
    ("disasm --pseudo indirect result order", ["disasm", "Fixtures/Sample/libIndirectResultOrder.opt.dylib", "--pseudo"]),
    ("disasm listing indirect result order", ["disasm", "Fixtures/Sample/libIndirectResultOrder.opt.dylib"]),
    ("disasm --json indirect result order", ["disasm", "Fixtures/Sample/libIndirectResultOrder.opt.dylib", "--json"]),
    ("disasm --structured complete body", ["disasm", "Fixtures/Sample/libCalleeBodyTransfer.opt.dylib", "--structured"]),
    ("disasm --pseudo complete body", ["disasm", "Fixtures/Sample/libCalleeBodyTransfer.opt.dylib", "--pseudo"]),
    ("disasm listing complete body", ["disasm", "Fixtures/Sample/libCalleeBodyTransfer.opt.dylib"]),
    ("disasm --json complete body", ["disasm", "Fixtures/Sample/libCalleeBodyTransfer.opt.dylib", "--json"]),
    ("disasm --structured caller frame aliases", ["disasm", "Fixtures/Sample/libCallerFrameAlias.opt.dylib", "--structured"]),
    ("disasm --pseudo caller frame aliases", ["disasm", "Fixtures/Sample/libCallerFrameAlias.opt.dylib", "--pseudo"]),
    ("disasm listing caller frame aliases", ["disasm", "Fixtures/Sample/libCallerFrameAlias.opt.dylib"]),
    ("disasm --json caller frame aliases", ["disasm", "Fixtures/Sample/libCallerFrameAlias.opt.dylib", "--json"]),
    ("disasm --structured imported receivers", ["disasm", "Fixtures/Sample/libImportedReceiver.opt.dylib", "--structured"]),
    ("disasm --pseudo imported receivers", ["disasm", "Fixtures/Sample/libImportedReceiver.opt.dylib", "--pseudo"]),
    ("disasm listing imported receivers", ["disasm", "Fixtures/Sample/libImportedReceiver.opt.dylib"]),
    ("disasm --json imported receivers", ["disasm", "Fixtures/Sample/libImportedReceiver.opt.dylib", "--json"]),
]

private func capture(_ arguments: [String], environment: [String: String] = [:]) throws -> Data {
    let output = Pipe()
    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    if !environment.isEmpty {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0, "CLI failed for \(arguments)")
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

/// Pass 2 analyses a standalone image's functions concurrently and must give
/// exactly what the serial loop gives. Each case runs both ways in its own
/// process; the fixtures here have from a dozen to a few hundred functions,
/// so several chunks run at once.
@Test func parallelAnalysisMatchesSerialIfPresent() throws {
    guard FileManager.default.fileExists(atPath: binary.path) else { return }
    var compared = 0
    for path in ["Fixtures/Sample/libSample.dylib", "Fixtures/Sample/sample.debug", "Fixtures/Sample/libFieldVTable.dylib",
                 "Fixtures/Sample/libImportedReceiver.opt.dylib", "Fixtures/Sample/libIndirect.dylib"]
    where FileManager.default.fileExists(atPath: path) {
        for view in ["--structured", "--pseudo"] {
            let serial = try capture(["disasm", path, view], environment: ["SWIFTDC_SERIAL": "1"])
            let parallel = try capture(["disasm", path, view])
            #expect(!serial.isEmpty, "\(path) \(view): no output")
            #expect(parallel == serial, "\(path) \(view): parallel pass 2 differs from serial (\(parallel.count) vs \(serial.count) bytes)")
            compared += 1
        }
    }
    #expect(compared == 0 || compared == 10, "compared \(compared) of 10")
}

/// The premise `outputIsIdenticalAcrossProcessesIfPresent` rests on: iteration order really does vary between
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

@Test func returnPathProbeTreesAreIdenticalAcrossProcessesIfPresent() throws {
    let path = "Fixtures/Sample/libResearchOnone.dylib"
    guard FileManager.default.fileExists(atPath: binary.path), FileManager.default.fileExists(atPath: path) else { return }
    var first: [Data]?
    for _ in 0..<4 {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-paths-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let output = try capture(["disasm", path, "-f", "signedRange", "--probe", file.path,
                                  "--probe-filter", "event=render.return-value"])
        #expect(!output.isEmpty)
        let trace = try String(contentsOf: file, encoding: .utf8)
        let paths = try trace.split(separator: "\n").compactMap { line -> Data? in
            let record = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            guard let fields = record?["fields"] as? [String: Any], let path = fields["path"] else { return nil }
            return try JSONSerialization.data(withJSONObject: path, options: [.sortedKeys])
        }
        #expect(!paths.isEmpty)
        if let first { #expect(paths == first) } else { first = paths }
    }
}

/// The probe trace is a deterministic stream too (`seq` numbers the events
/// in the order analysis records them). The argument-layout loop walked a
/// Dictionary of call sites, so `abi.argument-layout` events came out in
/// hash order: the rendered output matched across processes and the trace
/// did not. The summary line carries wall-clock times and is left out.
@Test func argumentLayoutProbeTracesAreIdenticalAcrossProcessesIfPresent() throws {
    let path = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: binary.path), FileManager.default.fileExists(atPath: path) else { return }
    var first: [Substring]?
    for _ in 0..<4 {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-layout-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let output = try capture(["disasm", path, "--pseudo", "--probe", file.path,
                                  "--probe-filter", "event=abi.argument-layout"])
        #expect(!output.isEmpty)
        let trace = try String(contentsOf: file, encoding: .utf8)
        let events = trace.split(separator: "\n").filter { $0.contains("\"event\":\"abi.argument-layout\"") }
        #expect(events.count > 10, "expected argument-layout events to compare, got \(events.count)")
        if let first { #expect(events == first) } else { first = events }
    }
}

/// The async chain pass walked a Dictionary of chains, so its
/// `async.context-escape` events came out in hash order: Chess's first 148
/// trace lines differed between two runs of one binary. `asyncfns.swift`
/// has 15 functions that record them.
@Test func asyncChainProbeTracesAreIdenticalAcrossProcessesIfPresent() throws {
    let path = "Fixtures/Sample/libAsyncFns.dylib"
    guard FileManager.default.fileExists(atPath: binary.path), FileManager.default.fileExists(atPath: path) else { return }
    var first: [Substring]?
    for _ in 0..<4 {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-async-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let output = try capture(["disasm", path, "--pseudo", "--probe", file.path,
                                  "--probe-filter", "event=async.context-escape|async.context-escape-unknown"])
        #expect(!output.isEmpty)
        let trace = try String(contentsOf: file, encoding: .utf8)
        let events = trace.split(separator: "\n").filter { $0.contains("\"event\":\"async.context-escape") }
        #expect(events.count > 10, "expected async context-escape events to compare, got \(events.count)")
        if let first { #expect(events == first) } else { first = events }
    }
}
