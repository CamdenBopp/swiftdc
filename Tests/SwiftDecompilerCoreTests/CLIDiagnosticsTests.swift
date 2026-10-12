import Testing
import Foundation

/// Diagnostics regression. A dyld-cache image that isn't found fails with one
/// shared message, "Use --list-images to see what's available", but only
/// `dump` and `swift-version` accepted that flag: `disasm --list-images` was
/// an "Unknown option" error. Every subcommand that takes `--image` must take
/// `--list-images` too. Drives the built CLI, like the other CLI tests.
struct CLIDiagnosticsTests {
    private static let binary = URL(fileURLWithPath: ".build/debug/swiftdc")

    private func help(_ subcommand: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: Self.binary.path) else { return nil }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = [subcommand, "--help"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func everyImageCommandListsImagesIfPresent() throws {
        guard let top = try help("help") else { return }
        // Subcommand names from the top-level help's SUBCOMMANDS section.
        let names = top.components(separatedBy: "SUBCOMMANDS:").last?
            .split(separator: "\n")
            .compactMap { $0.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) }
            .filter { !$0.isEmpty && $0.first?.isLetter == true && $0 != "See" } ?? []
        #expect(names.contains("disasm"), "\(top)")
        var withImage = 0
        for name in names {
            guard let text = try help(name), text.contains("--image <") else { continue }
            withImage += 1
            #expect(text.contains("--list-images"), "\(name) takes --image but not --list-images")
        }
        #expect(withImage >= 6, "found \(withImage) --image commands")
    }

    /// An empty `--function ""` matched every function in `disasm` and `objc`
    /// and none in `xrefs`, which printed "No function matched ''" and exited
    /// 0. Every subcommand that takes `--function` must refuse it instead.
    @Test func everyFunctionFilterRejectsAnEmptyNameIfPresent() throws {
        guard let top = try help("help") else { return }
        let names = top.components(separatedBy: "SUBCOMMANDS:").last?
            .split(separator: "\n")
            .compactMap { $0.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) }
            .filter { !$0.isEmpty && $0.first?.isLetter == true && $0 != "See" } ?? []
        var withFilter = 0
        for name in names {
            guard let text = try help(name), text.contains("--function <") else { continue }
            withFilter += 1
            let pipe = Pipe()
            let process = Process()
            process.executableURL = Self.binary
            process.arguments = [name, "Fixtures/Sample/libSample.dylib", "--function", ""]
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            #expect(process.terminationStatus != 0, "\(name) accepted an empty --function: \(output.prefix(200))")
            #expect(output.contains("--function needs a name"), "\(name): \(output.prefix(200))")
        }
        #expect(withFilter >= 3, "found \(withFilter) --function commands")
    }
}

/// The empty-result rule for `analyze`. Disassembly was `try?`-ed into an
/// empty list, so when llvm-objdump could not run, `analyze` printed
/// `(no functions recovered)` and exited 0, while `disasm` on the same file
/// exited 1. The declarations still print; the failure is stated and fails
/// the run.
@Test func analyzeReportsAFailedDisassemblyAsAFailureIfPresent() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    let fixture = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: binary.path),
          FileManager.default.fileExists(atPath: fixture) else { return }
    for arguments in [["analyze", fixture], ["analyze", fixture, "--json"]] {
        let out = Pipe(), err = Pipe()
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["DEVELOPER_DIR"] = "/nonexistent"  // xcrun cannot find llvm-objdump
        process.environment = environment
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus != 0, "\(arguments): exit 0\n\(stdout)")
        #expect(stderr.contains("disassembly failed"), "\(arguments): \(stderr)")
        #expect(!stdout.contains("(no functions recovered)"), "\(arguments): \(stdout)")
        #expect(stdout.contains("disassembly failed") || stdout.contains("\"disassemblyError\""), "\(arguments): \(stdout)")
    }
}
