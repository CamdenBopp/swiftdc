import Testing
@testable import SwiftDecompilerCore

/// The demangled result type that decides which register (if any) a Swift
/// function returns in. A witness name trails its signature with the
/// conformance clause; the type must stop before it, or `Swift.String` reads as
/// some other type and a stale x0 is printed as the witness's return.
@Test func returnTypeStopsBeforeAWitnessConformanceClause() {
    let witness = "protocol witness for sample.Shape.describe() -> Swift.String in conformance sample.Circle : sample.Shape in sample"
    #expect(Disassembler.swiftReturnTypeName(ofDemangled: witness) == "Swift.String")
    let getter = "protocol witness for Swift.RawRepresentable.rawValue.getter : A.RawValue in conformance M.Priority : Swift.RawRepresentable in M"
    #expect(Disassembler.swiftReturnTypeName(ofDemangled: getter) == "A.RawValue")
    #expect(Disassembler.swiftReturnTypeName(ofDemangled: "M.f(Swift.Int) -> Swift.Bool") == "Swift.Bool")
    #expect(Disassembler.swiftReturnTypeName(ofDemangled: "M.g() -> ()") == nil)
}

/// `callResultBank` declines a result type with a generic parameter in it
/// (`A`, `B1`, a specialization's substitution). The hand scan that finds one
/// must answer exactly as the regex it replaced, on printed types and on
/// every short string over an alphabet of the characters that decide it
/// (word and non-word ASCII, `.`, a newline, a precomposed letter, and an
/// uppercase letter with a combining mark, one `Character` the regex does
/// not read as `[A-Z]`).
@Test func genericParameterTokenScanMatchesTheRegex() {
    let regex = #/(^|[^A-Za-z0-9_.])[A-Z][0-9]*($|[^A-Za-z0-9_])/#
    let printed = [
        "A", "A1", "B12", "Swift.Array<A>", "[A1]", "(A, B)", "A.Element", "Swift.Int", "M.Abc",
        "Swift.Optional<Swift.Int>", "M.T", "M.T1", "x.A", "_A", "aA", "A_", "AB", "A1b", "(A1?)",
        "Swift.Dictionary<A, B1>.Index", "M.Outer<A>.Inner", "", " A ", "A\n", "\nA",
    ]
    for type in printed {
        #expect(Disassembler.containsGenericParameterToken(type) == type.contains(regex), "\(type)")
    }
    let alphabet: [String] = ["A", "Z", "a", "0", "9", "_", ".", " ", "<", ">", "\n", "é", "A\u{301}"]
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    for _ in 0 ..< 3000 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let length = Int(state >> 61)
        var text = ""
        for position in 0 ..< length {
            text += alphabet[Int((state >> UInt64(4 * position + 4)) % UInt64(alphabet.count))]
        }
        #expect(Disassembler.containsGenericParameterToken(text) == text.contains(regex), "\(text.debugDescription)")
    }
}
