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
