import ArgumentParser
import Foundation
import SwiftDecompilerCore

@main
struct SwiftDC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftdc",
        abstract: "A Swift-aware Mach-O decompiler: reconstructed declarations + annotated ARM64.",
        version: SwiftDecompiler.version,
        subcommands: [
            AnalyzeCommand.self, DumpCommand.self, InterfaceCommand.self, ObjCCommand.self,
            DisasmCommand.self, XrefsCommand.self, DevicesCommand.self, AppsCommand.self,
        ],
        defaultSubcommand: AnalyzeCommand.self
    )
}

struct ObjCCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "objc",
        abstract: "Reconstruct Objective-C headers (@interface/@protocol) from ObjC metadata."
    )

    @Argument(help: "Path to the Mach-O (or fat) binary. Omit when reading from the dyld shared cache with --image.")
    var path: String?

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

    @Option(name: .customLong("image"), help: "Read this image from the dyld shared cache by name (e.g. Foundation, UIKit).")
    var image: String?

    @Option(name: .customLong("image-path"), help: "Read this image from the dyld shared cache by full install path.")
    var imagePath: String?

    @Option(name: .customLong("cache"), help: "Path to a dyld_shared_cache_* file. Defaults to the running system's cache when --image is used.")
    var cache: String?

    @Option(name: .customLong("binary"), help: "For an .app/.framework/.ipa: analyze this embedded binary by name (e.g. a framework). Default: the main executable.")
    var binary: String?

    @Flag(name: .customLong("list-binaries"), help: "List the Mach-O binaries inside an .app/.framework/.ipa (main + embedded frameworks/extensions) and exit.")
    var listBinaries = false

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON (array of ObjC header blocks).")
    var json = false

    func run() throws {
        if listBinaries { try emit(binaryListing(for: path), to: output); return }
        let machO = try BinaryLoader.loadMachO(
            path: path,
            architecture: architecture,
            image: image,
            imagePath: imagePath,
            cachePath: cache,
            binary: binary
        )
        let blocks = ObjCDumper().blocks(machO)
        if json {
            try emit(jsonStrings(blocks), to: output)
        } else {
            try emit(blocks.isEmpty ? "// No Objective-C metadata found." : blocks.joined(separator: "\n\n"), to: output)
        }
    }
}

/// `kind  name  path` lines for the binaries inside a bundle/archive. Backs
/// `--list-binaries`.
private func binaryListing(for path: String?) throws -> String {
    guard let path else {
        throw BinaryLoadError("--list-binaries needs a path to a binary, .app, .framework, or .ipa.")
    }
    return try BinaryLoader.binaries(in: path)
        .map { "\($0.kind.rawValue)\t\($0.name)\t\($0.path)" }
        .joined(separator: "\n")
}

/// Writes `text` to `output` if given, otherwise prints to stdout.
func emit(_ text: String, to output: String?) throws {
    if let output {
        try text.write(toFile: output, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("Wrote \(output)\n".utf8))
    } else {
        print(text)
    }
}

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Full report: reconstructed declarations + disassembly grouped by type."
    )

    @Argument(help: "Path to the Mach-O (or fat) binary. Omit when reading from the dyld shared cache with --image.")
    var path: String?

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

    @Option(name: .customLong("image"), help: "Analyze this image from the dyld shared cache by name (e.g. Foundation). Disassembly is decoded in-process with Capstone.")
    var image: String?

    @Option(name: .customLong("image-path"), help: "Analyze this image from the dyld shared cache by full install path.")
    var imagePath: String?

    @Option(name: .customLong("cache"), help: "Path to a dyld_shared_cache_* file. Defaults to the running system's cache when --image is used.")
    var cache: String?

    @Option(name: .long, help: "Demangle preset: default, simplified, interface.")
    var demangle: DemanglePreset = .default

    @Option(name: .customLong("binary"), help: "For an .app/.framework/.ipa: analyze this embedded binary by name (e.g. a framework). Default: the main executable.")
    var binary: String?

    @Flag(name: .customLong("list-binaries"), help: "List the Mach-O binaries inside an .app/.framework/.ipa (main + embedded frameworks/extensions) and exit.")
    var listBinaries = false

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON instead of text.")
    var json = false

    func run() async throws {
        if listBinaries { try emit(binaryListing(for: path), to: output); return }
        let report = AnalysisReport(preset: demangle)
        let text: String
        if image != nil || imagePath != nil || cache != nil {
            let machO = try BinaryLoader.loadMachO(
                path: path, image: image, imagePath: imagePath, cachePath: cache, binary: binary
            )
            text = json ? await report.generateJSON(machO: machO) : await report.generate(machO: machO)
        } else if let path {
            // Accept an .app/.framework/.ipa, resolving to a real Mach-O for llvm-objdump.
            let resolved = try BinaryLoader.resolveBinaryInput(path, binary: binary)
            text = json
                ? try await report.generateJSON(path: resolved, architecture: architecture)
                : try await report.generate(path: resolved, architecture: architecture)
        } else {
            throw BinaryLoadError("Provide a binary path, or --image <name> to analyze a dyld shared-cache image.")
        }
        try emit(text, to: output)
    }
}

struct DumpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dump",
        abstract: "Reconstruct Swift declarations from a Mach-O binary — or a dyld shared-cache image."
    )

    @Argument(help: "Path to the Mach-O (or fat) binary. Omit when reading from the dyld shared cache with --image.")
    var path: String?

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

    @Option(name: .customLong("image"), help: "Read this image from the dyld shared cache by name (e.g. Foundation, SwiftUI, libswiftCore).")
    var image: String?

    @Option(name: .customLong("image-path"), help: "Read this image from the dyld shared cache by full install path.")
    var imagePath: String?

    @Option(name: .customLong("cache"), help: "Path to a dyld_shared_cache_* file. Defaults to the running system's cache when --image is used.")
    var cache: String?

    @Flag(name: .customLong("list-images"), help: "List every image install path in the dyld shared cache and exit.")
    var listImages = false

    @Option(name: .long, help: "Demangle preset: default, simplified, interface.")
    var demangle: DemanglePreset = .default

    @Option(
        name: [.short, .long],
        parsing: .upToNextOption,
        help: "Sections to dump: types, protocols, conformances, associatedTypes. Default: all."
    )
    var sections: [SwiftDeclarationDumper.Section] = []

    @Option(name: .customLong("binary"), help: "For an .app/.framework/.ipa: analyze this embedded binary by name (e.g. a framework). Default: the main executable.")
    var binary: String?

    @Flag(name: .customLong("list-binaries"), help: "List the Mach-O binaries inside an .app/.framework/.ipa (main + embedded frameworks/extensions) and exit.")
    var listBinaries = false

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON (array of declaration blocks).")
    var json = false

    func run() async throws {
        if listBinaries { try emit(binaryListing(for: path), to: output); return }
        if listImages {
            try emit(BinaryLoader.dyldCacheImagePaths(cachePath: cache).joined(separator: "\n"), to: output)
            return
        }
        let machO = try BinaryLoader.loadMachO(
            path: path,
            architecture: architecture,
            image: image,
            imagePath: imagePath,
            cachePath: cache,
            binary: binary
        )
        let dumper = SwiftDeclarationDumper(preset: demangle)
        let selected = sections.isEmpty
            ? Set(SwiftDeclarationDumper.Section.allCases)
            : Set(sections)
        let text = await dumper.dump(machO, sections: selected)
        if json {
            try emit(declarationsJSON(text), to: output)
        } else {
            try emit(text.isEmpty ? "// No Swift metadata found for the selected sections." : text, to: output)
        }
    }
}

struct InterfaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interface",
        abstract: "Reconstruct a Swift interface (.swiftinterface-style source) from a Mach-O — or a dyld shared-cache image."
    )

    @Argument(help: "Path to the Mach-O (or fat) binary. Omit when reading from the dyld shared cache with --image.")
    var path: String?

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

    @Option(name: .customLong("image"), help: "Read this image from the dyld shared cache by name (e.g. Foundation, SwiftUI).")
    var image: String?

    @Option(name: .customLong("image-path"), help: "Read this image from the dyld shared cache by full install path.")
    var imagePath: String?

    @Option(name: .customLong("cache"), help: "Path to a dyld_shared_cache_* file. Defaults to the running system's cache when --image is used.")
    var cache: String?

    @Flag(name: .long, help: "Include types imported from C.")
    var showCImportedTypes = false

    @Flag(name: .long, help: "Emit field-offset comments for stored properties.")
    var fieldOffsets = false

    @Flag(name: .long, help: "Emit each member's binary address as a comment.")
    var memberAddresses = false

    @Flag(name: .long, help: "Emit vtable-offset comments for class methods and computed properties.")
    var vtableOffsets = false

    @Flag(name: .long, help: "Emit a memory-layout comment for each type.")
    var typeLayout = false

    @Flag(name: .long, help: "Emit a memory-layout comment for each enum (payload / spare-bit info).")
    var enumLayout = false

    @Flag(name: .long, help: "Order members by binary layout offset instead of grouping by category.")
    var sortByOffset = false

    @Flag(name: .long, help: "Parse opaque (some P) return types. Experimental — may error on complex types.")
    var opaqueReturnTypes = false

    @Option(name: .customLong("binary"), help: "For an .app/.framework/.ipa: analyze this embedded binary by name (e.g. a framework). Default: the main executable.")
    var binary: String?

    @Flag(name: .customLong("list-binaries"), help: "List the Mach-O binaries inside an .app/.framework/.ipa (main + embedded frameworks/extensions) and exit.")
    var listBinaries = false

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    func run() async throws {
        if listBinaries { try emit(binaryListing(for: path), to: output); return }
        let machO = try BinaryLoader.loadMachO(
            path: path,
            architecture: architecture,
            image: image,
            imagePath: imagePath,
            cachePath: cache,
            binary: binary
        )
        let options = InterfaceReconstructor.Options(
            showCImportedTypes: showCImportedTypes,
            fieldOffsets: fieldOffsets,
            memberAddresses: memberAddresses,
            vtableOffsets: vtableOffsets,
            typeLayout: typeLayout,
            enumLayout: enumLayout,
            sortByOffset: sortByOffset,
            parseOpaqueReturnTypes: opaqueReturnTypes
        )
        let text = try await InterfaceReconstructor(options: options).reconstruct(machO)
        try emit(text.isEmpty ? "// No Swift metadata found." : text, to: output)
    }
}

struct DisasmCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disasm",
        abstract: "Disassemble function bodies to ARM64, annotated with demangled calls."
    )

    @Argument(help: "Path to the Mach-O (or fat) binary. Omit when reading from the dyld shared cache with --image.")
    var path: String?

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

    @Option(name: .customLong("image"), help: "Disassemble this image from the dyld shared cache by name (e.g. Foundation). Decoded in-process with Capstone.")
    var image: String?

    @Option(name: .customLong("image-path"), help: "Disassemble this image from the dyld shared cache by full install path.")
    var imagePath: String?

    @Option(name: .customLong("cache"), help: "Path to a dyld_shared_cache_* file. Defaults to the running system's cache when --image is used.")
    var cache: String?

    @Option(name: [.short, .long], help: "Only show functions whose name (raw or demangled) contains this string.")
    var function: String?

    @Option(name: .long, help: "Demangle preset: default, simplified, interface.")
    var demangle: DemanglePreset = .default

    @Option(name: .customLong("binary"), help: "For an .app/.framework/.ipa: analyze this embedded binary by name (e.g. a framework). Default: the main executable.")
    var binary: String?

    @Flag(name: .customLong("list-binaries"), help: "List the Mach-O binaries inside an .app/.framework/.ipa (main + embedded frameworks/extensions) and exit.")
    var listBinaries = false

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON instead of text.")
    var json = false

    @Flag(name: .long, help: "Render the control-flow graph (basic blocks + edges) instead of a flat listing.")
    var cfg = false

    @Flag(name: .long, help: "Render proto-pseudocode: recovered call statements per function (ARC/runtime noise hidden).")
    var pseudo = false

    @Flag(name: .long, help: "Like --pseudo, but folds the CFG into if/else structure (goto for loops).")
    var structured = false

    func run() async throws {
        if listBinaries { try emit(binaryListing(for: path), to: output); return }
        let disassembler = Disassembler(preset: demangle)
        let functions: [DisassembledFunction]
        if image != nil || imagePath != nil || cache != nil {
            // dyld shared-cache image: no standalone file for llvm-objdump, so
            // decode in-process with Capstone.
            let machO = try BinaryLoader.loadMachO(
                path: path, image: image, imagePath: imagePath, cachePath: cache, binary: binary
            )
            functions = await disassembler.disassemble(machO: machO, functionFilter: function)
        } else if let path {
            // Accept an .app/.framework/.ipa, resolving to a real Mach-O for llvm-objdump.
            let resolved = try BinaryLoader.resolveBinaryInput(path, binary: binary)
            functions = try await disassembler.disassemble(
                path: resolved, architecture: architecture, functionFilter: function
            )
        } else {
            throw BinaryLoadError("Provide a binary path, or --image <name> to disassemble a dyld shared-cache image.")
        }
        if json {
            try emit(functions.jsonString(), to: output)
        } else if functions.isEmpty {
            try emit("// No functions matched.", to: output)
        } else if structured {
            try emit(functions.map { $0.renderStructured() }.joined(separator: "\n\n"), to: output)
        } else if pseudo {
            try emit(functions.map { $0.renderPseudo() }.joined(separator: "\n\n"), to: output)
        } else if cfg {
            try emit(functions.map { $0.renderCFG() }.joined(separator: "\n\n"), to: output)
        } else {
            try emit(functions.map { $0.render() }.joined(separator: "\n\n"), to: output)
        }
    }
}

extension DemanglePreset: ExpressibleByArgument {}
extension SwiftDeclarationDumper.Section: ExpressibleByArgument {}
