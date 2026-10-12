import Foundation
import MachOKit

/// Produces a combined human-readable report: reconstructed Swift declarations
/// followed by ARM64 disassembly grouped by the owning type.
public struct AnalysisReport: Sendable {
    public var preset: DemanglePreset

    public init(preset: DemanglePreset = .default) {
        self.preset = preset
    }

    // MARK: - File input (llvm-objdump disassembly)

    /// Structured JSON: `{ declarations: [...], objc: [...], functions: [...] }`.
    public func generateJSON(path: String, architecture: String? = nil) async throws -> String {
        try await report(path: path, architecture: architecture, json: true).text
    }

    public func generate(path: String, architecture: String? = nil) async throws -> String {
        try await report(path: path, architecture: architecture, json: false).text
    }

    /// The report, and the reason disassembly failed if it did. The
    /// declarations still print: a failed disassembly should not sink them.
    /// But the failure is stated, never shown as an empty result. With
    /// `try?` here, `analyze` printed `(no functions recovered)` and exited 0
    /// when llvm-objdump could not run, while `disasm` on the same file
    /// exited 1.
    public func report(path: String, architecture: String? = nil, json: Bool)
        async throws -> (text: String, disassemblyError: String?) {
        let machO = try BinaryLoader.load(path: path, architecture: architecture)
        let functions: [DisassembledFunction]
        let failure: String?
        do {
            functions = try await Disassembler(preset: preset).disassemble(path: path, architecture: architecture)
            failure = nil
        } catch {
            functions = []
            failure = String(describing: error)
        }
        let text = json
            ? await self.json(machO: machO, functions: functions, failure: failure)
            : await self.text(machO: machO, functions: functions, failure: failure)
        return (text, failure)
    }

    // MARK: - Pre-loaded image input (in-process Capstone disassembly)

    /// Text report for an already-loaded image — e.g. a dyld shared-cache
    /// framework, which has no standalone file. Disassembly is in-process.
    public func generate(machO: MachOFile) async -> String {
        let functions = await Disassembler(preset: preset).disassemble(machO: machO)
        return await text(machO: machO, functions: functions)
    }

    /// JSON report for an already-loaded image (in-process disassembly).
    public func generateJSON(machO: MachOFile) async -> String {
        let functions = await Disassembler(preset: preset).disassemble(machO: machO)
        return await json(machO: machO, functions: functions)
    }

    // MARK: - Rendering (shared by both input paths)

    private func json(machO: MachOFile, functions: [DisassembledFunction], failure: String? = nil) async -> String {
        let declarations = await SwiftDeclarationDumper(preset: preset).dump(machO)
        let objc = ObjCDumper().blocks(machO)
        return reportJSON(declarations: declarations, objc: objc, functions: functions, disassemblyError: failure)
    }

    private func text(machO: MachOFile, functions: [DisassembledFunction], failure: String? = nil) async -> String {
        let declarations = await SwiftDeclarationDumper(preset: preset).dump(machO)
        let objc = ObjCDumper().dump(machO)

        var out = ""
        out += banner("SWIFT DECLARATIONS")
        out += declarations.isEmpty ? "// (no Swift type metadata found)\n" : declarations + "\n"

        if !objc.isEmpty {
            out += "\n" + banner("OBJECTIVE-C")
            out += objc + "\n"
        }

        out += "\n" + banner("DISASSEMBLY")
        if let failure {
            out += "// disassembly failed: \(failure)\n"
        } else if functions.isEmpty {
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
            let owner = function.objcMethod?.ownerName ?? ownerName(of: function.displayName)
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
