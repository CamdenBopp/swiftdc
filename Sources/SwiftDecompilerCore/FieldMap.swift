import Foundation
import MachOKit
import MachOSwiftSection
import SwiftLayout

/// What a memory access at a given offset into a Swift value resolves to.
public enum FieldHit: Sendable, Equatable {
    /// The access covers exactly one field.
    case whole(name: String, typeMangledName: String)
    /// The access lands strictly inside one field (a sub-word read of an Int, or
    /// one half of a two-word value).
    case part(name: String, typeMangledName: String, subOffset: Int, bytes: Int)
    /// The access spans more than one field. `Swift.String` is 16 bytes and
    /// arrives as `ldp x8, x9, [x0, #0x10]`, so this is not an edge case — a
    /// size-gated point lookup would reject its own headline example.
    case spans(names: [String])

    /// A rendered access path, e.g. `name` or `origin[0..8]`.
    public var rendered: String {
        switch self {
        case .whole(let name, _): return name
        case .part(let name, _, let subOffset, let bytes):
            return subOffset == 0 ? name : "\(name)[\(subOffset)..<\(subOffset + bytes)]"
        case .spans(let names): return names.joined(separator: "+")
        }
    }
}

/// Why an offset could not be named. Every one of these is a reason to print
/// nothing rather than to guess.
///
/// Modelled as a `Result` failure rather than an optional so that "I don't know"
/// is a value the type system forces every consumer to handle, with the concrete
/// reason attached. This is the one place `never invent` typechecks.
public enum FieldLookupFailure: Error, Sendable, Equatable {
    /// Past the end of the instance. Not decoration: `ManagedBuffer` and
    /// `_ContiguousArrayStorage` tail-allocate, so an access into the element
    /// area would otherwise land inside the header's last field range and
    /// resolve to a real field name of a real type.
    case pastInstanceSize(instanceSize: Int)
    /// At or past the first field this type could not lay out. Offsets are only
    /// trustworthy as a *prefix*: SwiftLayout stops computing at the first
    /// unresolvable field, and every subsequent offset is then unknown, not
    /// merely unlabelled.
    case pastTrustedPrefix(limit: Int, reason: String)
    /// Inside the instance and inside the trusted prefix, but in no field —
    /// alignment padding.
    case padding
    /// The type has no usable layout at all.
    case noLayout(reason: String)
}

/// A reverse index from byte offset to stored property, for one Swift type.
///
/// This is the primitive behind the project's one real differentiator: turning
/// `ldr x8, [x0, #0x10]` into `self.name`. The offsets come from
/// `__swift5_fieldmd` metadata and are computed offline — they are runtime-exact
/// and, unlike method signatures, they **survive stripping completely**.
///
/// For classes the offsets already include the superclass prefix, so a raw
/// `[x0, #N]` displacement maps directly with no adjustment.
public struct FieldMap: Sendable {
    public let typeName: String
    /// Total instance size in bytes.
    public let instanceSize: Int
    /// The first offset that is NOT trustworthy.
    ///
    /// SwiftLayout resolves fields in declaration order and gives up at the
    /// first one it cannot lay out (a resilient cross-module type, an
    /// existential, an unsubstituted generic). Every field after that has an
    /// offset that is *unknown*, not merely unnamed — so naming anything at or
    /// past this limit would be a fabrication.
    public let trustedOffsetLimit: Int
    /// Why the trusted prefix ends where it does, when it ends early.
    public let trustLimitReason: String?

    /// Sorted, non-overlapping `[start, end)` ranges of the trusted fields.
    private let ranges: [(range: Range<Int>, name: String, typeMangledName: String)]

    /// Build from a resolved aggregate layout.
    ///
    /// Only `.computed` fields are indexed, and only the leading run of them:
    /// the first unresolved field closes the trusted prefix.
    public init(typeName: String, layout: AggregateFieldLayout) {
        self.typeName = typeName
        self.instanceSize = layout.size

        var ranges: [(Range<Int>, String, String)] = []
        var limit = layout.size
        var reason: String?
        for field in layout.fields {
            guard case .computed = field.resolution else {
                // The prefix ends here. Everything from this field onward has an
                // offset SwiftLayout could not compute.
                limit = field.offset
                reason = Self.describe(field.resolution)
                break
            }
            // A field with no size can't be given a range; treat it as opaque
            // but keep the prefix open, since its offset is still computed.
            guard let bytes = field.layout?.size, bytes > 0 else { continue }
            ranges.append((field.offset ..< (field.offset + bytes), field.fieldName, field.typeMangledName))
        }
        self.trustedOffsetLimit = limit
        self.trustLimitReason = reason
        self.ranges = ranges.sorted { $0.0.lowerBound < $1.0.lowerBound }
    }

    /// Build a fully-known field map from an ABI that publishes concrete field
    /// offsets and encodings directly. Objective-C ivar metadata is such an ABI:
    /// every `ivar_t` carries an absolute instance offset, and its encoded type
    /// gives the storage size for ordinary scalar, object, pointer, array, and
    /// aggregate ivars.
    ///
    /// Unlike the Swift-layout initializer, there is no unresolved suffix here:
    /// fields whose encoded size cannot be established are omitted individually
    /// instead of making later absolute offsets untrustworthy.
    init(
        typeName: String,
        instanceSize: Int,
        fields: [(offset: Int, bytes: Int, name: String, typeEncoding: String)]
    ) {
        self.typeName = typeName
        self.instanceSize = instanceSize
        self.trustedOffsetLimit = instanceSize
        self.trustLimitReason = nil
        self.ranges = fields.compactMap { field in
            guard field.offset >= 0, field.bytes > 0,
                  field.offset < instanceSize,
                  field.offset + field.bytes <= instanceSize
            else { return nil }
            return (
                field.offset ..< (field.offset + field.bytes),
                field.name,
                field.typeEncoding
            )
        }.sorted { $0.0.lowerBound < $1.0.lowerBound }
    }

    /// Resolve a memory access.
    ///
    /// A **range** query, not a point query: the access width matters, because a
    /// 16-byte `Swift.String` is loaded as a register pair and a `ldrb` reads one
    /// byte out of the middle of an `Int`.
    public func lookup(offset: Int, bytes: Int) -> Result<FieldHit, FieldLookupFailure> {
        guard offset >= 0, bytes > 0 else { return .failure(.padding) }
        // Trusted-prefix first, and deliberately so. When the layout gave up
        // early, `instanceSize` is itself understated (a Widget whose second
        // field is a resilient `Foundation.Date` reports size 16, not 48), so
        // blaming the instance size would name a number that is also wrong. The
        // actionable reason is the field that could not be laid out.
        if let reason = trustLimitReason, offset >= trustedOffsetLimit {
            return .failure(.pastTrustedPrefix(limit: trustedOffsetLimit, reason: reason))
        }
        guard offset < instanceSize else { return .failure(.pastInstanceSize(instanceSize: instanceSize)) }
        guard offset < trustedOffsetLimit else {
            return .failure(.pastTrustedPrefix(limit: trustedOffsetLimit, reason: trustLimitReason ?? "unresolved"))
        }
        guard !ranges.isEmpty else { return .failure(.noLayout(reason: trustLimitReason ?? "no fields")) }

        let access = offset ..< (offset + bytes)
        let touched = ranges.filter { $0.range.overlaps(access) }
        guard let first = touched.first else { return .failure(.padding) }
        if touched.count > 1 { return .success(.spans(names: touched.map(\.name))) }

        if access.lowerBound == first.range.lowerBound && access.upperBound == first.range.upperBound {
            return .success(.whole(name: first.name, typeMangledName: first.typeMangledName))
        }
        return .success(.part(
            name: first.name,
            typeMangledName: first.typeMangledName,
            subOffset: access.lowerBound - first.range.lowerBound,
            bytes: bytes
        ))
    }

    /// Every trusted field, in offset order — for `swiftdc layout`.
    public var fields: [(offset: Int, bytes: Int, name: String, typeMangledName: String)] {
        ranges.map { ($0.range.lowerBound, $0.range.count, $0.name, $0.typeMangledName) }
    }

    /// Field offsets when this type is a small homogeneous floating-point
    /// aggregate — 1–4 fields, all `Double` (or all `Float`), packed contiguously
    /// from offset 0 with no gaps. Such a value is passed in consecutive SIMD
    /// registers (an HFA), so a method can decompose `self`/an argument onto
    /// `d0…`. Nil for any other shape, so a non-HFA type never triggers the
    /// register-decomposition path.
    public var homogeneousFloatFieldOffsets: [Int]? {
        let members = fields.sorted { $0.offset < $1.offset }
        guard (1...4).contains(members.count) else { return nil }
        // Double mangles as `Sd`, Float as `Sf`; both are single scalars whose
        // storage size matches the element width.
        let elementBytes: Int
        if members.allSatisfy({ $0.typeMangledName == "Sd" && $0.bytes == 8 }) {
            elementBytes = 8
        } else if members.allSatisfy({ $0.typeMangledName == "Sf" && $0.bytes == 4 }) {
            elementBytes = 4
        } else {
            return nil
        }
        // Contiguous from 0, no padding — a genuine HFA, not a padded struct.
        for (index, member) in members.enumerated() where member.offset != index * elementBytes {
            return nil
        }
        return members.map(\.offset)
    }

    /// Field offsets when this type is a small struct passed in GENERAL registers:
    /// 1–4 word-sized (8-byte) `Int`/`UInt` fields packed contiguously from offset
    /// 0 (total ≤ 32 bytes). The Swift convention explodes such an all-integer
    /// value across the first four argument registers `x0…x3` — field at offset
    /// `8·n` arrives in `x{n}` (confirmed: a 4-field struct's `.failed.getter`,
    /// field +0x18, is `mov x0, x3; ret`). So a getter can read `self.field`
    /// directly from its register, and `Point.sum` reads `self.x + self.y`. The
    /// four-field cap is the ABI's own: a fifth word spills the whole value to an
    /// indirect `x20` pointer, which the `[x20]` guard in the decomposer catches.
    /// Nil for any other shape — sub-word packing, references (ARC), floats (an
    /// HFA), mixed integer/float (which would mis-map `x{n}` onto the SIMD bank),
    /// or a struct too large for registers all bail, so nothing outside this exact
    /// ABI shape triggers the decomposition.
    public var wordIntegerFieldOffsetsInRegisters: [Int]? {
        let members = fields.sorted { $0.offset < $1.offset }
        guard (1...4).contains(members.count),
              members.allSatisfy({ $0.bytes == 8 && ($0.typeMangledName == "Si" || $0.typeMangledName == "Su") })
        else { return nil }
        for (index, member) in members.enumerated() where member.offset != index * 8 {
            return nil
        }
        return members.map(\.offset)
    }

    private static func describe(_ resolution: FieldResolution) -> String {
        guard case .unknown(let reason) = resolution else { return "computed" }
        return "\(reason)"
    }
}

/// Builds `FieldMap`s for every nominal type in an image.
public enum FieldMapBuilder {
    /// Index a binary's types by name.
    ///
    /// Single-image only. `ImageUniverse.dependencyClosure` exists to resolve
    /// resilient cross-module field types through the shared cache, and would in
    /// principle extend the trusted prefix past a `Foundation.Date` field — but
    /// it **traps** (`Fatal error: Not enough bits to represent the passed
    /// value`, an uncatchable fatalError) on exactly those inputs: measured on
    /// Foundation from the host cache, and on a local binary with a resilient
    /// `Date`/`UUID` field. Since it either crashes or changes nothing, it is
    /// not wired up. The single-image path degrades honestly instead, reporting
    /// the field it could not lay out.
    public static func build(in machO: MachOFile) throws -> [String: FieldMap] {
        let calculator = try StaticLayoutCalculator(machO: machO)

        var built: [(name: String, qualified: String?, map: FieldMap)] = []
        for type in (try? machO.swift.types) ?? [] {
            guard let descriptor = Self.contextDescriptor(of: type),
                  let name = Self.name(of: type, in: machO)
            else { continue }
            // Per-type isolation: one type that fails to lay out must not take
            // the whole image with it.
            guard let layout = try? calculator.fieldLayout(of: descriptor), !layout.fields.isEmpty
            else { continue }
            built.append((name, Self.qualifiedName(of: type, in: machO), FieldMap(typeName: name, layout: layout)))
        }
        var maps = resolvingSimpleNameCollisions(built.map { ($0.name, $0.map) })
        // Also index each type by its FULLY-QUALIFIED name (`Module.Outer.Type`).
        // Qualified names are unique, so a caller that already resolved a qualified
        // self-type (the register-decomposition path names `Module.…​.Type`) finds
        // its OWN map even when the simple name collided and was dropped above —
        // recovering the correct fields the collision guard would otherwise decline.
        // The bare/simple-name path is unchanged: it never keys on a dotted name.
        for entry in built {
            guard let qualified = entry.qualified else { continue }
            maps[qualified] = entry.map
        }
        return maps
    }

    /// Index the built maps by simple name, DROPPING any name that two distinct
    /// nominal types claim with different layouts.
    ///
    /// Maps are keyed by the descriptor's SIMPLE name, and `namedFieldMap`
    /// resolves a demangled self-type through a last-component fallback — so two
    /// distinct types sharing a simple name (`FatArch.Layout` vs `MachHeader.Layout`,
    /// a plain-struct `Options` vs a dependency's OptionSet `Options`) collide on one
    /// key. Whichever is built last would otherwise win, and a getter for any of the
    /// others then names the WRONG type's fields (`Options.showCImportedTypes` → the
    /// OptionSet's `self.rawValue`). A name that resolves to two DIFFERENT layouts is
    /// ambiguous and dropped, so an ambiguous self-type declines rather than
    /// fabricating one claimant's fields under another's name. Isolated here so the
    /// rule is testable without a binary.
    ///
    /// This is the simple-name half of the rule. The precise recovery shipped
    /// alongside it: `buildMaps` also installs a QUALIFIED key per type, so a
    /// receiver whose fully-qualified name is known resolves to its own layout
    /// even when its simple name collided and was dropped here. Dropping is
    /// therefore the fallback for an unqualified receiver, not the only outcome.
    /// See docs/research/field-map-name-collision.md.
    static func resolvingSimpleNameCollisions(
        _ built: [(name: String, map: FieldMap)]
    ) -> [String: FieldMap] {
        var maps: [String: FieldMap] = [:]
        var signature: [String: String] = [:]
        var ambiguous: Set<String> = []
        for (name, map) in built {
            let sig = "\(map.instanceSize):"
                + map.fields.map { "\($0.offset).\($0.name)" }.joined(separator: ",")
            if let previous = signature[name], previous != sig {
                ambiguous.insert(name)
            } else {
                signature[name] = sig
            }
            maps[name] = map
        }
        for name in ambiguous { maps.removeValue(forKey: name) }
        return maps
    }

    private static func contextDescriptor(of type: TypeContextWrapper) -> TypeContextDescriptorWrapper? {
        switch type {
        case .enum(let model): return .enum(model.descriptor)
        case .struct(let model): return .struct(model.descriptor)
        case .class(let model): return .class(model.descriptor)
        }
    }

    private static func name(of type: TypeContextWrapper, in machO: MachOFile) -> String? {
        switch type {
        case .enum(let model): return try? model.descriptor.name(in: machO)
        case .struct(let model): return try? model.descriptor.name(in: machO)
        case .class(let model): return try? model.descriptor.name(in: machO)
        }
    }

    /// Fully-qualified name (`Module.Outer.Type`) by walking the descriptor's
    /// parent context chain to the module. Nil when a link is a symbol, an
    /// extension, or an anonymous/opaque context (no clean qualified name), so a
    /// caller falls back to the simple name rather than a fabricated one.
    static func qualifiedName(of type: TypeContextWrapper, in machO: MachOFile) -> String? {
        guard let own = name(of: type, in: machO) else { return nil }
        var components = [own]
        var next: SymbolOrElement<ContextWrapper>?
        switch type {
        case .enum(let m): next = try? m.parent(in: machO)
        case .struct(let m): next = try? m.parent(in: machO)
        case .class(let m): next = try? m.parent(in: machO)
        }
        var hops = 0
        while let link = next, hops < 16 {
            hops += 1
            guard case .element(let wrapper) = link else { return nil }
            switch wrapper {
            case .module(let module):
                guard let name = try? module.descriptor.name(in: machO) else { return nil }
                components.append(name)
                return components.reversed().joined(separator: ".")
            case .type(let parentType):
                guard let name = name(of: parentType, in: machO) else { return nil }
                components.append(name)
                next = try? wrapper.parent(in: machO)
            default:
                return nil   // extension / anonymous / protocol / opaque — can't qualify
            }
        }
        return nil
    }
}
