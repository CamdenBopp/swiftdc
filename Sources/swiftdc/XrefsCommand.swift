import ArgumentParser
import Foundation
import SwiftDecompilerCore

struct XrefsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xrefs",
        abstract: "Show who calls a function, and what it calls.",
        discussion: """
        Builds a call graph from resolved direct-branch targets across the whole \
        image, so unlike `disasm --function` it must disassemble everything — \
        expect it to be slow on a large binary.

        Indirect dispatch (a `blr` through a vtable, witness table, or block \
        pointer) has no statically known target, so those calls are not edges. \
        The unresolved count is reported alongside the results rather than \
        pretending the graph is complete.
        """
    )

    @Argument(help: "Path to the Mach-O (or fat) binary. Omit when reading from the dyld shared cache with --image.")
    var path: String?

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries (arm64, arm64e, x86_64).")
    var architecture: String?

    @Option(name: .customLong("image"), help: "Read this image from the dyld shared cache by name (e.g. Foundation).")
    var image: String?

    @Option(name: .customLong("image-path"), help: "Read this image from the dyld shared cache by full install path.")
    var imagePath: String?

    @Option(name: .customLong("cache"), help: "Path to a dyld_shared_cache_* file. Defaults to the running system's cache when --image is used.")
    var cache: String?

    @Option(name: .customLong("binary"), help: "For an .app/.framework/.ipa: analyze this embedded binary by name. Default: the main executable.")
    var binary: String?

    @Option(name: [.short, .long], help: "Function to cross-reference: matches any function whose name (raw or demangled) contains this string.")
    var function: String?

    @Flag(name: .long, help: "List functions no other function in this image statically calls.")
    var unreferenced = false

    @Option(name: .long, help: "Demangle preset: default, simplified, interface.")
    var demangle: DemanglePreset = .default

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON.")
    var json = false

    func run() async throws {
        guard function != nil || unreferenced else {
            throw ValidationError("Pass --function <name> to cross-reference, or --unreferenced.")
        }

        let disassembler = Disassembler(preset: demangle)
        let functions: [DisassembledFunction]
        if image != nil || imagePath != nil || cache != nil {
            let machO = try BinaryLoader.loadMachO(
                path: path, image: image, imagePath: imagePath, cachePath: cache, binary: binary
            )
            functions = await disassembler.disassemble(machO: machO)
        } else if let path {
            let resolved = try BinaryLoader.resolveBinaryInput(path, binary: binary)
            functions = try await disassembler.disassemble(path: resolved, architecture: architecture)
        } else {
            throw BinaryLoadError("Provide a binary path, or --image <name> to read a dyld shared-cache image.")
        }

        let graph = CallGraph(functions: functions)
        if unreferenced {
            try emit(renderUnreferenced(graph), to: output)
            return
        }
        try emit(renderCrossReferences(graph, needle: function!), to: output)
    }

    private func renderUnreferenced(_ graph: CallGraph) -> String {
        let addresses = graph.unreferenced()
        if json {
            return jsonText(addresses.map {
                ["address": hex($0), "name": graph.name(of: $0)] as [String: Any]
            })
        }
        var lines = addresses.map { "\(hex($0))  \(graph.name(of: $0))" }
        lines.append("")
        lines.append("""
        \(addresses.count) of \(graph.functionAddresses.count) functions have no static \
        caller in this image — entry points, exported symbols, and anything reached by \
        indirect dispatch look the same as dead code here.
        """)
        return lines.joined(separator: "\n")
    }

    private func renderCrossReferences(_ graph: CallGraph, needle: String) -> String {
        let matches = graph.addresses(matching: needle)
        guard !matches.isEmpty else {
            return json ? "[]" : "// No function matched '\(needle)'."
        }

        if json {
            return jsonText(matches.map { address in
                [
                    "address": hex(address),
                    "name": graph.name(of: address),
                    "callers": graph.callers(of: address).map {
                        ["site": hex($0.site), "function": graph.name(of: $0.caller)] as [String: Any]
                    },
                    "callees": graph.callees(of: address).map {
                        ["site": hex($0.site), "function": graph.name(of: $0.callee)] as [String: Any]
                    },
                ] as [String: Any]
            })
        }

        var blocks: [String] = []
        for address in matches {
            var lines = ["\(graph.name(of: address))  \(hex(address))"]
            let callers = graph.callers(of: address)
            let callees = graph.callees(of: address)

            lines.append("  callers (\(callers.count)):")
            if callers.isEmpty {
                lines.append("    <none — an entry point, an export, or called indirectly>")
            }
            for edge in callers {
                lines.append("    \(hex(edge.site))  \(graph.name(of: edge.caller))")
            }

            // Deduplicate: a callee hit from several sites is one relationship,
            // and listing it once per site buries the rest.
            lines.append("  callees (\(Set(callees.map(\.callee)).count)):")
            var seen = Set<UInt64>()
            for edge in callees where seen.insert(edge.callee).inserted {
                lines.append("    \(hex(edge.site))  \(graph.name(of: edge.callee))")
            }
            blocks.append(lines.joined(separator: "\n"))
        }

        if graph.unresolvedCallSites > 0 {
            blocks.append("""
            // \(graph.unresolvedCallSites) call sites in this image dispatch \
            indirectly and have no static target, so they are absent from the graph.
            """)
        }
        return blocks.joined(separator: "\n\n")
    }

    private func hex(_ address: UInt64) -> String { "0x" + String(address, radix: 16) }
}

private func jsonText(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) else { return "[]" }
    return String(decoding: data, as: UTF8.self)
}
