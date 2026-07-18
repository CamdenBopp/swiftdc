import Foundation
import MachOKit
import MachOSwiftSection

/// Maps a **no-payload** Swift enum to its case names in tag order.
///
/// For an enum with no payload cases, the runtime assigns each case a tag equal
/// to its declaration index (`0, 1, 2, …`), and `__swift5_fieldmd` lists the
/// cases in that same declaration order. So `records[tag].fieldName` is the case
/// name for a returned or compared tag value — recoverable with no symbols, and
/// surviving `strip` completely (field-reflection metadata is not stripped).
///
/// Deliberately excludes payload enums. Their tag encoding interleaves payload
/// cases (low tags) with empty cases spilled across the payload's spare bits and
/// an extra discriminator, so a bare immediate does *not* index the record list
/// in declaration order. Naming a payload-enum case from a raw tag would be a
/// guess, so this declines and the raw value is printed instead — the project's
/// "never invent" rule, enforced by a table rather than by vigilance.
public struct EnumCaseIndex: Sendable {
    /// Simple enum name → case names in tag/declaration order. A name maps to
    /// `nil` when it is *ambiguous* — two distinct no-payload enums in the image
    /// share the simple name with different case lists — which forces a decline
    /// rather than a coin-flip between two candidates.
    private let byName: [String: [String]?]

    public init(byName: [String: [String]?] = [:]) { self.byName = byName }

    /// The case name for `tag` of the enum named by `typeName` (which may be
    /// module-qualified, e.g. `Module.Color` or `Module.Outer.Color`), or `nil`
    /// when the enum is unknown, ambiguous, carries payloads, or `tag` is out of
    /// range. The out-of-range guard matters: an unrelated integer that merely
    /// happens to sit in the result register of an enum-typed function must not
    /// be dressed up as a case.
    public func caseName(ofEnum typeName: String, tag: Int) -> String? {
        let simple = typeName.split(separator: ".").last.map(String.init) ?? typeName
        guard let entry = byName[simple], let cases = entry else { return nil }
        guard tag >= 0, tag < cases.count else { return nil }
        return cases[tag]
    }

    /// The number of enums indexed (unambiguous + ambiguous), for diagnostics.
    public var count: Int { byName.count }

    public static func build(in machO: MachOFile) -> EnumCaseIndex {
        var seen: [String: [String]] = [:]
        var ambiguous: Set<String> = []
        for type in (try? machO.swift.types) ?? [] {
            guard case .enum(let model) = type else { continue }
            let descriptor = model.descriptor
            // No-payload enums only: a payload enum's tags don't index the case
            // list, so its bare immediate is not a declaration index.
            guard descriptor.numberOfPayloadCases == 0 else { continue }
            guard let name = try? descriptor.name(in: machO),
                  let records = try? descriptor.fieldDescriptor(in: machO).records(in: machO)
            else { continue }
            let cases = records.compactMap { try? $0.fieldName(in: machO) }
            // Every case name must have resolved and the count must match the
            // descriptor, or the tag→index mapping has a hole and can't be
            // trusted for any index.
            guard cases.count == records.count,
                  cases.count == descriptor.numberOfCases,
                  !cases.isEmpty
            else { continue }
            if let existing = seen[name], existing != cases {
                ambiguous.insert(name)
            } else {
                seen[name] = cases
            }
        }
        var byName: [String: [String]?] = [:]
        for (name, cases) in seen {
            byName[name] = ambiguous.contains(name) ? nil : cases
        }
        return EnumCaseIndex(byName: byName)
    }
}
