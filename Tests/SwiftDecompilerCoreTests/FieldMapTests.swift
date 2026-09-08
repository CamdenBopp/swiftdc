import Testing
import Foundation
import SwiftLayout
@testable import SwiftDecompilerCore

/// Build a FieldMap without a binary, so the lookup rules are testable in
/// isolation from metadata parsing.
private func map(
    _ typeName: String,
    size: Int,
    _ fields: [(name: String, offset: Int, bytes: Int, resolution: FieldResolution)]
) -> FieldMap {
    FieldMap(
        typeName: typeName,
        layout: AggregateFieldLayout(
            fields: fields.map {
                FieldLayoutEntry(
                    fieldName: $0.name,
                    offset: $0.offset,
                    typeMangledName: "T",
                    layout: StaticTypeLayout(
                        size: $0.bytes, stride: $0.bytes, alignmentMask: 7,
                        extraInhabitantCount: 0, isBitwiseTakable: true
                    ),
                    resolution: $0.resolution
                )
            },
            size: size, stride: size, alignment: 8, extraInhabitantCount: 0
        )
    )
}

/// A load that covers exactly one field.
@Test func namesWholeFieldAccess() {
    let dog = map("Dog", size: 0x38, [
        ("breed", 0x20, 16, .computed),
        ("goodBoy", 0x30, 1, .computed),
    ])
    #expect(dog.lookup(offset: 0x20, bytes: 16) == .success(.whole(name: "breed", typeMangledName: "T")))
    #expect(dog.lookup(offset: 0x30, bytes: 1) == .success(.whole(name: "goodBoy", typeMangledName: "T")))
}

/// `Swift.String` is 16 bytes and arrives as `ldp x8, x9, [x0, #0x10]`, so one
/// register of the pair is a *partial* read. A size-gated point lookup would
/// reject its own headline example.
@Test func namesPartialAndSpanningAccess() {
    let m = map("Mixed", size: 0x28, [
        ("a", 0x0, 8, .computed),
        ("b", 0x8, 8, .computed),
        ("name", 0x18, 16, .computed),
    ])
    // The high half of the String.
    #expect(m.lookup(offset: 0x20, bytes: 8) == .success(.part(name: "name", typeMangledName: "T", subOffset: 8, bytes: 8)))
    // One byte out of the middle of an Int (`ldrb`).
    #expect(m.lookup(offset: 0x2, bytes: 1) == .success(.part(name: "a", typeMangledName: "T", subOffset: 2, bytes: 1)))
    // A 16-byte read straddling two 8-byte fields.
    #expect(m.lookup(offset: 0x0, bytes: 16) == .success(.spans(names: ["a", "b"])))
}

/// Offsets are trustworthy only as a PREFIX. Swift lays out fields in
/// declaration order, and the first unresolvable one makes every later offset
/// unknown — not merely unnamed. Naming past it would be a fabrication.
@Test func refusesPastTheTrustedPrefix() {
    let widget = map("Widget", size: 0x30, [
        ("origin", 0x0, 16, .computed),
        ("when", 0x10, 8, .unknown(reason: .typeDescriptorNotFound(qualifiedTypeName: "Foundation.Date"))),
        ("n", 0x28, 8, .computed),   // a real field, at a real offset — still refused
    ])
    #expect(widget.trustedOffsetLimit == 0x10)
    #expect(widget.lookup(offset: 0x0, bytes: 16) == .success(.whole(name: "origin", typeMangledName: "T")))

    // `n` IS at 0x28, but the layout could not prove it, so it must not be named.
    guard case .failure(.pastTrustedPrefix(let limit, let reason)) = widget.lookup(offset: 0x28, bytes: 8) else {
        Issue.record("expected a trusted-prefix refusal"); return
    }
    #expect(limit == 0x10)
    #expect(reason.contains("Foundation.Date"))   // the actionable reason, not "past instance size"
}

/// Tail-allocated storage (ManagedBuffer, _ContiguousArrayStorage) puts elements
/// past the instance. Without this bound, such an access lands inside the last
/// field's range and resolves to a real field name of a real type.
@Test func refusesPastInstanceSize() {
    let p = map("Point", size: 18, [
        ("x", 0, 8, .computed),
        ("y", 8, 8, .computed),
        ("tag", 16, 1, .computed),
        ("flag", 17, 1, .computed),
    ])
    #expect(p.lookup(offset: 16, bytes: 1) == .success(.whole(name: "tag", typeMangledName: "T")))
    #expect(p.lookup(offset: 18, bytes: 8) == .failure(.pastInstanceSize(instanceSize: 18)))
    #expect(p.lookup(offset: 0x100, bytes: 8) == .failure(.pastInstanceSize(instanceSize: 18)))
}

/// An offset inside the instance but in no field is padding, not a guess.
@Test func refusesPadding() {
    let padded = map("Padded", size: 24, [
        ("a", 0, 1, .computed),
        ("b", 16, 8, .computed),
    ])
    #expect(padded.lookup(offset: 4, bytes: 4) == .failure(.padding))
}

// MARK: - Simple-name collision guard

/// Field maps are keyed by SIMPLE name, and the resolver falls back to a name's
/// last component — so two distinct types sharing a simple name but with DIFFERENT
/// layouts (a plain-struct `Options` vs an OptionSet `Options` whose offset 0 is
/// `rawValue`) would hand one type's fields to the other. The ambiguous key is
/// dropped so a colliding self-type declines rather than fabricating a wrong field.
@Test func dropsCollidingSimpleNameWithDifferentLayouts() {
    let a = map("Pair", size: 16, [("alpha", 0, 8, .computed), ("beta", 8, 8, .computed)])
    let b = map("Pair", size: 24, [
        ("gamma", 0, 8, .computed), ("delta", 8, 8, .computed), ("epsilon", 16, 8, .computed),
    ])
    let solo = map("Solo", size: 8, [("only", 0, 8, .computed)])
    let maps = FieldMapBuilder.resolvingSimpleNameCollisions([("Pair", a), ("Pair", b), ("Solo", solo)])

    #expect(maps["Pair"] == nil)   // ambiguous → dropped; neither claimant wins the key
    #expect(maps["Solo"] != nil)   // uniquely named → kept
    #expect(maps["Solo"]?.lookup(offset: 0, bytes: 8) == .success(.whole(name: "only", typeMangledName: "T")))
}

/// Two types that share a simple name AND an identical layout are not a
/// fabrication risk — either resolves to the same fields — so the key is kept.
@Test func keepsCollidingSimpleNameWithIdenticalLayout() {
    let a = map("Twin", size: 8, [("x", 0, 8, .computed)])
    let b = map("Twin", size: 8, [("x", 0, 8, .computed)])
    let maps = FieldMapBuilder.resolvingSimpleNameCollisions([("Twin", a), ("Twin", b)])

    #expect(maps["Twin"] != nil)
    #expect(maps["Twin"]?.lookup(offset: 0, bytes: 8) == .success(.whole(name: "x", typeMangledName: "T")))
}

/// A three-way collision (the common `Layout`/`Iterator`/`Storage` case): the
/// moment any two distinct layouts claim the name it is dropped, even if a third
/// repeats one of them.
@Test func dropsMultiwaySimpleNameCollision() {
    let one = map("Layout", size: 8, [("a", 0, 8, .computed)])
    let two = map("Layout", size: 16, [("b", 0, 8, .computed), ("c", 8, 8, .computed)])
    let three = map("Layout", size: 8, [("a", 0, 8, .computed)])   // same as `one`
    let maps = FieldMapBuilder.resolvingSimpleNameCollisions([("Layout", one), ("Layout", two), ("Layout", three)])

    #expect(maps["Layout"] == nil)
}
