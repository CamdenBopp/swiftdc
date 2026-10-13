import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Soundness regression. The structurer negates a condition when the branch it
/// renders is the fall-through. It used to do that by replacing the first
/// operator text it found *everywhere*, which:
///
/// - negated one conjunct of a compound test: the -O guard
///   `(0 <= x) && (x < 101)` inverted to `(0 > x) && (x < 101)`, never true
///   where the `throw .tooBig` it guards runs (`typedPick`);
/// - rewrote operators inside demangled names: `where A.Element == Swift.String`
///   became `!=` in a SwiftData condition;
/// - stripped `!(` from `!(a) && (b)`, leaving `a) && (b`.
@Test func invertsASingleComparisonInPlace() {
    #expect(ControlFlowStructure.inverted("arg0 < 0") == "arg0 >= 0")
    #expect(ControlFlowStructure.inverted("(x & 1) == 0") == "(x & 1) != 0")
    #expect(ControlFlowStructure.inverted("x <\u{1D41} 101") == "x >=\u{1D41} 101")
    #expect(ControlFlowStructure.inverted("x <=\u{1D41} y") == "x >\u{1D41} y")
    // Only the top-level operator: a nested comparison is an operand.
    #expect(ControlFlowStructure.inverted("((a > 0) ? b : c) < d") == "((a > 0) ? b : c) >= d")
    // A shift is not a comparison and not a generic bracket.
    #expect(ControlFlowStructure.inverted("(x >> 2) == 1") == "(x >> 2) != 1")
    #expect(ControlFlowStructure.inverted("x >> 2 == 1") == "x >> 2 != 1")
}

@Test func wrapsACompoundCondition() {
    #expect(ControlFlowStructure.inverted("(0 <= arg0) && (arg0 < 101)") == "!((0 <= arg0) && (arg0 < 101))")
    #expect(ControlFlowStructure.inverted("(a == b) || (c != d)") == "!((a == b) || (c != d))")
    #expect(ControlFlowStructure.inverted("!(a) && (b)") == "!(!(a) && (b))")
    // Unparenthesized: rewriting one operator would negate one conjunct.
    #expect(ControlFlowStructure.inverted("a == b && c != d") == "!(a == b && c != d)")
    #expect(ControlFlowStructure.inverted("x < 1 || flag") == "!(x < 1 || flag)")
}

@Test func leavesOperatorsInsideNamesAlone() {
    let call = "M.Collection< where A.Element == Swift.String>.isEmpty.getter : Swift.Bool()"
    #expect(ControlFlowStructure.inverted(call) == "!(\(call))")
    #expect(ControlFlowStructure.inverted("f(a == b)") == "!f(a == b)")
    #expect(ControlFlowStructure.inverted("[x isEqual:y]") == "![x isEqual:y]")
    #expect(ControlFlowStructure.inverted("Swift.Array<Swift.Array<Swift.Int>>.isEmpty()") == "!Swift.Array<Swift.Array<Swift.Int>>.isEmpty()")
}

@Test func keepsTheSimpleNegations() {
    #expect(ControlFlowStructure.inverted("!flag") == "flag")
    #expect(ControlFlowStructure.inverted("!(a & b)") == "a & b")
    #expect(ControlFlowStructure.inverted("bit 0 of w8 clear") == "bit 0 of w8 set")
    #expect(ControlFlowStructure.inverted("flag") == "!flag")
}

@Test func rangeGuardNegatesWholeIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "Reconstruction.typedPick(")
    }
    let body = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(!body.isEmpty)
    // `cmp x0, #101; b.lo <return>`: the fall-through (`throw .tooBig`) runs
    // when NOT (0 <= x < 101).
    #expect(!body.contains("(0 > arg0) && (arg0 < 101)"), "\(body)")
    #expect(body.contains("!((0 <= arg0) && (arg0 < 101))"), "\(body)")
}

/// Soundness regression: a literal in a bit-level expression over a float
/// argument is a shift count or a mask, not an IEEE double. `Int(d)` inlines a
/// range check on `d`'s bit pattern; the old policy rendered every literal in
/// a float-valued expression as a double (`>> 2.57e-322` for `>> 52`).
@Test func bitLevelLiteralsOverAFloatStayIntegersIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "Reconstruction.truncated(")
    }
    let body = functions.map { $0.renderStructured() + "\n" + $0.renderPseudo() }.joined(separator: "\n")
    #expect(body.contains("(arg0 >>ᵁ 52)"), "\(body)")
    #expect(body.contains("& 2047)"), "\(body)")
    #expect(!body.contains("e-32"), "\(body)")
}
