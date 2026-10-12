import ArgumentParser
import Foundation
import SwiftDecompilerCore

/// `--probe` and its filters, shared by the commands that analyse code.
struct ProbeOptions: ParsableArguments {
    @Option(name: .customLong("probe"), help: ArgumentHelp(
        "Write instrumentation events as JSON lines to this file ('-' for stderr), then a summary line.",
        discussion: "Schema \(ProbeRecorder.schema); events are listed in docs/INSTRUMENTATION.md."))
    var path: String?

    @Option(name: .customLong("probe-filter"), help: ArgumentHelp(
        "Keep only matching events in the trace (counts still cover everything): "
            + "comma-separated subsystem=, category=, event=, function=, address=<lo>-<hi>. "
            + "Repeat a key with | (category=decline|limit)."))
    var filter: String?

    @Flag(name: .customLong("probe-names"), help: "Write names read from the binary (symbols, types) into the trace; by default each is replaced by a stable hash.")
    var names = false

    @Flag(name: .customLong("probe-summary"), help: "Write only the summary line (counts, times, validator violations).")
    var summaryOnly = false

    /// Runs `body` under a recorder when `--probe` was given.
    func run<T>(_ body: () async throws -> T) async throws -> T {
        guard let path else { return try await body() }
        let handle: FileHandle
        if path == "-" {
            handle = FileHandle.standardError
        } else {
            guard FileManager.default.createFile(atPath: path, contents: nil) else {
                throw ValidationError("Cannot create --probe file '\(path)'.")
            }
            handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        }
        let output: ProbeRecorder.Output = summaryOnly
            ? .summaryOnly
            : .jsonLines { line in handle.write(Data((line + "\n").utf8)) }
        let recorder = ProbeRecorder(filter: try parsedFilter(), output: output, includeNames: names)
        let result = try await Probe.recording(recorder, body)
        handle.write(Data((recorder.summaryLine() + "\n").utf8))
        if path != "-" { try handle.close() }
        return result
    }

    func parsedFilter() throws -> ProbeFilter {
        var filter = ProbeFilter()
        guard let spec = self.filter, !spec.isEmpty else { return filter }
        for clause in spec.split(separator: ",") {
            let parts = clause.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw ValidationError("--probe-filter: expected key=value, got '\(clause)'.") }
            let values = parts[1].split(separator: "|").map(String.init)
            switch parts[0] {
            case "subsystem":
                filter.subsystems = Set(try values.map { value in
                    guard let subsystem = ProbeEvent.Subsystem(rawValue: value) else {
                        throw ValidationError("--probe-filter: unknown subsystem '\(value)' (\(ProbeEvent.Subsystem.allCases.map(\.rawValue).joined(separator: ", "))).")
                    }
                    return subsystem
                })
            case "category":
                filter.categories = Set(try values.map { value in
                    guard let category = ProbeEvent.Category(rawValue: value) else {
                        throw ValidationError("--probe-filter: unknown category '\(value)' (\(ProbeEvent.Category.allCases.map(\.rawValue).joined(separator: ", "))).")
                    }
                    return category
                })
            case "event":
                filter.events = Set(values)
            case "function":
                filter.function = parts[1]
            case "address":
                let bounds = parts[1].split(separator: "-").map { UInt64($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
                guard bounds.count == 2, let low = bounds[0], let high = bounds[1], low <= high else {
                    throw ValidationError("--probe-filter: address wants <lo>-<hi> in hex, got '\(parts[1])'.")
                }
                filter.addresses = low...high
            default:
                throw ValidationError("--probe-filter: unknown key '\(parts[0])' (subsystem, category, event, function, address).")
            }
        }
        return filter
    }
}
