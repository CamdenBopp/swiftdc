import ArgumentParser
import Foundation
import SwiftDecompilerCore

struct LayoutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "layout",
        abstract: "Show each Swift type's stored-property layout: byte offset → field.",
        discussion: """
        Offsets come from __swift5_fieldmd metadata and are computed offline, so \
        they are runtime-exact and — unlike method signatures — survive stripping \
        completely. This is the reverse index that turns `ldr x8, [x0, #0x10]` \
        into `self.name`.

        Offsets are trustworthy only as a PREFIX. Swift lays out fields in \
        declaration order, and the first field that cannot be resolved (a \
        resilient cross-module type, an existential, an unsubstituted generic) \
        makes every offset after it unknown rather than merely unnamed. Where \
        that happens the type is reported with its trusted limit and the reason, \
        and nothing past it is named.
        """
    )

    @Argument(help: "Path to the Mach-O (or fat) binary, .app, .framework, or .ipa.")
    var path: String?

    @Option(name: [.short, .customLong("arch")], help: "Architecture slice for fat binaries.")
    var architecture: String?

    @Option(name: .customLong("image"), help: "Read this image from the dyld shared cache by name.")
    var image: String?

    @Option(name: .customLong("cache"), help: "Path to a dyld_shared_cache_* file.")
    var cache: String?

    @Option(name: .customLong("binary"), help: "For an .app/.framework/.ipa: analyze this embedded binary by name.")
    var binary: String?

    @Option(name: [.short, .long], help: "Only show types whose name contains this string.")
    var type: String?

    @Option(name: .long, help: "Resolve one offset into this type, as `swiftdc layout Bin --type Dog --at 0x10`.")
    var at: String?

    @Option(name: .long, help: "Access width in bytes for --at. Default 8.")
    var bytes: Int = 8

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON.")
    var json = false

    func run() throws {
        let machO = try BinaryLoader.loadMachO(
            path: path, architecture: architecture, image: image, cachePath: cache, binary: binary
        )
        var maps = try FieldMapBuilder.build(in: machO)
        if let needle = type?.lowercased() {
            maps = maps.filter { $0.key.lowercased().contains(needle) }
        }
        guard !maps.isEmpty else {
            try emit(json ? "[]" : "// No Swift types with a resolvable field layout.", to: output)
            return
        }

        if let at {
            try emit(renderLookup(maps, at: at), to: output)
            return
        }
        try emit(json ? renderJSON(maps) : renderText(maps), to: output)
    }

    /// `--at`: the exact query the disassembler will make.
    private func renderLookup(_ maps: [String: FieldMap], at: String) throws -> String {
        let trimmed = at.hasPrefix("0x") ? String(at.dropFirst(2)) : at
        guard let offset = Int(trimmed, radix: at.hasPrefix("0x") ? 16 : 10) else {
            throw ValidationError("--at must be a decimal or 0x-prefixed offset")
        }
        var lines: [String] = []
        for (name, map) in maps.sorted(by: { $0.key < $1.key }) {
            switch map.lookup(offset: offset, bytes: bytes) {
            case .success(let hit):
                lines.append("\(name)  +0x\(String(offset, radix: 16)) [\(bytes)] -> self.\(hit.rendered)")
            case .failure(let reason):
                lines.append("\(name)  +0x\(String(offset, radix: 16)) [\(bytes)] -> <unnamed: \(describe(reason))>")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func renderText(_ maps: [String: FieldMap]) -> String {
        var blocks: [String] = []
        for (name, map) in maps.sorted(by: { $0.key < $1.key }) {
            var lines = ["\(name)  // instance size \(map.instanceSize) bytes"]
            for field in map.fields {
                let offset = "0x" + String(field.offset, radix: 16)
                lines.append("  +\(offset.padding(toLength: max(6, offset.count), withPad: " ", startingAt: 0)) \(field.bytes)B  \(field.name): \(field.typeMangledName)")
            }
            if let reason = map.trustLimitReason {
                lines.append("  // offsets past 0x\(String(map.trustedOffsetLimit, radix: 16)) are NOT trusted: \(reason)")
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    private func renderJSON(_ maps: [String: FieldMap]) -> String {
        let payload = maps.sorted { $0.key < $1.key }.map { name, map in
            [
                "type": name,
                "instanceSize": map.instanceSize,
                "trustedOffsetLimit": map.trustedOffsetLimit,
                "trustLimitReason": map.trustLimitReason as Any,
                "fields": map.fields.map {
                    ["offset": $0.offset, "bytes": $0.bytes, "name": $0.name, "type": $0.typeMangledName] as [String: Any]
                },
            ] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private func describe(_ failure: FieldLookupFailure) -> String {
        switch failure {
        case .pastInstanceSize(let size): return "past instance size \(size)"
        case .pastTrustedPrefix(let limit, let reason): return "past trusted prefix 0x\(String(limit, radix: 16)) — \(reason)"
        case .padding: return "padding"
        case .noLayout(let reason): return "no layout — \(reason)"
        }
    }
}
