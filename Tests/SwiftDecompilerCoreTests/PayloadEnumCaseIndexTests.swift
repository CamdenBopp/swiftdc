import Testing
@testable import SwiftDecompilerCore

/// The soundness sentinel for payload-enum case naming. `namesProvablePayloadEnum
/// CaseIfPresent` (ReconstructionTests) proves the *name-when-provable* half on a
/// real binary; these prove the *decline-when-not* half against the unprovable
/// shapes the fixtures do not contain. The rule is: name only a unique exact
/// byte-pattern match of an empty case, on an enum small enough to be returned in
/// registers; anything else leaves the raw value.
/// An empty case with a fixed byte pattern (the shape every direct-return test
/// below exercises).
private func emptyCase(_ name: String, fixedBytes: [Int: UInt8], masks: [Int: UInt8] = [:]) -> PayloadEnumCaseIndex.ResolvedCase {
    PayloadEnumCaseIndex.ResolvedCase(name: name, isPayloadCase: false, fixedBytes: fixedBytes, masks: masks, payloadWords: nil)
}

/// A payload case whose tag is the fixed bytes and whose payload is `words`
/// word scalars (nil: not a word-scalar tuple).
private func payloadCase(_ name: String, fixedBytes: [Int: UInt8], masks: [Int: UInt8] = [:], words: Int?) -> PayloadEnumCaseIndex.ResolvedCase {
    PayloadEnumCaseIndex.ResolvedCase(name: name, isPayloadCase: true, fixedBytes: fixedBytes, masks: masks, payloadWords: words)
}

private func index(
    name: String,
    size: Int,
    cases: [PayloadEnumCaseIndex.ResolvedCase],
    qualified: String? = nil,
    ambiguous: Bool = false
) -> PayloadEnumCaseIndex {
    let entry = PayloadEnumCaseIndex.Entry(size: size, cases: cases)
    var byQualified: [String: PayloadEnumCaseIndex.Entry] = [:]
    if let qualified { byQualified[qualified] = entry }
    return PayloadEnumCaseIndex(
        byName: [name: ambiguous ? nil : entry],
        byQualifiedName: byQualified
    )
}

/// `Token { eof; number(Int); ident(Int) }`: 8-byte payload + 1 tag byte, `.eof`
/// = payload 0, tag byte 2.
private let eof = emptyCase("eof", fixedBytes: [0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, 8: 2])

@Test func namesAnExactUniqueMatch() {
    let i = index(name: "Token", size: 9, cases: [eof], qualified: "Reconstruction.Token")
    #expect(i.caseName(ofEnum: "Token", x0: 0, x1: 2) == "eof")
    // A qualified name resolves only through its own descriptor identity.
    #expect(i.caseName(ofEnum: "Reconstruction.Token", x0: 0, x1: 2) == "eof")
}

/// A foreign type sharing the simple name is not this image's enum: its case
/// encoding and names are unknown here. (From the pre-merge stash 983aa25.)
@Test func declinesForeignQualifiedPayloadEnumWithSameSimpleName() {
    let i = index(name: "Token", size: 9, cases: [eof], qualified: "Reconstruction.Token")
    #expect(i.caseName(ofEnum: "Other.Token", x0: 0, x1: 2) == nil)
}

@Test func declinesWhenAnyFixedByteMismatches() {
    let i = index(name: "Token", size: 9, cases: [eof])
    #expect(i.caseName(ofEnum: "Token", x0: 0, x1: 3) == nil)   // wrong tag byte
    #expect(i.caseName(ofEnum: "Token", x0: 5, x1: 2) == nil)   // non-zero payload
    #expect(i.caseName(ofEnum: "Token", x0: 0, x1: nil) == nil) // tag byte unsourced
}

@Test func declinesAnOversizeEnumReturnedIndirectly() {
    // > 16 bytes is returned via x8, so x0/x1 do not hold the value — decline
    // regardless of what the registers happen to contain.
    let i = index(name: "Big", size: 24, cases: [eof])
    #expect(i.caseName(ofEnum: "Big", x0: 0, x1: 2) == nil)
}

@Test func declinesWhenAFixedByteHasNoSourcingRegister() {
    // A fixed byte beyond the two registers cannot be verified → decline.
    let farByte = emptyCase("x", fixedBytes: [16: 1])
    let i = index(name: "E", size: 16, cases: [farByte])
    #expect(i.caseName(ofEnum: "E", x0: 0, x1: 0) == nil)
}

@Test func declinesWhenTwoCasesBothMatch() {
    // Two empty cases whose fixed bytes both match the observed value: no unique
    // answer, so decline rather than pick.
    let a = emptyCase("a", fixedBytes: [0: 0])
    let b = emptyCase("b", fixedBytes: [1: 0])
    let i = index(name: "E", size: 8, cases: [a, b])
    #expect(i.caseName(ofEnum: "E", x0: 0, x1: nil) == nil)   // both match x0 == 0
    // But a value that matches exactly one still names it.
    let j = index(name: "F", size: 8, cases: [
        emptyCase("a", fixedBytes: [0: 1]),
        emptyCase("b", fixedBytes: [0: 2]),
    ])
    #expect(j.caseName(ofEnum: "F", x0: 2, x1: nil) == "b")
}

@Test func declinesAnAmbiguousSimpleName() {
    let i = index(name: "Token", size: 9, cases: [eof], ambiguous: true)
    #expect(i.caseName(ofEnum: "Token", x0: 0, x1: 2) == nil)
}

@Test func resolvesAQualifiedNameEvenWhenSimpleIsAmbiguous() {
    let i = index(name: "Token", size: 9, cases: [eof], qualified: "Reconstruction.Token", ambiguous: true)
    #expect(i.caseName(ofEnum: "Reconstruction.Token", x0: 0, x1: 2) == "eof")   // qualified wins
    #expect(i.caseName(ofEnum: "Token", x0: 0, x1: 2) == nil)                    // simple still ambiguous
}

@Test func declinesAnUnknownEnum() {
    let i = index(name: "Token", size: 9, cases: [eof])
    #expect(i.caseName(ofEnum: "Other", x0: 0, x1: 2) == nil)
}

// MARK: - Indirect (x8) returns

/// `Shape4 { empty; box(Int, Int, Int, Int); ball(Int); tagged(String, Int, Int) }`:
/// a 32-byte payload area and a tag byte at 32. `.empty` is payload 0, tag 2;
/// `.box` is tag 0 over four payload words; `.ball` is tag 1 over one.
private let shape4 = index(name: "Shape4", size: 33, cases: [
    emptyCase("empty", fixedBytes: Dictionary(uniqueKeysWithValues: (0..<32).map { ($0, UInt8(0)) }).merging([32: 2]) { a, _ in a }),
    payloadCase("box", fixedBytes: [32: 0], words: 4),
    payloadCase("ball", fixedBytes: [32: 1], words: 1),
    payloadCase("tagged", fixedBytes: [32: 3], words: nil),
])

private func stores(_ entries: [(Int, Int, UInt64?)]) -> [Int: (bytes: Int, immediate: UInt64?)] {
    Dictionary(uniqueKeysWithValues: entries.map { ($0.0, (bytes: $0.1, immediate: $0.2)) })
}

@Test func namesIndirectPayloadCaseFromTagAndDeclaredArity() {
    let box = shape4.indirectCase(ofEnum: "Shape4", stores: stores([
        (0, 8, nil), (8, 8, nil), (16, 8, nil), (24, 8, nil), (32, 1, 0),
    ]))
    #expect(box?.name == "box")
    #expect(box?.payloadWordOffsets == [0, 8, 16, 24])
    let empty = shape4.indirectCase(ofEnum: "Shape4", stores: stores([
        (0, 8, 0), (8, 8, 0), (16, 8, 0), (24, 8, 0), (32, 1, 2),
    ]))
    #expect(empty?.name == "empty")
    #expect(empty?.payloadWordOffsets == [])
}

@Test func declinesIndirectCaseWhoseTagIsNotAStoredImmediate() {
    // The tag byte stored from a register (nil immediate) cannot be matched.
    #expect(shape4.indirectCase(ofEnum: "Shape4", stores: stores([
        (0, 8, nil), (8, 8, nil), (16, 8, nil), (24, 8, nil), (32, 1, nil),
    ])) == nil)
    // No tag store at all.
    #expect(shape4.indirectCase(ofEnum: "Shape4", stores: stores([(0, 8, nil)])) == nil)
}

@Test func declinesIndirectPayloadCaseMissingAWordOrWithoutWordArity() {
    // `.box` with only three of its four payload words stored.
    #expect(shape4.indirectCase(ofEnum: "Shape4", stores: stores([
        (0, 8, nil), (8, 8, nil), (16, 8, nil), (32, 1, 0),
    ])) == nil)
    // `.tagged` has a String payload: the arity is not provable from stores.
    #expect(shape4.indirectCase(ofEnum: "Shape4", stores: stores([
        (0, 8, nil), (8, 8, nil), (16, 8, nil), (24, 8, nil), (32, 1, 3),
    ])) == nil)
}

@Test func declinesIndirectCaseOnADirectlyReturnedEnum() {
    // 16 bytes or fewer travels in x0/x1, never through x8.
    let small = index(name: "Token", size: 9, cases: [eof])
    #expect(small.indirectCase(ofEnum: "Token", stores: stores([(0, 8, 0), (8, 1, 2)])) == nil)
}

@Test func declinesIndirectEmptyCaseWithAPayloadByteUnstored() {
    // `.empty` fixes every payload byte to zero; a word left unstored is unverified.
    #expect(shape4.indirectCase(ofEnum: "Shape4", stores: stores([
        (0, 8, 0), (8, 8, 0), (16, 8, 0), (32, 1, 2),
    ])) == nil)
}

@Test func wordScalarTupleArityCountsOnlyWordScalars() {
    // The field records' own spellings (printed from `libIndirect.dylib`):
    // `box(Int, Int, Int, Int)` is `Si_S3it`, `tagged(String, Int, Int)` is `SS_S2it`.
    #expect(PayloadEnumCaseIndex.wordScalarTupleArity(mangled: "Si") == 1)
    #expect(PayloadEnumCaseIndex.wordScalarTupleArity(mangled: "Si_S3it") == 4)
    #expect(PayloadEnumCaseIndex.wordScalarTupleArity(mangled: "Si_Sdt") == 2)       // (Int, Double)
    #expect(PayloadEnumCaseIndex.wordScalarTupleArity(mangled: "SS_S2it") == nil)    // a String payload
    #expect(PayloadEnumCaseIndex.wordScalarTupleArity(mangled: "Sb") == nil)         // Bool
    #expect(PayloadEnumCaseIndex.wordScalarTupleArity(mangled: "SiSi") == nil)       // not a tuple
    #expect(PayloadEnumCaseIndex.wordScalarTupleArity(mangled: "8Indirect5Wide5V") == nil)
}
