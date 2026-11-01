import Foundation
import MachOKit
import MachOSwiftSection
import Demangling
// `SymbolicDemangler` is SPI, as in FieldMap and MetadataSymbolizer.
@_spi(Internals) import SwiftInspection

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
    /// Full descriptor identity, including module and enclosing types.
    private let byQualifiedName: [String: [String]]
    /// Imported C types (`__C.NSComparisonResult`) whose value witness table
    /// the loader binds to a builtin integer's (`$sBi64_WV`), by qualified
    /// name: each is that integer, in one register.
    private let importedIntegerBits: [String: Int]

    public init(byName: [String: [String]?] = [:], byQualifiedName: [String: [String]] = [:],
                importedIntegerBits: [String: Int] = [:]) {
        self.byName = byName
        self.byQualifiedName = byQualifiedName
        self.importedIntegerBits = importedIntegerBits
    }

    /// Whether `typeName` is an imported C type this image proves an integer
    /// of at most 64 bits: an `NS_ENUM` or `NS_OPTIONS` passes as its raw
    /// value, one register.
    public func isImportedInteger(_ typeName: String) -> Bool {
        importedIntegerBits[typeName] != nil
    }

    private func cases(for typeName: String) -> [String]? {
        // A qualified type may belong to another image. Falling back to a
        // same-named local enum would attach that enum's cases to the foreign
        // type, even though the return signature names the foreign module.
        if typeName.contains(".") { return byQualifiedName[typeName] }
        return byName[typeName] ?? nil
    }

    /// The case name for `tag` of the enum named by `typeName` (which may be
    /// module-qualified, e.g. `Module.Color` or `Module.Outer.Color`), or `nil`
    /// when the enum is unknown, ambiguous, carries payloads, or `tag` is out of
    /// range. The out-of-range guard matters: an unrelated integer that merely
    /// happens to sit in the result register of an enum-typed function must not
    /// be dressed up as a case.
    public func caseName(ofEnum typeName: String, tag: Int) -> String? {
        guard let cases = cases(for: typeName) else { return nil }
        guard tag >= 0, tag < cases.count else { return nil }
        return cases[tag]
    }

    /// Whether `typeName` (possibly module-qualified) names a no-payload enum
    /// this image publishes unambiguously — i.e. one whose cases this index can
    /// name. A no-payload enum is a trivial integer tag in a single register, so
    /// this is also the safe gate for seeding such a parameter as a scalar.
    public func isNoPayloadEnum(_ typeName: String) -> Bool {
        cases(for: typeName) != nil
    }

    /// All valid tags must survive a proposed integer projection before that
    /// projection can be hidden in source-level enum comparisons.
    func tagsFit(_ typeName: String, unsignedBits: Int) -> Bool {
        guard unsignedBits > 0, unsignedBits <= 64 else { return false }
        guard let cases = cases(for: typeName), !cases.isEmpty else { return false }
        return unsignedBits == 64 || UInt64(cases.count - 1) < (UInt64(1) << unsignedBits)
    }

    /// The number of enums indexed (unambiguous + ambiguous), for diagnostics.
    public var count: Int { byName.count }

    public static func build(in machO: MachOFile) -> EnumCaseIndex {
        var seen: [String: [String]] = [:]
        var ambiguous: Set<String> = []
        var byQualifiedName: [String: [String]] = [:]
        var ambiguousQualifiedNames: Set<String> = []
        for type in UnrecordedTypes.all(in: machO) {
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
            if let qualified = FieldMapBuilder.qualifiedName(of: type, in: machO) {
                if let existing = byQualifiedName[qualified], existing != cases {
                    ambiguousQualifiedNames.insert(qualified)
                }
                byQualifiedName[qualified] = cases
            }
        }
        var byName: [String: [String]?] = [:]
        for (name, cases) in seen {
            byName[name] = ambiguous.contains(name) ? nil : cases
        }
        for name in ambiguousQualifiedNames { byQualifiedName.removeValue(forKey: name) }
        return EnumCaseIndex(byName: byName, byQualifiedName: byQualifiedName,
                             importedIntegerBits: importedIntegerBits(in: machO))
    }

    /// Imported types the image's foreign metadata proves integers. A foreign
    /// type's metadata candidate is its value witness table pointer, then its
    /// kind, then its descriptor (swift/include/swift/ABI/Metadata.h,
    /// `TargetForeignTypeMetadata`); an imported integer enum or option set
    /// shares the builtin integer's table, which the loader binds:
    /// `_$sBi64_WV` for `NSComparisonResult`, an `NSInteger`. Standalone files
    /// with chained fixups only; a name two candidates give different widths
    /// is left out.
    static func importedIntegerBits(in machO: MachOFile) -> [String: Int] {
        guard machO.cache == nil, let fixups = machO.dyldChainedFixups, let starts = fixups.startsInImage,
              let base = machO.segments.first(where: { $0.segmentName == "__TEXT" })?.virtualMemoryAddress
        else { return [:] }
        // Keyed by the name a signature demangles to, which for an imported
        // type is its C name (`__C.NSComparisonResult`), where the
        // descriptor's own name is the Swift one (`ComparisonResult`).
        var descriptors: [Int: String] = [:]
        for type in UnrecordedTypes.all(in: machO) {
            let wrapper: TypeContextDescriptorWrapper = switch type {
            case .enum(let m): .enum(m.descriptor)
            case .struct(let m): .struct(m.descriptor)
            case .class(let m): .class(m.descriptor)
            }
            guard let node = try? SymbolicDemangler.demangleContext(for: .type(wrapper), in: machO.context)
            else { continue }
            let name = node.print(using: .default)
            guard name.hasPrefix("__C.") else { continue }
            descriptors[SwiftDeclarationDumper.descriptorOffset(of: type)] = name
        }
        guard !descriptors.isEmpty else { return [:] }
        let table = Disassembler.ChainedFixupTable()
        var bits: [String: Int] = [:]
        var conflicting: Set<String> = []
        let imports = fixups.imports
        for segment in fixups.startsInSegments(of: starts) {
            for pointer in fixups.pointers(of: segment, in: machO) {
                guard pointer.fixupInfo.bind != nil,
                      let (ordinal, _) = pointer.bindOrdinalAndAddend(for: machO),
                      imports.indices.contains(ordinal),
                      let symbol = fixups.symbolName(for: imports[ordinal].info.nameOffset),
                      let width = builtinIntegerWidth(ofWitnessTable: symbol)
                else { continue }
                let offset = pointer.offset
                // Struct (0x200) or enum (0x201) metadata.
                guard let kind = UnrecordedTypes.read(offset + 8, as: UInt64.self, in: machO),
                      kind == 0x200 || kind == 0x201,
                      let target = table.rebaseTarget(at: UInt64(offset + 16), in: machO),
                      let fileOffset = machO.fileOffset(of: UInt64(base) + target),
                      let name = descriptors[Int(fileOffset)]
                else { continue }
                if let existing = bits[name], existing != width { conflicting.insert(name) }
                bits[name] = width
            }
        }
        for name in conflicting { bits.removeValue(forKey: name) }
        return bits
    }

    /// N for `_$sBiN_WV` (the value witness table of `Builtin.IntN`), N a
    /// power of two from 8 to 64.
    static func builtinIntegerWidth(ofWitnessTable symbol: String) -> Int? {
        guard symbol.hasPrefix("_$sBi"), symbol.hasSuffix("_WV"),
              let width = Int(symbol.dropFirst("_$sBi".count).dropLast("_WV".count)),
              [8, 16, 32, 64].contains(width)
        else { return nil }
        return width
    }
}
