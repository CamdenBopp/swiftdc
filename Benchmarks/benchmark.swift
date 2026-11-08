#!/usr/bin/env swift
import CryptoKit
import Darwin
import Foundation

// Native Swift benchmark harness. One discarded warm-up, then warm min/median;
// every timed output AND exit status is checked for repeatability.
struct Binary { let key: String; let path: String; let label: String; let fixture: Bool }
struct Axis {
    let key: String; let title: String; let swiftdc: [String]; let ipsw: [String]; let includeSelf: Bool
}
struct Measurement: Codable {
    let tool: String; let axis: String; let binary: String; let argv: [String]
    var ok = false; var exit_code: Int32?; var times_s: [Double] = []
    var min_s: Double?; var median_s: Double?; var stdout_bytes = 0; var stdout_lines = 0
    var deterministic: Bool?; var note = ""
}
enum HarnessError: Error { case invalid(String), timeout }
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func resolve(_ path: String) -> String { root.appendingPathComponent(path).path }
func find(_ name: String) -> String? {
    (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        .map { String($0) + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
}
func duration(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now).components
    return Double(d.seconds) + Double(d.attoseconds) / 1e18
}
func run(_ argv: [String]) throws -> (Int32, Data, Double) {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-bench-" + UUID().uuidString)
    FileManager.default.createFile(atPath: scratch.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let output = try FileHandle(forWritingTo: scratch)
    defer { try? output.close() }
    let p = Process(), finished = DispatchSemaphore(value: 0)
    p.executableURL = URL(fileURLWithPath: argv[0]); p.arguments = Array(argv.dropFirst())
    p.currentDirectoryURL = root; p.standardOutput = output; p.standardError = FileHandle.nullDevice
    p.terminationHandler = { _ in finished.signal() }
    let start = ContinuousClock.now; try p.run()
    if finished.wait(timeout: .now() + 180) == .timedOut {
        p.terminate()
        if finished.wait(timeout: .now() + 2) == .timedOut { kill(p.processIdentifier, SIGKILL); finished.wait() }
        throw HarnessError.timeout
    }
    let elapsed = duration(start)
    return (p.terminationStatus, try Data(contentsOf: scratch), elapsed)
}
func text(_ argv: [String]) -> String { (try? run(argv)).map { String(decoding: $0.1, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "unknown" }
func main() throws {
    var runs = 5, quick = false, destination = root.appendingPathComponent("Benchmarks")
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--help", "-h": print("swift Benchmarks/benchmark.swift [--quick] [--runs N] [--out-dir PATH]"); return
        case "--quick": quick = true
        case "--runs":
            guard !args.isEmpty, let n = Int(args.removeFirst()), n > 0 else { throw HarnessError.invalid("--runs requires a positive integer") }; runs = n
        case "--out-dir":
            guard !args.isEmpty else { throw HarnessError.invalid("--out-dir requires a path") }
            destination = URL(fileURLWithPath: args.removeFirst())
        default: throw HarnessError.invalid("unknown option: \(arg)")
        }
    }
    guard let dc = [resolve(".build/release/swiftdc"), resolve(".build/debug/swiftdc")].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        throw HarnessError.invalid("swiftdc not built; run swift build -c release")
    }
    guard let ipsw = find("ipsw") else { throw HarnessError.invalid("ipsw not on PATH; install with brew install ipsw") }
    let binaries = [
        Binary(key: "recon.opt.stripped", path: resolve("Fixtures/Sample/libReconstruction.opt.stripped.dylib"), label: "Reconstruction, -O, stripped", fixture: true),
        Binary(key: "sample", path: resolve("Fixtures/Sample/libSample.dylib"), label: "Sample dylib, -Onone", fixture: true),
        Binary(key: "recon.opt", path: resolve("Fixtures/Sample/libReconstruction.opt.dylib"), label: "Reconstruction, -O", fixture: true),
        Binary(key: "recon", path: resolve("Fixtures/Sample/libReconstruction.dylib"), label: "Reconstruction, -Onone", fixture: true),
        Binary(key: "recon.resilient", path: resolve("Fixtures/Sample/libReconstruction.resilient.dylib"), label: "Reconstruction, library-evolution", fixture: true),
        Binary(key: "swiftdc.self", path: dc, label: "swiftdc itself", fixture: false)
    ].filter { FileManager.default.fileExists(atPath: $0.path) && (!quick || $0.fixture) }
    let axes = [
        Axis(key: "swift", title: "Swift declarations", swiftdc: ["dump"], ipsw: ["macho", "info", "--swift", "--demangle", "--no-color"], includeSelf: true),
        Axis(key: "objc", title: "Objective-C headers", swiftdc: ["objc"], ipsw: ["macho", "info", "--objc", "--no-color"], includeSelf: true),
        Axis(key: "disasm", title: "ARM64 disassembly (whole __text)", swiftdc: ["disasm"], ipsw: ["macho", "disass", "--section", "__TEXT.__text", "--no-color"], includeSelf: false)
    ]
    guard !binaries.isEmpty else { throw HarnessError.invalid("no benchmark binaries; build Fixtures/Sample/build.sh") }
    let outputs = destination.appendingPathComponent("outputs")
    try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
    var measurements: [Measurement] = []
    for axis in axes {
        for binary in binaries where binary.fixture || axis.includeSelf {
            for (tool, executable, options) in [("swiftdc", dc, axis.swiftdc), ("ipsw", ipsw, axis.ipsw)] {
                let argv = [executable] + options + [binary.path]
                var m = Measurement(tool: tool, axis: axis.key, binary: binary.key, argv: argv.map {
                    $0 == ipsw ? "ipsw" : $0.replacingOccurrences(of: root.path + "/", with: "")
                })
                do {
                    let (code, first, _) = try run(argv)
                    m.exit_code = code; m.stdout_bytes = first.count; m.stdout_lines = first.filter { $0 == 10 }.count
                    m.deterministic = true
                    guard code == 0 else { throw HarnessError.invalid("exit \(code)") }
                    let digest = SHA256.hash(data: first)
                    try first.write(to: outputs.appendingPathComponent("\(binary.key).\(axis.key).\(tool).txt"))
                    for _ in 0..<runs {
                        let (nextCode, out, elapsed) = try run(argv)
                        m.times_s.append(elapsed)
                        if nextCode != code || SHA256.hash(data: out) != digest { m.deterministic = false }
                        guard nextCode == 0 else { throw HarnessError.invalid("timed run exited \(nextCode)") }
                    }
                    let sorted = m.times_s.sorted()
                    m.min_s = sorted.first
                    m.median_s = sorted.count % 2 == 0 ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
                    m.ok = true
                } catch { m.note = String(describing: error) }
                print("\(axis.key) \(binary.key) \(tool): \(m.ok ? String(format: "%.1f ms", m.min_s! * 1000) : m.note)")
                measurements.append(m)
            }
        }
    }
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
    let env: [String: String] = [
        "date": formatter.string(from: Date()), "machine": text(["/usr/sbin/sysctl", "-n", "hw.machine"]),
        "cpu": text(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"]),
        "macos": text(["/usr/bin/sw_vers", "-productVersion"]),
        "swiftdc_path": dc.replacingOccurrences(of: root.path + "/", with: ""),
        "swiftdc_build": dc.contains("release") ? "release" : "debug",
        "swiftdc_commit": text(["/usr/bin/git", "-C", root.path, "rev-parse", "--short", "HEAD"]),
        "ipsw_version": text([ipsw, "version"]), "runs": String(runs), "harness": "swift/1"
    ]
    struct Report: Encodable { let env: [String: String]; let results: [Measurement] }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(Report(env: env, results: measurements)).write(to: destination.appendingPathComponent("results.json"))
    var lines = ["# swiftdc vs ipsw — benchmark results\n", "_Generated by `Benchmarks/benchmark.swift`. See [README.md](README.md) for methodology._\n", "## Environment\n"]
    lines += env.keys.sorted().map { "- \($0): \(env[$0]!)" }; lines.append("")
    func ms(_ m: Measurement?) -> String { m.map { $0.ok ? String(format: "%.1f ms", $0.min_s! * 1000) : $0.note } ?? "—" }
    for axis in axes {
        lines += ["## \(axis.title)\n", "| binary | swiftdc | ipsw | speedup | swiftdc lines | ipsw lines |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
        for b in binaries where b.fixture || axis.includeSelf {
            let s = measurements.first { $0.binary == b.key && $0.axis == axis.key && $0.tool == "swiftdc" }
            let i = measurements.first { $0.binary == b.key && $0.axis == axis.key && $0.tool == "ipsw" }
            var speed = "—"
            if let s, let i, s.ok, i.ok, let st = s.min_s, let it = i.min_s, st > 0, it > 0 {
                let ratio = it / st
                speed = String(format: "%.1f× %@", ratio >= 1 ? ratio : 1 / ratio, ratio >= 1 ? "swiftdc" : "ipsw")
            }
            lines.append("| \(b.label) | \(ms(s)) | \(ms(i)) | \(speed) | \(s?.stdout_lines ?? 0) | \(i?.stdout_lines ?? 0) |")
        }
        lines.append("")
    }
    lines += ["## Determinism\n"]
    let changed = measurements.filter { $0.deterministic == false }
    lines += changed.isEmpty ? ["Every successful run produced byte-identical output across all repeats."]
        : changed.map { "- **non-deterministic**: \($0.tool) \($0.axis) \($0.binary)" }
    try lines.joined(separator: "\n").write(to: destination.appendingPathComponent("RESULTS.md"), atomically: true, encoding: .utf8)
    print("wrote \(destination.path)/RESULTS.md and results.json")
}
do { try main() }
catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2) }
