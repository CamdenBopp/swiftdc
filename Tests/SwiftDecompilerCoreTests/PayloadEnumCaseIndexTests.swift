import Testing
@testable import SwiftDecompilerCore

/// The soundness sentinel for payload-enum case naming. `namesProvablePayloadEnum
/// CaseIfPresent` (ReconstructionTests) proves the *name-when-provable* half on a
/// real binary; these prove the *decline-when-not* half against the unprovable
/// shapes the fixtures do not contain. The rule is: name only a unique exact
/// byte-pattern match of an empty case, on an enum small enough to be returned in
/// registers; anything else leaves the raw value.
private func index(
    name: String,
    size: Int,
    cases: [PayloadEnumCaseIndex.ExactEmptyCase],
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
private let eof = PayloadEnumCaseIndex.ExactEmptyCase(
    name: "eof", fixedBytes: [0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, 8: 2], masks: [:]
)

@Test func namesAnExactUniqueMatch() {
    let i = index(name: "Token", size: 9, cases: [eof])
    #expect(i.caseName(ofEnum: "Token", x0: 0, x1: 2) == "eof")
    // Module-qualified names resolve through the simple-name fallback too.
    #expect(i.caseName(ofEnum: "Reconstruction.Token", x0: 0, x1: 2) == "eof")
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
    let farByte = PayloadEnumCaseIndex.ExactEmptyCase(name: "x", fixedBytes: [16: 1], masks: [:])
    let i = index(name: "E", size: 16, cases: [farByte])
    #expect(i.caseName(ofEnum: "E", x0: 0, x1: 0) == nil)
}

@Test func declinesWhenTwoCasesBothMatch() {
    // Two empty cases whose fixed bytes both match the observed value: no unique
    // answer, so decline rather than pick.
    let a = PayloadEnumCaseIndex.ExactEmptyCase(name: "a", fixedBytes: [0: 0], masks: [:])
    let b = PayloadEnumCaseIndex.ExactEmptyCase(name: "b", fixedBytes: [1: 0], masks: [:])
    let i = index(name: "E", size: 8, cases: [a, b])
    #expect(i.caseName(ofEnum: "E", x0: 0, x1: nil) == nil)   // both match x0 == 0
    // But a value that matches exactly one still names it.
    let j = index(name: "F", size: 8, cases: [
        PayloadEnumCaseIndex.ExactEmptyCase(name: "a", fixedBytes: [0: 1], masks: [:]),
        PayloadEnumCaseIndex.ExactEmptyCase(name: "b", fixedBytes: [0: 2], masks: [:]),
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
