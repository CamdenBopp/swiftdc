import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A struct argument's integer scalars share a register only when they are
/// neighbours in offset order within one 8-byte chunk. A float between them
/// keeps them apart: `{ Int16, Float16, Int16 }` is i16, half, i16, two
/// general registers and one vector register (`swiftc -emit-ir`, Swift
/// 6.4.2). Counted as one general register, every formal after the struct
/// was placed one register early: `afterSplit(_ s: Split, _ k: Int, _ m:
/// Int) { k &- m }` has `k` in x1, which holds `s.b`. No image reaches the
/// count today, because the layout reader has no size for Float16 and
/// declines the struct. fpbarrierpieces.swift states each function's true
/// behaviour.
private func structured(_ path: String, _ name: String) async throws -> String {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("FPBarrierPieces.\(name)(") })
    return function.renderStructured()
}

private func banks(_ type: String, _ maps: [String: FieldMap]) -> [Int]? {
    SwiftLowering.aggregateRegisters(of: type, fieldMaps: maps).map { [$0.integers, $0.floats] }
}

private func directBanks(_ type: String, _ maps: [String: FieldMap]) -> [Int]? {
    SwiftLowering.directAggregateRegisters(of: type, fieldMaps: maps).map { [$0.integers, $0.floats] }
}

/// A complete, non-resilient layout of `M.<name>` from offsets, sizes and
/// printed field types.
private func layout(_ name: String, size: Int, _ fields: [(offset: Int, bytes: Int, type: String)]) -> FieldMap {
    let named = fields.enumerated().map { (name: "f\($0.offset)", field: $0.element) }
    return FieldMap(typeName: "M.\(name)", instanceSize: size, fields: named.map {
        (offset: $0.field.offset, bytes: $0.field.bytes, name: $0.name, typeEncoding: $0.field.type)
    }).withFieldTypeNames(Dictionary(uniqueKeysWithValues: named.map { ($0.name, $0.field.type) }))
}

private func banks(_ fields: [(offset: Int, bytes: Int, type: String)], size: Int) -> [Int]? {
    banks("M.S", ["M.S": layout("S", size: size, fields)])
}

@Test func aFloatBetweenTwoIntegersOfOneChunkKeepsThemInSeparateRegisters() {
    // i16, half, i16.
    #expect(banks([(0, 2, "Swift.Int16"), (2, 2, "Swift.Float16"), (4, 2, "Swift.Int16")], size: 6) == [2, 1])
    // The integers after the float are neighbours: i8, half, i16.
    #expect(banks([(0, 1, "Swift.Int8"), (2, 2, "Swift.Float16"), (4, 1, "Swift.Int8"), (5, 1, "Swift.Int8")],
                  size: 6) == [2, 1])
    #expect(banks([(0, 2, "Swift.Int16"), (2, 2, "Swift.Float16"), (4, 2, "Swift.Int16"), (6, 2, "Swift.Int16")],
                  size: 8) == [2, 1])
    // A nested struct is flattened first: its float still separates its
    // integer from the outer one.
    let maps = [
        "M.Pair": layout("Pair", size: 4, [(0, 2, "Swift.Int16"), (2, 2, "Swift.Float16")]),
        "M.Outer": layout("Outer", size: 6, [(0, 4, "M.Pair"), (4, 2, "Swift.Int16")]),
    ]
    #expect(banks("M.Outer", maps) == [2, 1])
}

/// The controls: integers that are neighbours still merge, wherever the
/// float is.
@Test func adjacentIntegersOfOneChunkStillShareARegister() {
    #expect(banks([(0, 2, "Swift.Int16"), (2, 2, "Swift.Int16"), (4, 2, "Swift.Float16")], size: 6) == [1, 1])
    #expect(banks([(0, 2, "Swift.Float16"), (2, 2, "Swift.Int16"), (4, 2, "Swift.Int16")], size: 6) == [1, 1])
    // The measured table (docs/ABI-INVARIANTS.md, structlowering.swift).
    #expect(banks([(0, 4, "Swift.Int32"), (4, 4, "Swift.Int32")], size: 8) == [1, 0])
    #expect(banks([(0, 4, "Swift.Float"), (4, 4, "Swift.Int32")], size: 8) == [1, 1])
    // Padding is no piece: Int16 and Int32 merge across it, Int8 is the
    // next chunk's.
    #expect(banks([(0, 2, "Swift.Int16"), (4, 4, "Swift.Int32"), (8, 1, "Swift.Int8")], size: 12) == [2, 0])
    #expect(banks([(0, 4, "Swift.Int32"), (8, 8, "Swift.Int64"), (16, 4, "Swift.Int32")], size: 24) == [3, 0])
    // A String is two words and an `Int?` a word and its tag byte.
    #expect(banks([(0, 16, "Swift.String"), (16, 8, "Swift.Int")], size: 24) == [3, 0])
    #expect(banks([(0, 9, "Swift.Optional<Swift.Int>"), (16, 8, "Swift.Int")], size: 24) == [3, 0])
}

/// More than four scalars go by address, counted after merging: the split
/// integers make five where the adjacent ones make four.
@Test func theFloatBarrierCountsTowardTheFourRegisterLimit() {
    let doubles: [(offset: Int, bytes: Int, type: String)] = [(8, 8, "Swift.Double"), (16, 8, "Swift.Double")]
    let split: [(offset: Int, bytes: Int, type: String)] =
        [(0, 2, "Swift.Int16"), (2, 2, "Swift.Float16"), (4, 2, "Swift.Int16")] + doubles
    let joined: [(offset: Int, bytes: Int, type: String)] =
        [(0, 2, "Swift.Int16"), (2, 2, "Swift.Int16"), (4, 2, "Swift.Float16")] + doubles
    let maps = ["M.SplitWide": layout("SplitWide", size: 24, split), "M.JoinedWide": layout("JoinedWide", size: 24, joined)]
    // Its address, one general register, and no vector register.
    #expect(banks("M.SplitWide", maps) == [1, 0])
    #expect(directBanks("M.SplitWide", maps) == nil)
    #expect(banks("M.JoinedWide", maps) == [1, 3])
    #expect(directBanks("M.JoinedWide", maps) == [1, 3])
}

/// A layout that does not prove every piece counts nothing.
@Test func anUnprovenPieceLayoutHasNoRegisterCount() {
    let split: [(offset: Int, bytes: Int, type: String)] =
        [(0, 2, "Swift.Int16"), (2, 2, "Swift.Float16"), (4, 2, "Swift.Int16")]
    // Two scalars at the same bytes.
    #expect(banks([(0, 4, "Swift.Int32"), (2, 2, "Swift.Float16")], size: 4) == nil)
    #expect(banks([(0, 2, "Swift.Int16"), (0, 2, "Swift.Int16")], size: 2) == nil)
    // An integer piece lies within one chunk: a String or an `Int?` off a
    // word boundary is not a layout the compiler produces.
    #expect(banks([(4, 16, "Swift.String")], size: 20) == nil)
    #expect(banks([(4, 9, "Swift.Optional<Swift.Int>")], size: 16) == nil)
    // A vector's lowering is not modelled, so it is no barrier either.
    #expect(banks([(0, 2, "Swift.Int16"), (8, 8, "Swift.SIMD2<Swift.Float>"), (16, 2, "Swift.Int16")], size: 24) == nil)
    // A possibly resilient struct is passed by address.
    var resilient = layout("S", size: 6, split)
    resilient.mayBeResilient = true
    #expect(banks("M.S", ["M.S": resilient]) == nil)
    // A field whose type has no printed name.
    let unnamed = FieldMap(typeName: "M.S", instanceSize: 6, fields: split.map {
        (offset: $0.offset, bytes: $0.bytes, name: "f\($0.offset)", typeEncoding: $0.type)
    })
    #expect(banks("M.S", ["M.S": unnamed]) == nil)
}

/// The image's own layouts stop at the Float16 field: the layout reader has
/// no size for it, so the struct has no register count and nothing after
/// it is placed. The count above is what a reader that learns Float16 must
/// already have.
@Test func aFloat16FieldLeavesTheImagesLayoutUnprovenIfPresent() throws {
    for path in ["Fixtures/Sample/libFPBarrierPieces.dylib", "Fixtures/Sample/libFPBarrierPieces.onone.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let maps = try FieldMapBuilder.build(in: try BinaryLoader.load(path: path))
        for type in ["Split", "Joined", "SplitWide", "JoinedWide"] {
            #expect(banks("FPBarrierPieces.\(type)", maps) == nil, "\(path): \(type)")
            #expect(directBanks("FPBarrierPieces.\(type)", maps) == nil, "\(path): \(type)")
        }
    }
}

/// With no count for the struct, no formal after it is named: `afterSplit`
/// is `k &- m` with k in x2 and m in x3, and a count of one general
/// register for the struct would print `arg1 - arg2` from x1 and x2.
@Test(arguments: ["Fixtures/Sample/libFPBarrierPieces.dylib", "Fixtures/Sample/libFPBarrierPieces.onone.dylib"])
func formalsAfterAStructWithAnUnprovenLayoutAreNotNamedIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    for name in ["afterSplit", "afterJoined", "secondOfSplit", "afterSplitWide", "afterJoinedWide"] {
        let text = try await structured(path, name)
        #expect(text.contains("return ?"), "\(name):\n\(text)")
        #expect(!text.contains("arg"), "\(name):\n\(text)")
    }
}
