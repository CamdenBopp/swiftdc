import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Inputs that are not a plain arm64 linked image, driven through the built
/// CLI: every subcommand takes its own path to the file, and a result on one
/// does not carry over to the others.
struct InputShapeTests {
    private static let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    private static let image = "Fixtures/Sample/libInputShape.arm64.dylib"

    /// Every subcommand that reads a binary, with the arguments it needs.
    private static let readers: [[String]] = [
        ["disasm"], ["disasm", "--pseudo"], ["disasm", "--structured"], ["disasm", "--cfg"], ["disasm", "--json"],
        ["dump"], ["layout"], ["interface"], ["objc"], ["analyze"], ["xrefs", "--unreferenced"], ["swift-version"],
    ]

    private struct Run { let status: Int32, stdout: String, stderr: String }

    private func run(_ arguments: [String]) throws -> Run? {
        guard FileManager.default.fileExists(atPath: Self.binary.path) else { return nil }
        let out = Pipe(), err = Pipe()
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = arguments
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, stdout: String(decoding: stdout, as: UTF8.self),
                   stderr: String(decoding: stderr, as: UTF8.self))
    }

    private func command(_ reader: [String], _ path: String) -> [String] {
        [reader[0], path] + reader.dropFirst()
    }

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-shape-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func absolute(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    // MARK: - Symlinks

    /// `attributesOfItem` describes a link, not its target, so every command
    /// measured a 7-byte file: "link.dylib is 7 bytes, shorter than a dyld
    /// shared cache header". A link reads as the file it names, on every path.
    @Test func everyCommandReadsThroughASymlinkIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.image) else { return }
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A relative link, and a link to a link, as Homebrew's bin/ has.
        let copy = directory.appendingPathComponent("Cellar/real.dylib")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: Self.image, toPath: copy.path)
        let hop = directory.appendingPathComponent("hop.dylib").path
        let link = directory.appendingPathComponent("link.dylib").path
        try FileManager.default.createSymbolicLink(atPath: hop, withDestinationPath: "Cellar/real.dylib")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "hop.dylib")
        for reader in Self.readers {
            guard let direct = try run(command(reader, copy.path)), let linked = try run(command(reader, link)) else { return }
            #expect(direct.status == 0, "\(reader): \(direct.stderr)")
            #expect(linked.status == 0, "\(reader): \(linked.stderr)")
            #expect(linked.stdout == direct.stdout, "\(reader)")
        }
    }

    /// A dangling link and a loop are different causes from a missing file.
    @Test func aDanglingLinkAndALoopSayWhatTheyAre() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dangling = directory.appendingPathComponent("dangling").path
        let loop = directory.appendingPathComponent("a").path
        try FileManager.default.createSymbolicLink(atPath: dangling, withDestinationPath: "missing")
        try FileManager.default.createSymbolicLink(atPath: loop, withDestinationPath: "b")
        try FileManager.default.createSymbolicLink(
            atPath: directory.appendingPathComponent("b").path, withDestinationPath: "a")
        for load in [{ _ = try BinaryLoader.load(path: $0) },
                     { _ = try BinaryLoader.resolveBinaryInput($0) },
                     { _ = try BinaryLoader.binaries(in: $0) },
                     { _ = try BinaryLoader.loadFromDyldCache(cachePath: $0, selector: .name("x")) }] as [(String) throws -> Void] {
            #expect { try load(dangling) } throws: { "\($0)".contains("dangling symbolic link") }
            #expect { try load(loop) } throws: { "\($0)".contains("symbolic link loop") }
            #expect { try load(loop + "/inner") } throws: { "\($0)".contains("symbolic link loop") }
        }
    }

    /// A `--cache` link was measured as a link too, and read as a short file.
    @Test func aCacheLinkIsMeasuredThroughTheLink() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("cache")
        // Long enough for a header, with no cache's magic.
        try Data(count: 4096).write(to: cache)
        let link = directory.appendingPathComponent("l").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "cache")
        #expect { _ = try BinaryLoader.loadFromDyldCache(cachePath: link, selector: .name("x")) } throws: {
            !"\($0)".contains("shorter than")
        }
    }

    /// A standard macOS framework: the top-level binary is a link through
    /// `Versions/Current`, and `Info.plist` sits in `Versions/A/Resources`.
    private func versionedFramework(in directory: URL, name: String, executable: String? = nil) throws -> URL {
        let binary = executable ?? name
        let fm = FileManager.default
        let framework = directory.appendingPathComponent("\(name).framework")
        let version = framework.appendingPathComponent("Versions/A")
        try fm.createDirectory(at: version.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try fm.copyItem(atPath: Self.image, toPath: version.appendingPathComponent(binary).path)
        if executable != nil {
            let info: [String: Any] = ["CFBundleExecutable": binary]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: version.appendingPathComponent("Resources/Info.plist"))
        }
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent(binary).path, withDestinationPath: "Versions/Current/\(binary)")
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Resources").path, withDestinationPath: "Versions/Current/Resources")
        return framework
    }

    @Test func aVersionedFrameworkResolvesToItsBinaryIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.image) else { return }
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The executable's name comes from Info.plist, or failing one, from the bundle's.
        for (name, executable) in [("Plisted", "Inner"), ("Bare", nil)] as [(String, String?)] {
            let framework = try versionedFramework(in: directory, name: name, executable: executable)
            let binaries = try BinaryLoader.binaries(in: framework.path)
            #expect(binaries.map(\.name) == [executable ?? name])
            #expect(binaries.first?.kind == .executable)
            for reader in Self.readers {
                guard let result = try run(command(reader, framework.path)) else { return }
                #expect(result.status == 0, "\(name) \(reader): \(result.stderr)")
            }
            // Tab completion leaves a trailing slash.
            guard let slash = try run(["dump", framework.path + "/"]) else { return }
            #expect(slash.status == 0, "\(slash.stderr)")
            #expect(slash.stdout.contains("Tally"), "\(slash.stdout)")
            guard let listing = try run(["dump", framework.path, "--list-binaries"]) else { return }
            #expect(listing.stdout.contains(executable ?? name), "\(listing.stderr)")
        }
        // A bundle is known by its name, and a link's own name need not say so.
        let link = directory.appendingPathComponent("noextension").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "Bare.framework")
        #expect(try BinaryLoader.binaries(in: link).map(\.name) == ["Bare"])
    }

    /// `disasm --binary M1 T.app` for a framework embedded in a macOS app, and
    /// the app reached through a link whose own name has no `.app`.
    @Test func anEmbeddedVersionedFrameworkIsSelectableIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.image) else { return }
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fm = FileManager.default
        let app = directory.appendingPathComponent("T.app")
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: frameworks, withIntermediateDirectories: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.copyItem(atPath: Self.image, toPath: macOS.appendingPathComponent("T").path)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": "T"] as [String: Any], format: .xml, options: 0)
        try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
        _ = try versionedFramework(in: frameworks, name: "M1")
        let link = directory.appendingPathComponent("shortcut").path
        try fm.createSymbolicLink(atPath: link, withDestinationPath: "T.app")

        for input in [app.path, link] {
            #expect(try BinaryLoader.binaries(in: input).map(\.name) == ["T", "M1"])
            guard let result = try run(["disasm", "--binary", "M1", input, "-f", "sum4"]) else { return }
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout.contains("sum4"), "\(result.stdout)")
        }
    }
}
