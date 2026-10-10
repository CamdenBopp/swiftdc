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
}
