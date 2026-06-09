import Foundation
import MachOKit
import MachOSwiftSection
import SwiftDump

/// Derives function `address → name` mappings from Swift metadata that survives
/// stripping. Two sources:
///   - **Class vtable methods** — taken from the reconstructed declarations,
///     where SwiftDump already resolves type + member context.
///   - **Protocol-conformance witnesses** — read directly from each
///     conformance's witness table, named `<Type>: <Protocol>.<kind>`.
///
/// Struct/enum *non-protocol* methods are intentionally absent: with static
/// dispatch they have no metadata record, so they can't be named from a
/// stripped binary (only their boundaries are recovered, via function-starts).
struct MetadataSymbolizer: Sendable {
    var preset: DemanglePreset

    init(preset: DemanglePreset) {
        self.preset = preset
    }

    /// Full `address → name` map, classes first (witnesses don't overwrite).
    func functionNames(in machO: MachOFile) async -> [UInt64: String] {
        var map = await classMethodNames(in: machO)
        for (address, name) in witnessNames(in: machO) where map[address] == nil {
            map[address] = name
        }
        return map
    }

    // MARK: - Class vtable methods (via reconstructed declarations)

    private func classMethodNames(in machO: MachOFile) async -> [UInt64: String] {
        let dump = await SwiftDeclarationDumper(preset: preset).dump(machO, sections: [.types])
        var map: [UInt64: String] = [:]
        var currentType: String?

        for rawLine in dump.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let typeName = parseTypeHeader(line) {
                currentType = typeName
                continue
            }
            if line == "}" { currentType = nil; continue }

            for token in line.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }) {
                guard token.hasPrefix("sub_"),
                      let address = UInt64(token.dropFirst(4), radix: 16)
                else { continue }
                if map[address] != nil { continue }
                let kind = parseKind(line)
                map[address] = currentType.map { "\($0).\(kind)" } ?? kind
            }
        }
        return map
    }

    // MARK: - Protocol-conformance witnesses (via the witness table)

    private func witnessNames(in machO: MachOFile) -> [UInt64: String] {
        guard let conformances = try? machO.swift.protocolConformances else { return [:] }
        let imageBase = machO.address(forOffset: 0)
        let pointerSize = MemoryLayout<UInt64>.size
        var map: [UInt64: String] = [:]

        for conformance in conformances {
            guard let protocolDescriptor = conformance.protocol?.resolved,
                  let pattern = conformance.witnessTablePattern,
                  let proto = try? MachOSwiftSection.Protocol(descriptor: protocolDescriptor, in: machO)
            else { continue }

            let protocolName = proto.name
            let owner = conformingTypeName(conformance, in: machO).map { "\($0): \(protocolName)" } ?? protocolName

            // Witness table layout: slot 0 is the conformance/descriptor; the
            // requirements' implementations follow at slot (index + 1).
            for (index, requirement) in proto.requirements.enumerated() {
                guard let kind = functionKindLabel(requirement.layout.flags.kind) else { continue }
                let slotOffset = pattern.offset + pointerSize * (index + 1)
                guard let runtimeOffset = machO.resolveRebase(at: UInt64(slotOffset)) else { continue }
                let address = imageBase + runtimeOffset
                if map[address] == nil {
                    map[address] = "\(owner).\(kind)"
                }
            }
        }
        return map
    }

    /// Simple (unqualified) name of the type a conformance is declared on.
    private func conformingTypeName(
        _ conformance: ProtocolConformance,
        in machO: MachOFile
    ) -> String? {
        guard let resolved = try? conformance.descriptor.resolvedTypeReference(in: machO) else {
            return nil
        }
        switch resolved {
        case .directTypeDescriptor(let wrapper):
            return wrapper.flatMap { typeName(of: $0, in: machO) }
        case .directObjCClassName(let name):
            return name
        case .indirectTypeDescriptor, .indirectObjCClass:
            return nil // best-effort: skip indirected references
        }
    }

    private func typeName(of wrapper: ContextDescriptorWrapper, in machO: MachOFile) -> String? {
        guard case .type(let typeWrapper) = wrapper else { return nil }
        switch typeWrapper {
        case .enum(let descriptor): return try? descriptor.name(in: machO)
        case .struct(let descriptor): return try? descriptor.name(in: machO)
        case .class(let descriptor): return try? descriptor.name(in: machO)
        }
    }

    /// Maps a requirement kind to a short label, or nil for non-function
    /// requirements (base protocols, associated-type/conformance accessors).
    private func functionKindLabel(_ kind: ProtocolRequirementKind) -> String? {
        switch kind {
        case .method: return "method"
        case .`init`: return "init"
        case .getter: return "getter"
        case .setter: return "setter"
        case .readCoroutine: return "read"
        case .modifyCoroutine: return "modify"
        case .baseProtocol, .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
            return nil
        }
    }

    // MARK: - Declaration-text parsing helpers

    /// `class sample.Dog: sample.Animal {` → `sample.Dog`; member lines → nil.
    private func parseTypeHeader(_ line: String) -> String? {
        guard let first = line.first, !first.isWhitespace else { return nil }
        let tokens = line.split(separator: " ").map(String.init)
        let keywords: Set<String> = ["struct", "enum", "class", "actor"]
        guard let keywordIndex = tokens.firstIndex(where: { keywords.contains($0) }),
              keywordIndex + 1 < tokens.count
        else { return nil }
        var name = tokens[keywordIndex + 1]
        if let cut = name.firstIndex(where: { $0 == ":" || $0 == "{" || $0 == "<" }) {
            name = String(name[..<cut])
        }
        return name.isEmpty ? nil : name
    }

    /// Extract a short kind from a `/* [ Init ] */`-style comment on the line.
    private func parseKind(_ line: String) -> String {
        if let open = line.range(of: "/*"), let close = line.range(of: "*/"),
           open.upperBound <= close.lowerBound {
            let inner = line[open.upperBound..<close.lowerBound]
                .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
            if let firstWord = inner.split(separator: " ").first {
                return firstWord.lowercased()
            }
        }
        return "func"
    }
}
