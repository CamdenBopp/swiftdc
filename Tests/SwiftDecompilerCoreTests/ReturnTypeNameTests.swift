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
