import Foundation

/// Produces a combined human-readable report: reconstructed Swift declarations
/// followed by ARM64 disassembly grouped by the owning type.
public struct AnalysisReport: Sendable {
    public var preset: DemanglePreset

    public init(preset: DemanglePreset = .default) {
        self.preset = preset
    }

    /// Structured JSON: `{ declarations: [...], functions: [...] }`.
    public func generateJSON(path: String, architecture: String? = nil) async throws -> String {
        let machO = try BinaryLoader.load(path: path, architecture: architecture)
        let declarations = await SwiftDeclarationDumper(preset: preset).dump(machO)
        let functions = (try? await Disassembler(preset: preset)
            .disassemble(path: path, architecture: architecture)) ?? []
        return reportJSON(declarations: declarations, functions: functions)
    }

    public func generate(path: String, architecture: String? = nil) async throws -> String {
        let machO = try BinaryLoader.load(path: path, architecture: architecture)
        let declarations = await SwiftDeclarationDumper(preset: preset).dump(machO)
        // Disassembly is best-effort; a missing/odd binary shouldn't sink the report.
        let functions = (try? await Disassembler(preset: preset)
            .disassemble(path: path, architecture: architecture)) ?? []

        var out = ""
        out += banner("DECLARATIONS")
        out += declarations.isEmpty ? "// (no Swift type metadata found)\n" : declarations + "\n"

        out += "\n" + banner("DISASSEMBLY")
        if functions.isEmpty {
            out += "// (no functions recovered)\n"
        } else {
            for group in Self.groupByOwner(functions) {
                out += "\n// ──── \(group.owner) ────\n\n"
                out += group.functions.map { $0.render() }.joined(separator: "\n\n")
                out += "\n"
            }
        }
        return out
    }

    private func banner(_ title: String) -> String {
        let rule = String(repeating: "=", count: 60)
        return "// \(rule)\n// \(title)\n// \(rule)\n"
    }

    /// Group functions by their owning type, preserving first-seen order.
    static func groupByOwner(
        _ functions: [DisassembledFunction]
    ) -> [(owner: String, functions: [DisassembledFunction])] {
        var order: [String] = []
        var buckets: [String: [DisassembledFunction]] = [:]
        for function in functions {
            let owner = ownerName(of: function.displayName)
            if buckets[owner] == nil { order.append(owner) }
            buckets[owner, default: []].append(function)
        }
        return order.map { (owner: $0, functions: buckets[$0] ?? []) }
    }

    /// Best-effort owning type from a demangled function name.
    /// `sample.Point.distance(to:) -> …` → `sample.Point`
    /// `Point.area.getter : …`          → `Point`
    /// `sample.run() -> ()`             → `sample`
    static func ownerName(of demangled: String) -> String {
        // Take the qualified path up to the first `(`, ` `, or `:`.
        let head = demangled.prefix { $0 != "(" && $0 != " " && $0 != ":" }
        var components = head.split(separator: ".").map(String.init)
        let accessors: Set<String> = ["getter", "setter", "modify", "read", "init", "deinit", "_modify"]
        while let last = components.last, accessors.contains(last) {
            components.removeLast()
        }
        if components.count > 1 {
            components.removeLast() // drop the member name, keep the owner path
        }
        return components.isEmpty ? demangled : components.joined(separator: ".")
    }
}
