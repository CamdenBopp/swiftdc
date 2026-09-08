import Foundation
import MachOKit
import MachOSwiftSection
import SwiftLayout
import SwiftInspection

/// Names a **payload** enum's *empty* case when a function returns it as a
/// constant — but only when the encoding is *provable*, never guessed.
///
/// `EnumCaseIndex` deliberately declines payload enums: a bare returned immediate
/// is not a declaration index, so naming a case from it would be a fabrication.
/// That decline is correct as far as it goes. What it lacks is the enum's real
/// encoding — which `SwiftLayout`'s `StaticLayoutCalculator.enumCaseLayoutResult`
/// computes offline through `SwiftInspection.EnumLayoutCalculator` (the audited
/// port of the runtime's `getEnumTag*` formulas). For a *tagged* multi-payload
/// enum like `Token { eof; number(Int); ident(Int) }` it resolves `.eof` to the
/// exact bytes `payload 0, tag byte 2` (`patternResolution == .exactBytes`).
///
/// So an empty case whose pattern is `.exactBytes` can be named soundly: assemble
/// the returned value's bytes from the return registers (a direct-return enum of
/// ≤ 16 bytes puts bytes 0..<8 in x0 and 8..<16 in x1) and require an *exact*
/// match of every fixed byte. That match is a proof, not a guess — a misread or
/// an indirect return will not coincidentally equal `payload 0 ∧ tag 2`, which by
/// definition *is* `.eof`. Anything short of a unique exact match declines:
///
///   - a case whose bytes depend on the payload's extra-inhabitant scheme
///     (`.unresolvedExtraInhabitant`) — only the in-process runtime projector can
///     resolve those, and this is a static tool;
///   - an enum larger than 16 bytes (returned indirectly via x8, so x0/x1 do not
///     hold the value);
///   - a fixed byte at an offset the two registers cannot source;
///   - more than one empty case matching the observed bytes;
///   - an enum whose simple name is ambiguous across the image.
///
/// Payload *cases* are out of scope: they carry a live associated value, so they
/// are never returned as a bare constant.
public struct PayloadEnumCaseIndex: Sendable {
    /// One statically-resolved empty case: its source name plus the fixed byte
    /// pattern that identifies it (offset → value, with the fixed-bit mask per
    /// byte; an absent mask means every bit is fixed).
    struct ExactEmptyCase: Sendable {
        let name: String
        let fixedBytes: [Int: UInt8]
        let masks: [Int: UInt8]
    }

    /// One indexed enum: its total size (to gate the direct-return register
    /// mapping) and its resolvable empty cases.
    struct Entry: Sendable {
        let size: Int
        let cases: [ExactEmptyCase]
    }

    /// Simple name → entry, `nil` when the simple name is ambiguous across the
    /// image (two distinct payload enums, different layouts) so it declines
    /// rather than guessing which one a receiver meant.
    private let byName: [String: Entry?]
    /// Fully-qualified name → entry. Qualified names are unique, so a caller that
    /// knows the qualified return type resolves its own enum even when the simple
    /// name collided and was dropped.
    private let byQualifiedName: [String: Entry]

    init(byName: [String: Entry?] = [:], byQualifiedName: [String: Entry] = [:]) {
        self.byName = byName
        self.byQualifiedName = byQualifiedName
    }

    /// The number of enums indexed, for diagnostics.
    public var count: Int { byName.count }

    /// The empty-case name for a payload enum returned in `x0` (bytes 0..<8) and,
    /// for a value spanning a second register, `x1` (bytes 8..<16) — or `nil`
    /// (decline) when the enum is unknown/ambiguous/oversize, a register cannot
    /// source a fixed byte, or the observed bytes do not match exactly one case.
    public func caseName(ofEnum typeName: String, x0: UInt64, x1: UInt64?) -> String? {
        guard let entry = resolve(typeName), entry.size <= 16 else { return nil }

        // The byte at `offset` of the returned value, sourced from the register it
        // lands in; nil when no register covers it (so the case cannot be verified).
        func byte(at offset: Int) -> UInt8? {
            if offset < 0 { return nil }
            if offset < 8 { return UInt8((x0 >> (offset * 8)) & 0xFF) }
            if offset < 16, let x1 { return UInt8((x1 >> ((offset - 8) * 8)) & 0xFF) }
            return nil
        }

        var matched: [String] = []
        for candidate in entry.cases {
            var isExactMatch = true
            for (offset, value) in candidate.fixedBytes {
                let mask = candidate.masks[offset] ?? 0xFF
                guard let actual = byte(at: offset), (actual & mask) == (value & mask) else {
                    isExactMatch = false
                    break
                }
            }
            if isExactMatch { matched.append(candidate.name) }
        }
        // A unique exact match only — never a coin-flip between two candidates.
        return matched.count == 1 ? matched[0] : nil
    }

    private func resolve(_ typeName: String) -> Entry? {
        if let exact = byQualifiedName[typeName] { return exact }
        let simple = typeName.split(separator: ".").last.map(String.init) ?? typeName
        guard let entry = byName[simple] else { return nil }
        return entry   // may be nil (ambiguous) → decline
    }

    public static func build(in machO: MachOFile) -> PayloadEnumCaseIndex {
        guard let calculator = try? StaticLayoutCalculator(machO: machO) else {
            return PayloadEnumCaseIndex()
        }
        var seen: [String: Entry] = [:]
        var ambiguous: Set<String> = []
        var byQualified: [String: Entry] = [:]

        for type in (try? machO.swift.types) ?? [] {
            guard case .enum(let model) = type else { continue }
            let descriptor = model.descriptor
            // Payload enums only: a no-payload enum is `EnumCaseIndex`'s domain
            // (its bare tag IS the declaration index).
            guard descriptor.numberOfPayloadCases > 0 else { continue }
            guard let name = try? descriptor.name(in: machO) else { continue }

            // Size gates the direct-return register mapping: a value > 16 bytes is
            // returned indirectly (x8), so x0/x1 do not hold it.
            guard let size = (try? calculator.typeLayout(forDescriptor: .enum(descriptor)))?.size,
                  size <= 16,
                  let layout = calculator.enumCaseLayoutResult(forDescriptor: .enum(descriptor))
            else { continue }

            let exactEmptyCases: [ExactEmptyCase] = layout.cases.compactMap { projection in
                guard !projection.isPayloadCase,
                      projection.patternResolution == .exactBytes,
                      let declaredName = projection.declaredName
                else { return nil }
                let masks = Dictionary(uniqueKeysWithValues:
                    projection.memoryChanges.keys.map { ($0, projection.fixedBitMask(atByteOffset: $0)) })
                return ExactEmptyCase(name: declaredName, fixedBytes: projection.memoryChanges, masks: masks)
            }
            guard !exactEmptyCases.isEmpty else { continue }
            let entry = Entry(size: size, cases: exactEmptyCases)

            if let existing = seen[name], !entriesEquivalent(existing, entry) {
                ambiguous.insert(name)
            } else {
                seen[name] = entry
            }
            if let qualified = FieldMapBuilder.qualifiedName(of: type, in: machO) {
                byQualified[qualified] = entry
            }
        }

        var byName: [String: Entry?] = [:]
        for (name, entry) in seen {
            byName[name] = ambiguous.contains(name) ? nil : entry
        }
        return PayloadEnumCaseIndex(byName: byName, byQualifiedName: byQualified)
    }

    /// Two entries are equivalent when they name the same empty cases with the
    /// same patterns — so two same-named enums with identical layouts are not
    /// treated as an ambiguous collision.
    private static func entriesEquivalent(_ a: Entry, _ b: Entry) -> Bool {
        guard a.size == b.size, a.cases.count == b.cases.count else { return false }
        let aByName = Dictionary(a.cases.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for caseB in b.cases {
            guard let caseA = aByName[caseB.name],
                  caseA.fixedBytes == caseB.fixedBytes, caseA.masks == caseB.masks
            else { return false }
        }
        return true
    }
}
