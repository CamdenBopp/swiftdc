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

    // MARK: - Not arm64

    private static let x86 = "Fixtures/Sample/inputshape_x86_64.shape"
    private static let universal = "Fixtures/Sample/inputshape_universal.shape"

    /// `disasm --pseudo -f sum4` printed `mem0[x2 + 0x4a] = ?` for
    /// `pushq %rbp`, and `xrefs` printed `callees (0)`, both exit 0.
    @Test func everyCodeCommandRefusesAnotherArchitectureIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.x86) else { return }
        let codeCommands: [[String]] = [
            ["disasm", "--pseudo"], ["disasm", "--structured"], ["disasm", "--cfg"], ["disasm", "--json"],
            ["disasm", "-f", "sum4"], ["disasm", "--pseudo", "-f", "sum4"], ["disasm", "--json", "-f", "sum4"],
            ["xrefs", "--unreferenced"], ["xrefs", "-f", "sum4"],
            ["objc", "--methods"], ["objc", "--pseudo"], ["objc", "--structured"], ["objc", "-f", "add"],
        ]
        for (path, extra) in [(Self.x86, []), (Self.universal, ["--arch", "x86_64"])] {
            for reader in codeCommands {
                guard let result = try run(command(reader, path) + extra) else { return }
                #expect(result.status == 1, "\(reader) \(extra)")
                #expect(result.stderr.contains("x86_64 code cannot be analyzed"), "\(reader): \(result.stderr)")
                #expect(result.stdout.isEmpty, "\(reader): \(result.stdout)")
            }
        }
        // `score` decodes through the same streaming pass.
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = directory.appendingPathComponent("oracle.json")
        try JSONEncoder().encode(ReturnOracle([ReturnExpectation(1, in: 0x1000)])).write(to: manifest)
        guard let score = try run(["score", Self.x86, "--oracle", manifest.path]) else { return }
        #expect(score.status == 2)
        #expect(score.stderr.contains("x86_64 code cannot be analyzed"), "\(score.stderr)")
    }

    /// The other half: what reaches the decoder without the command's check
    /// claims nothing, rather than reading x86_64 bytes as ARM64.
    @Test func theDecoderDeclinesAnotherArchitectureIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: Self.x86) else { return }
        let machO = try BinaryLoader.load(path: Self.x86)
        let disassembler = Disassembler()
        #expect(!Disassembler.decodesCode(of: machO))
        try await withStableDependencies {
            #expect(await disassembler.disassemble(machO: machO).isEmpty)
            #expect(await disassembler.disassemble(machO: machO, functionFilter: "sum4").isEmpty)
            let streamed: [String] = await disassembler.disassembleStreaming(machO: machO) { $0.symbol }
            #expect(streamed.isEmpty)
            let starts = Set(disassembler.functionStarts(of: machO))
            #expect(!starts.isEmpty)
            #expect(await disassembler.disassembleFunctions(at: starts, in: machO).isEmpty)
            await #expect(throws: Disassembler.DisassembleError.self) {
                _ = try await disassembler.disassemble(path: Self.x86)
            }
        }
    }

    /// Plain `disasm` is llvm-objdump's text for the real architecture, with
    /// a warning, and none of the ARM64 analysis.
    @Test func thePlainListingShowsTheRealInstructionsIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.x86) else { return }
        for (path, extra) in [(Self.x86, []), (Self.universal, ["--arch", "x86_64"])] {
            guard let result = try run(["disasm", path] + extra) else { return }
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stderr.contains("x86_64 code is not analyzed"), "\(result.stderr)")
            #expect(result.stdout.contains("pushq"), "\(result.stdout)")
            #expect(!result.stdout.contains("sub_"), "\(result.stdout)")
            #expect(!result.stdout.contains("[recovered from"), "\(result.stdout)")
        }
    }

    /// `analyze` keeps its declarations and states the refusal, in text and
    /// JSON, and the run fails. `(no functions recovered)` would be a lie.
    @Test func analyzePrintsDeclarationsAndFailsIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.x86) else { return }
        guard let text = try run(["analyze", Self.x86]), let json = try run(["analyze", Self.x86, "--json"]) else { return }
        #expect(text.status == 1)
        #expect(json.status == 1)
        #expect(text.stdout.contains("Tally"), "\(text.stdout)")
        #expect(text.stdout.contains("// disassembly failed: x86_64 code cannot be analyzed"), "\(text.stdout)")
        #expect(!text.stdout.contains("no functions recovered"), "\(text.stdout)")
        #expect(json.stdout.contains("x86_64 code cannot be analyzed"), "\(json.stdout)")
        #expect(text.stderr.contains("error: disassembly failed"), "\(text.stderr)")
    }

    /// The loaded-image route, which a cache image takes.
    @Test func analyzeOfALoadedImageFailsAlikeIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: Self.x86) else { return }
        let machO = try BinaryLoader.load(path: Self.x86)
        let report = await withStableDependencies { await AnalysisReport().report(machO: machO, json: false) }
        #expect(report.disassemblyError?.contains("x86_64 code cannot be analyzed") == true)
        #expect(report.text.contains("// disassembly failed: x86_64 code cannot be analyzed"), "\(report.text)")
    }

    /// Metadata needs no decoder, and must keep working.
    @Test func metadataCommandsReadAnotherArchitectureIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.x86) else { return }
        for (path, extra) in [(Self.x86, []), (Self.universal, ["--arch", "x86_64"])] {
            for (reader, expected) in [(["dump"], "Tally"), (["interface"], "Tally"), (["layout"], "Pair"),
                                       (["objc"], "Tally"), (["objc", "--metadata-only"], "Tally"),
                                       (["swift-version"], "Swift")] as [([String], String)] {
                guard let result = try run(command(reader, path) + extra) else { return }
                #expect(result.status == 0, "\(reader): \(result.stderr)")
                #expect(result.stdout.contains(expected), "\(reader): \(result.stdout)")
            }
        }
    }

    /// The universal file's arm64 slice still decodes.
    @Test func theArm64SliceOfAUniversalFileDecodesIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.universal) else { return }
        guard let result = try run(["disasm", Self.universal, "--arch", "arm64", "--pseudo", "-f", "sum4"]) else { return }
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.contains("sum4"), "\(result.stdout)")
    }

    // MARK: - Relocatable objects

    /// `disasm c1.o` printed `bl _printf ; args(sub_0)`, `xrefs` a callee
    /// `0x30 sub_30`, and a function at offset 0 two folded symbols, because
    /// nothing applied the relocations. A Swift object failed as "Malformed
    /// Mach-O" while the C object was accepted. Every command, one message.
    @Test func everyCommandRefusesAnObjectAlikeIfPresent() throws {
        let objects = ["Fixtures/Sample/inputshape_c.o", "Fixtures/Sample/inputshape_swift.o"]
        guard objects.allSatisfy(FileManager.default.fileExists(atPath:)) else { return }
        for object in objects {
            for reader in Self.readers + [["xrefs", "-f", "entry"], ["disasm", "-f", "entry"], ["objc", "--methods"]] {
                guard let result = try run(command(reader, object)) else { return }
                #expect(result.status == 1, "\(reader) \(object)")
                #expect(result.stderr.contains("Relocatable object: "), "\(reader) \(object): \(result.stderr)")
                #expect(!result.stderr.contains("Malformed"), "\(reader) \(object): \(result.stderr)")
                #expect(result.stdout.isEmpty, "\(reader) \(object): \(result.stdout)")
            }
        }
    }

    /// A universal object: each slice is refused for the same cause.
    @Test func aUniversalObjectIsRefusedAlikeIfPresent() throws {
        let object = "Fixtures/Sample/inputshape_c.o"
        guard let bytes = FileManager.default.contents(atPath: object) else { return }
        // `fat_header`, one `fat_arch` for arm64, the object at offset 4096.
        var fat = Data()
        for word in [0xcafe_babe, 1, 0x0100_000c, 0, 4096, UInt32(bytes.count), 12] as [UInt32] {
            withUnsafeBytes(of: word.bigEndian) { fat.append(contentsOf: $0) }
        }
        fat.append(Data(count: 4096 - fat.count))
        fat.append(bytes)
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("fat.o")
        try fat.write(to: path)
        #expect { _ = try BinaryLoader.load(path: path.path, architecture: "arm64") } throws: {
            "\($0)".contains("Relocatable object: ")
        }
    }

    /// The header test on all four magic spellings, and only `MH_OBJECT`.
    @Test func anObjectIsKnownByItsHeader() {
        func header(_ magic: UInt32, filetype: UInt32, bigEndian: Bool) -> Data {
            var data = Data()
            for word in [magic, 0, 0, filetype] {
                withUnsafeBytes(of: bigEndian ? word.bigEndian : word.littleEndian) { data.append(contentsOf: $0) }
            }
            return data
        }
        for magic in [0xfeed_facf, 0xfeed_face] as [UInt32] {
            #expect(MachOPreflight.isRelocatableObject(prefix: header(magic, filetype: 1, bigEndian: false)))
            #expect(MachOPreflight.isRelocatableObject(prefix: header(magic, filetype: 1, bigEndian: true)))
            #expect(!MachOPreflight.isRelocatableObject(prefix: header(magic, filetype: 6, bigEndian: false)))
            #expect(!MachOPreflight.isRelocatableObject(prefix: header(magic, filetype: 6, bigEndian: true)))
        }
        #expect(!MachOPreflight.isRelocatableObject(prefix: header(0xcafe_babe, filetype: 1, bigEndian: false)))
    }

    /// An object is refused only for relocations it may hold: one section
    /// listing any, or load commands that cannot all be read. A relocation-free
    /// object (the tests' hand-built images) has nothing unresolved.
    @Test func anObjectIsRefusedOnlyForItsRelocations() {
        func object(nreloc: [UInt32], ncmds: UInt32? = nil, truncate: Int = 0) -> Data {
            var words: [UInt32] = [0xfeed_facf, 0x0100_000c, 0, 1, ncmds ?? 1, 72 + 80 * UInt32(nreloc.count), 0, 0]
            words += [0x19, 72 + 80 * UInt32(nreloc.count)] + Array(repeating: 0, count: 14) + [UInt32(nreloc.count), 0]
            for count in nreloc { words += Array(repeating: 0, count: 15) + [count] + Array(repeating: 0, count: 4) }
            var data = Data()
            for word in words { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
            return data.dropLast(truncate)
        }
        #expect(!MachOPreflight.mayHoldRelocations(prefix: object(nreloc: [])))
        #expect(!MachOPreflight.mayHoldRelocations(prefix: object(nreloc: [0, 0])))
        #expect(MachOPreflight.mayHoldRelocations(prefix: object(nreloc: [0, 2])))
        #expect(MachOPreflight.mayHoldRelocations(prefix: object(nreloc: [0], truncate: 24)))
        #expect(MachOPreflight.mayHoldRelocations(prefix: object(nreloc: [], ncmds: 2)))
    }

    // MARK: - No LC_FUNCTION_STARTS

    private static let noStarts = "Fixtures/Sample/libInputShapeNoStarts.dylib"
    private static let noStartsStripped = "Fixtures/Sample/libInputShapeNoStarts.stripped.dylib"

    /// Stripped with no function starts, `triple` and `shout` run together
    /// under one heading, which claimed `[boundary from LC_FUNCTION_STARTS]`,
    /// a load command the image does not have.
    @Test func aBoundaryNothingRecordsSaysSoIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.noStartsStripped) else { return }
        guard let listing = try run(["disasm", Self.noStartsStripped]) else { return }
        #expect(listing.status == 0, "\(listing.stderr)")
        #expect(!listing.stdout.contains("LC_FUNCTION_STARTS"), "\(listing.stdout)")
        #expect(listing.stdout.contains("[no recorded boundary: decoding began here]"), "\(listing.stdout)")
    }

    /// Function starts still read as function starts, in both decoders.
    @Test func aRecordedBoundaryNamesItsSourceIfPresent() async throws {
        let path = "Fixtures/Sample/sample.stripped"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let machO = try BinaryLoader.load(path: path)
        let functions = await withStableDependencies { await Disassembler().disassemble(machO: machO) }
        let unnamed = functions.filter { $0.source == .address }
        #expect(!unnamed.isEmpty)
        #expect(unnamed.allSatisfy { $0.render().contains("[boundary from LC_FUNCTION_STARTS]") })
    }

    /// Every command that segments the image warns, once, on stderr; stdout
    /// is unchanged and the run still succeeds.
    @Test func unreliableBoundariesWarnOnEveryPathIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.noStartsStripped) else { return }
        for reader in [["disasm"], ["disasm", "--pseudo"], ["disasm", "--json"], ["disasm", "-f", "entry"], ["analyze"],
                       ["xrefs", "--unreferenced"], ["objc", "--methods"]] {
            guard let result = try run(command(reader, Self.noStartsStripped)) else { return }
            #expect(result.status == 0, "\(reader): \(result.stderr)")
            let warnings = result.stderr.components(separatedBy: "warning: no LC_FUNCTION_STARTS").count - 1
            #expect(warnings == 1, "\(reader): \(result.stderr)")
            #expect(!result.stdout.contains("warning:"), "\(reader)")
        }
    }

    /// Symbols that mark every function need no warning; nor does an image
    /// with function starts.
    @Test func sufficientBoundariesDoNotWarnIfPresent() throws {
        for path in [Self.noStarts, "Fixtures/Sample/libNoFunctionStarts.dylib", "Fixtures/Sample/sample.stripped"] {
            guard FileManager.default.fileExists(atPath: path), let result = try run(["disasm", path]) else { return }
            #expect(!result.stderr.contains("warning: no LC_FUNCTION_STARTS"), "\(path): \(result.stderr)")
        }
    }

    /// Each kind of evidence, on a hand-built body.
    private func unmarked(_ words: [UInt32], boundaries: Set<UInt64> = [0x1000]) throws -> UInt64? {
        let code = words.reduce(into: Data()) { data, word in
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
        }
        let engine = try #require(CapstoneEngine())
        let section = CodeSection(segment: "__TEXT", name: "__text", range: 0x1000 ..< 0x1000 + UInt64(code.count))
        var scan = UnmarkedEntryScan(boundaries: boundaries, sections: [section])
        return scan.read(engine.disassemble(code, address: 0x1000)) ?? scan.finish()
    }

    /// Every copy of a function keeps what marks it.
    @Test func aRebuiltFunctionKeepsItsBoundaryEvidence() {
        let function = DisassembledFunction(symbol: "sub_0", demangledName: nil, startAddress: 0, instructions: [],
                                            source: .address, boundary: .decodeStart)
        let resume = AsyncFuncletInfo(parent: 0x50, parentName: "parent", ordinal: 1, kind: .awaitReturn,
                                      predecessor: 0x50, chain: [0x50, 0])
        #expect(function.replacingInstructions([]).boundary == .decodeStart)
        #expect(function.attachingSwitchTargets([:]).boundary == .decodeStart)
        let titled = function.attachingAsyncFunclet(resume)
        #expect(titled.boundary == .decodeStart)
        #expect(titled.render().contains("[titled from its async parent; no recorded boundary: decoding began here]"))
    }

    /// A call out of the code sections is a stub, not an unmarked function.
    @Test func aCallOutOfTheCodeSectionsIsNoEvidence() throws {
        let blFar: UInt32 = 0x9400_0100, ret: UInt32 = 0xd65f_03c0
        #expect(try unmarked([blFar, ret]) == nil)
    }

    @Test func aCallIntoABodyIsAnUnmarkedEntry() throws {
        let bl8: UInt32 = 0x9400_0002, ret: UInt32 = 0xd65f_03c0, nop: UInt32 = 0xd503_201f
        #expect(try unmarked([bl8, ret, nop]) == 0x1008)
        #expect(try unmarked([bl8, ret, nop], boundaries: [0x1000, 0x1008]) == nil)
    }

    @Test func codeAfterAReturnIsAnUnmarkedEntryUnlessABranchReachesIt() throws {
        let ret: UInt32 = 0xd65f_03c0, mov: UInt32 = 0xd280_0020, nop: UInt32 = 0xd503_201f
        let cbzPlus8: UInt32 = 0xb400_0040
        #expect(try unmarked([ret, mov, ret]) == 0x1004)
        #expect(try unmarked([ret, mov, ret], boundaries: [0x1000, 0x1004]) == nil)
        #expect(try unmarked([cbzPlus8, ret, mov, ret]) == nil)
        #expect(try unmarked([ret, nop, nop]) == nil)
    }

    @Test func theScanFindsTheFixturesAnswerIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: Self.noStartsStripped),
              FileManager.default.fileExists(atPath: Self.noStarts) else { return }
        let disassembler = Disassembler()
        let stripped = try BinaryLoader.load(path: Self.noStartsStripped)
        let named = try BinaryLoader.load(path: Self.noStarts)
        await withStableDependencies {
            #expect(disassembler.unmarkedEntry(in: stripped) != nil)
            #expect(disassembler.unmarkedEntry(in: named) == nil)
        }
    }


    // MARK: - --arch

    /// `--arch` on a thin file was never read: `--arch x86_64` and `--arch
    /// ppc` both printed the arm64 image, exit 0.
    @Test func aThinFileRefusesAnotherArchitectureIfPresent() throws {
        guard FileManager.default.fileExists(atPath: Self.image) else { return }
        for reader in Self.readers + [["disasm", "-f", "sum4"]] {
            for architecture in ["x86_64", "ppc", "arm64e"] {
                guard let result = try run(command(reader, Self.image) + ["--arch", architecture]) else { return }
                #expect(result.status == 1, "\(reader) \(architecture)")
                #expect(result.stderr.contains("Architecture '\(architecture)' not found. Available: arm64"),
                        "\(reader): \(result.stderr)")
                #expect(result.stdout.isEmpty, "\(reader)")
            }
            guard let same = try run(command(reader, Self.image) + ["--arch", "arm64"]) else { return }
            #expect(same.status == 0, "\(reader): \(same.stderr)")
        }
    }

    /// The same on a dyld shared-cache image, whose commands dropped `--arch`.
    @Test func aCacheImageRefusesAnotherArchitectureIfPresent() throws {
        guard let list = try run(["dump", "--list-images"]), list.status == 0, list.stdout.contains("libswiftCore") else { return }
        for reader in [["dump"], ["disasm"], ["disasm", "--json"], ["analyze"], ["xrefs", "--unreferenced"], ["layout"],
                       ["interface"], ["objc"], ["swift-version"]] {
            let arguments = [reader[0], "--image", "libswiftCore", "--arch", "ppc"] + reader.dropFirst()
            guard let result = try run(arguments) else { return }
            #expect(result.status == 1, "\(reader)")
            #expect(result.stderr.contains("Architecture 'ppc' not found."), "\(reader): \(result.stderr)")
        }
    }
}
