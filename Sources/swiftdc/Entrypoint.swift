import ArgumentParser
import Foundation
import SwiftDecompilerCore

@main
struct SwiftDC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftdc",
        abstract: "A Swift-aware Mach-O decompiler: reconstructed declarations + annotated ARM64.",
        version: SwiftDecompiler.version,
        subcommands: [AnalyzeCommand.self, DumpCommand.self, ObjCCommand.self, DisasmCommand.self],
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

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON (array of ObjC header blocks).")
    var json = false

    func run() throws {
        let machO = try BinaryLoader.loadMachO(
            path: path,
            architecture: architecture,
            image: image,
            imagePath: imagePath,
            cachePath: cache
        )
        let blocks = ObjCDumper().blocks(machO)
        if json {
            try emit(jsonStrings(blocks), to: output)
        } else {
            try emit(blocks.isEmpty ? "// No Objective-C metadata found." : blocks.joined(separator: "\n\n"), to: output)
        }
    }
}

/// Writes `text` to `output` if given, otherwise prints to stdout.
private func emit(_ text: String, to output: String?) throws {
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

    @Argument(help: "Path to the Mach-O (or fat) binary.")
    var path: String

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

    @Option(name: .long, help: "Demangle preset: default, simplified, interface.")
    var demangle: DemanglePreset = .default

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON instead of text.")
    var json = false

    func run() async throws {
        let report = AnalysisReport(preset: demangle)
        let text = json
            ? try await report.generateJSON(path: path, architecture: architecture)
            : try await report.generate(path: path, architecture: architecture)
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

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON (array of declaration blocks).")
    var json = false

    func run() async throws {
        if listImages {
            try emit(BinaryLoader.dyldCacheImagePaths(cachePath: cache).joined(separator: "\n"), to: output)
            return
        }
        let machO = try BinaryLoader.loadMachO(
            path: path,
            architecture: architecture,
            image: image,
            imagePath: imagePath,
            cachePath: cache
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

struct DisasmCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disasm",
        abstract: "Disassemble function bodies to ARM64, annotated with demangled calls."
    )

    @Argument(help: "Path to the Mach-O (or fat) binary.")
    var path: String

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

    @Option(name: [.short, .long], help: "Only show functions whose name (raw or demangled) contains this string.")
    var function: String?

    @Option(name: .long, help: "Demangle preset: default, simplified, interface.")
    var demangle: DemanglePreset = .default

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
        let disassembler = Disassembler(preset: demangle)
        let functions = try await disassembler.disassemble(
            path: path,
            architecture: architecture,
            functionFilter: function
        )
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
