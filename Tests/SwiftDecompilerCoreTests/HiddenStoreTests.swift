import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A compiler-made helper that writes a value is a statement. The outlined
/// copies of an address-only value and the existential assign helper were
/// hidden with the reference-counting helpers, so `ao = a` in a setter and
/// `a = b` on an `inout any Shape` rendered `// no non-runtime calls (leaf
/// / pure computation)` (`hiddenstore.swift`, -Onone and -O).
@Test func aStoreThroughACompilerHelperIsShownIfPresent() async throws {
    for level in ["Onone", "O"] {
        let path = "Fixtures/Sample/libHiddenStore.\(level).dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        func structured(_ name: String) throws -> String {
            try #require(functions.first { $0.displayName.hasPrefix("HS.\(name)(") }, "\(level) \(name)")
                .renderStructured()
        }
        // Source first, destination second: the field is the destination.
        let setter = try structured("H.setAO")
        #expect(setter.contains("outlined assign with copy of HS.AO(?, &self.ao)"), "\(level): \(setter)")
        let copy = try structured("copyAO")
        #expect(copy.contains("outlined init with copy of HS.AO(?, &result)"), "\(level): \(copy)")
        let assign = try structured("assignAO")
        #expect(assign.contains("with copy of HS.AO("), "\(level): \(assign)")
        // -Onone calls the existential assign helper (destination, source);
        // -O destroys the old value and copies the new one in.
        let shape = try structured("assignShape")
        #expect(shape.contains(level == "Onone" ? "__swift_assign_boxed_opaque_existential_1(arg0, arg1)"
                                                : "outlined init with copy of HS.Shape(arg1, arg0)"),
                "\(level): \(shape)")
        for text in [setter, copy, assign, shape] { #expect(!text.contains("no non-runtime calls"), "\(level): \(text)") }
    }
}

/// Each kind of store helper is kept, merged or not; the helpers that only
/// count references or project a box are still scaffolding.
@Test func onlyHelpersThatWriteAValueAreKeptAsStatements() {
    for callee in ["outlined init with copy of M.T", "outlined init with take of M.T",
                   "outlined assign with copy of M.T", "outlined assign with take of M.T",
                   "outlined enum tag store of M.E", "merged outlined assign with take of M.T",
                   "__swift_assign_boxed_opaque_existential_1", "__swift_assign_boxed_opaque_existential_0"] {
        #expect(DisassembledFunction.isStoreHelper(callee), "\(callee)")
        #expect(!DisassembledFunction.isGenericPlumbingCallee(callee), "\(callee)")
    }
    for callee in ["outlined copy of M.E", "outlined consume of M.E", "outlined destroy of M.T",
                   "outlined retain of M.T", "outlined release of M.T", "outlined enum get tag of M.E",
                   "__swift_project_boxed_opaque_existential_1", "__swift_destroy_boxed_opaque_existential_1",
                   "type metadata accessor for M.T"] {
        #expect(!DisassembledFunction.isStoreHelper(callee), "\(callee)")
        #expect(DisassembledFunction.isGenericPlumbingCallee(callee), "\(callee)")
    }
}

/// A copy of an interpolated operand, made between two appends at -Onone,
/// neither ends the interpolation run nor disappears into it: the string
/// keeps its head and the copy is shown ahead of it. Ended at the copy,
/// `"Circle(\(name)) r=\(radius)"` read `"\(local_70)) r=\(local_78)"`
/// (`sample.debug`, `Circle.describe()`).
@Test func anOperandCopyInsideAnInterpolationStaysAStatementIfPresent() async throws {
    let path = "Fixtures/Sample/sample.debug"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "sample.Circle.describe()")
    }
    let text = try #require(functions.first { $0.displayName == "sample.Circle.describe() -> Swift.String" })
        .renderStructured()
    #expect(text.contains("outlined init with copy of Swift.String(local_30, local_60)\n    return \"Circle(\\("),
            Comment(rawValue: text))
}
