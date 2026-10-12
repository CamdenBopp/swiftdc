import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A merged (`Tm`) function's symbol names one of the functions LLVM folded
/// into it. A call from any other one must not claim that type.
@Test func aMergedCalleeDoesNotNameItsRepresentativeType() {
    let cases: [(String, String)] = [
        ("merged storeEnumTagSinglePayload value witness for Reconstruction.IntQuad",
         "merged storeEnumTagSinglePayload value witness for …"),
        ("merged Reconstruction.Direction.hashValue.getter : Swift.Int",
         "merged ….hashValue.getter : Swift.Int"),
        ("merged protocol witness for Swift.Hashable.hashValue.getter : Swift.Int in conformance Reconstruction.Direction : Swift.Hashable in Reconstruction",
         "merged protocol witness for Swift.Hashable.hashValue.getter : Swift.Int in conformance … : Swift.Hashable in Reconstruction"),
        ("merged Reconstruction.Box.combine(Swift.Int) -> Swift.Int", "merged ….combine(Swift.Int) -> Swift.Int"),
        ("Reconstruction.Direction.hashValue.getter : Swift.Int", "Reconstruction.Direction.hashValue.getter : Swift.Int"),
    ]
    for (symbol, expected) in cases {
        #expect(DisassembledFunction.mergedCallName(symbol) == expected)
    }
    #expect(DisassembledFunction.strippedCallee("merged Reconstruction.Box.combine(Swift.Int) -> Swift.Int")
        == "merged ….combine")
}

/// `storeEnumTagSinglePayload value witness for Reconstruction.OuterX.Wide`
/// tail-calls the body LLVM merged with IntQuad's, and rendered as a call to
/// IntQuad's witness. The merged function's own header keeps its symbol.
@Test func aCallIntoAMergedFunctionNamesNoTypeIfPresent() async throws {
    let fixture = "Fixtures/Sample/libReconstruction.opt.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "storeEnumTagSinglePayload")
    }
    let wide = try #require(functions.first {
        $0.displayName == "storeEnumTagSinglePayload value witness for Reconstruction.OuterX.Wide"
    })
    let text = wide.renderStructured()
    #expect(text.contains("merged storeEnumTagSinglePayload value witness for …("), Comment(rawValue: text))
    #expect(!text.contains("IntQuad"), Comment(rawValue: text))
    let merged = try #require(functions.first { $0.displayName.hasPrefix("merged ") && $0.displayName.hasSuffix("IntQuad") })
    #expect(merged.renderStructured().hasPrefix("merged storeEnumTagSinglePayload value witness for Reconstruction.IntQuad {"))
}
