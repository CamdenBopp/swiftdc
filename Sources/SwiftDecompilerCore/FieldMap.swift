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

        var maps: [String: FieldMap] = [:]
        for type in (try? machO.swift.types) ?? [] {
            guard let descriptor = Self.contextDescriptor(of: type),
                  let name = Self.name(of: type, in: machO)
            else { continue }
            // Per-type isolation: one type that fails to lay out must not take
            // the whole image with it.
            guard let layout = try? calculator.fieldLayout(of: descriptor), !layout.fields.isEmpty
            else { continue }
            maps[name] = FieldMap(typeName: name, layout: layout)
        }
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
}
