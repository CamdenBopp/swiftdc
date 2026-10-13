import ArgumentParser
import CryptoKit
import Foundation
import SwiftDecompilerCore

/// An explicit run, not a background schedule: compile, execute the native
/// oracle, score each presentation/entry path, retain evidence and summarize
/// the next unknown/refuted sites. Unknowns never become successful cases.
struct ResearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "research", abstract: "Run a repeatable native integer-fixture research loop across compiler and decompiler modes.")
    @Option(help: "Directory for versioned evidence. Each run gets a fresh subdirectory.") var output = "work/research"
    @Option(help: "Authored scalar fixture source; run from the repository root by default.") var fixtureSource = "Fixtures/Sample/researchinteger.swift"
    @Option(help: "Deterministic SplitMix64 seed; integer edge cases are always included.") var seed: UInt64 = 1
    @Option(help: "Fresh input batches per optimization level.") var iterations = 1
    @Option(help: "Additional deterministic random inputs per batch.") var randomInputs = 16
    func validate() throws {
        guard (1...100).contains(iterations), (0...10000).contains(randomInputs) else {
            throw ValidationError("iterations must be 1...100 and random-inputs 0...10000")
        }
    }
    func run() async throws {
        let directory = URL(fileURLWithPath: output).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: fixtureSource).standardizedFileURL
        let sourceData = try Data(contentsOf: source)
        let snapshot = directory.appendingPathComponent("fixture.swift")
        var evidence = ResearchEvidence(source: source.path, sourceSHA256: digest(sourceData), seed: seed,
                                        iterations: iterations, randomInputs: randomInputs,
                                        decompilerSHA256: try digest(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0]))),
                                        workingDiffSHA256: digest(Data(try process("/usr/bin/git", ["diff", "--binary"]).text.utf8)),
                                        toolchain: try process("/usr/bin/xcrun", ["swiftc", "--version"]).text,
                                        revision: try process("/usr/bin/git", ["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines))
        try sourceData.write(to: snapshot)
        // A failed/partial run can never leave an old success marker behind.
        try save(evidence, to: directory.appendingPathComponent("research.json"))
        for iteration in 0..<iterations {
            let inputs = ResearchFixtures.inputs(seed: seed &+ UInt64(iteration), randomCount: randomInputs)
            for (baseModule, optimization) in zip(ResearchFixtures.modules, ["-Onone", "-O", "-Osize"]) {
                let module = baseModule + "_R\(iteration)"
                let binary = directory.appendingPathComponent("\(module).dylib")
                _ = try process("/usr/bin/xcrun", ["swiftc", "-parse-as-library", optimization, "-emit-library",
                                                  "-module-name", module, snapshot.path, "-o", binary.path])
                let oracle = try ResearchFixtures.oracle(path: binary.path, module: module, inputs: inputs)
                try save(oracle, to: directory.appendingPathComponent("\(module).oracle.json"))
                let assembly = try process("/usr/bin/xcrun", ["llvm-objdump", "--macho", "--disassemble", binary.path]).text
                try assembly.write(to: directory.appendingPathComponent("\(module).asm"), atomically: true, encoding: .utf8)
                let binaryHash = try digest(Data(contentsOf: binary))
                let machO = try BinaryLoader.loadMachO(path: binary.path)
                for preset in DemanglePreset.allCases {
                    for streaming in [false, true] {
                        let score = try ProbeScore(oracle: oracle)
                        let recorder = score.recorder
                        await Probe.recording(recorder) {
                            let disassembler = Disassembler(preset: preset)
                            if streaming {
                                let _: [Void] = await disassembler.disassembleStreaming(machO: machO) { _ = $0.renderStructured() }
                            } else {
                                for function in await disassembler.disassemble(machO: machO) { _ = function.renderStructured() }
                            }
                        }
                        let report = try score.report()
                        let label = "\(module).\(preset.rawValue).\(streaming ? "stream" : "array")"
                        try report.json().write(to: directory.appendingPathComponent(label + ".score.json"), atomically: true, encoding: .utf8)
                        try recorder.summaryLine().write(to: directory.appendingPathComponent(label + ".probes.json"), atomically: true, encoding: .utf8)
                        evidence.runs.append(.init(label: label, optimization: optimization, preset: preset.rawValue,
                                                   streaming: streaming, binarySHA256: binaryHash,
                                                   binaryUUID: oracle.binaryUUID!, counts: report.counts,
                                                   coverage: report.coverage, agreement: report.agreement,
                                                   findings: report.results.filter { $0.outcome != .verified }.map {
                            .init(id: $0.expectation.id!, outcome: $0.outcome.rawValue, reason: $0.reason, actual: $0.actual)
                        }))
                        try save(evidence, to: directory.appendingPathComponent("research.json"))
                        let counts = ["verified", "refuted", "not-evaluated", "missing"].map { "\($0)=\(report.counts[$0] ?? 0)" }.joined(separator: " ")
                        print("\(label): \(counts)")
                    }
                }
            }
        }
        evidence.completed = true
        try save(evidence, to: directory.appendingPathComponent("research.json"))
        print("Research evidence: \(directory.path)")
        if evidence.runs.contains(where: { ($0.counts["refuted"] ?? 0) > 0 }) { throw ExitCode(1) }
        // Research intentionally keeps discoveries of unsupported recovery.
        // Success means the exploration completed, never that coverage was 100%.
    }
}
private struct ResearchEvidence: Encodable {
    let schema = "swiftdc-research/1"
    let scope = "authored UInt64 -> UInt64 samples; no app-wide accuracy claim"
    let source: String
    let sourceSHA256: String
    let seed: UInt64
    let iterations: Int
    let randomInputs: Int
    let decompilerSHA256: String
    let workingDiffSHA256: String
    let toolchain: String
    let revision: String
    var completed = false
    var runs: [Run] = []
    struct Run: Encodable {
        let label: String; let optimization: String; let preset: String; let streaming: Bool
        let binarySHA256: String; let binaryUUID: String; let counts: [String: Int]
        let coverage: Double; let agreement: Double?; let findings: [Finding]
    }
    struct Finding: Encodable { let id: String; let outcome: String; let reason: String?; let actual: String? }
}
private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func save<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
}
private func process(_ executable: String, _ arguments: [String]) throws -> (text: String, status: Int32) {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
    task.standardOutput = pipe; task.standardError = FileHandle.standardError
    try task.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
    guard task.terminationStatus == 0 else { throw ValidationError("research command failed: \(arguments.first ?? executable)") }
    return (String(decoding: data, as: UTF8.self), task.terminationStatus)
}
