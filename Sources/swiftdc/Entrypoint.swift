import ArgumentParser
import Foundation
import SwiftDecompilerCore

@main
struct SwiftDC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftdc",
        abstract: "A Swift-aware Mach-O decompiler: reconstructed declarations + annotated ARM64.",
        version: SwiftDecompiler.version,
        subcommands: [AnalyzeCommand.self, DumpCommand.self, DisasmCommand.self],
        defaultSubcommand: AnalyzeCommand.self
    )
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

    func run() async throws {
        let report = try await AnalysisReport(preset: demangle)
            .generate(path: path, architecture: architecture)
        try emit(report, to: output)
    }
}

struct DumpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dump",
        abstract: "Reconstruct Swift declarations from a Mach-O binary's metadata."
    )

    @Argument(help: "Path to the Mach-O (or fat) binary.")
    var path: String

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

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

    func run() async throws {
        let machO = try BinaryLoader.load(path: path, architecture: architecture)
        let dumper = SwiftDeclarationDumper(preset: demangle)
        let selected = sections.isEmpty
            ? Set(SwiftDeclarationDumper.Section.allCases)
            : Set(sections)
        let text = await dumper.dump(machO, sections: selected)
        try emit(text.isEmpty ? "// No Swift metadata found for the selected sections." : text, to: output)
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

    func run() async throws {
        let disassembler = Disassembler(preset: demangle)
        let functions = try await disassembler.disassemble(
            path: path,
            architecture: architecture,
            functionFilter: function
        )
        let text = functions.isEmpty
            ? "// No functions matched."
            : functions.map { $0.render() }.joined(separator: "\n\n")
        try emit(text, to: output)
    }
}

extension DemanglePreset: ExpressibleByArgument {}
extension SwiftDeclarationDumper.Section: ExpressibleByArgument {}
