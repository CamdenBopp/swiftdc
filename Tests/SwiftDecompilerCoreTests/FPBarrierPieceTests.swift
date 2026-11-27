import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A struct argument's integer scalars share a register only when they are
/// neighbours in offset order within one 8-byte chunk. A float between them
/// keeps them apart: `{ Int16, Float16, Int16 }` is i16, half, i16, two
/// general registers and one vector register (`swiftc -emit-ir`, Swift
/// 6.4.2). Counted as one general register, every formal after the struct
/// was placed one register early: `afterSplit(_ s: Split, _ k: Int, _ m:
/// Int) { k &- m }` has `k` in x1, which holds `s.b`. The images reach the
/// count through the layout reader, which lays a Float16 field out as two
/// bytes at an even offset. fpbarrierpieces.swift states each function's
/// true behaviour.
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

private let images = ["Fixtures/Sample/libFPBarrierPieces.dylib", "Fixtures/Sample/libFPBarrierPieces.onone.dylib"]

/// Float16 is a two-byte scalar aligned to two, so every field after one
/// has a proven offset: `{ Int16, Float16, Int16 }` is 6 bytes, and the
/// Doubles of the wide structs start at 8 and 16 for 24 in all.
@Test func aFloat16FieldIsTwoBytesInTheImagesLayoutIfPresent() throws {
    let expected: [(type: String, size: Int, fields: [String])] = [
        ("Split", 6, ["a@0+2", "h@2+2", "b@4+2"]),
        ("Joined", 6, ["a@0+2", "b@2+2", "h@4+2"]),
        ("SplitWide", 24, ["a@0+2", "h@2+2", "b@4+2", "d@8+8", "e@16+8"]),
        ("JoinedWide", 24, ["a@0+2", "b@2+2", "h@4+2", "d@8+8", "e@16+8"]),
    ]
    for path in images {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let maps = try FieldMapBuilder.build(in: try BinaryLoader.load(path: path))
        for (type, size, fields) in expected {
            let map = try #require(maps["FPBarrierPieces.\(type)"], "\(path): \(type)")
            #expect(map.trustLimitReason == nil, "\(path): \(type)")
            #expect(map.trustedOffsetLimit == size, "\(path): \(type)")
            #expect(map.instanceSize == size, "\(path): \(type)")
            #expect(map.fields.map { "\($0.name)@\($0.offset)+\($0.bytes)" } == fields, "\(path): \(type)")
            #expect(map.fieldTypeNames["h"] == "Swift.Float16", "\(path): \(type)")
        }
    }
}

/// The count from the images' own layouts: the float between the integers
/// makes two general registers, and five scalars in all go by address.
@Test func theFloatBarrierIsCountedFromTheImagesOwnLayoutsIfPresent() throws {
    for path in images {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let maps = try FieldMapBuilder.build(in: try BinaryLoader.load(path: path))
        #expect(banks("FPBarrierPieces.Split", maps) == [2, 1], "\(path)")
        #expect(directBanks("FPBarrierPieces.Split", maps) == [2, 1], "\(path)")
        #expect(banks("FPBarrierPieces.Joined", maps) == [1, 1], "\(path)")
        #expect(directBanks("FPBarrierPieces.Joined", maps) == [1, 1], "\(path)")
        // Its address, one general register, and no vector register.
        #expect(banks("FPBarrierPieces.SplitWide", maps) == [1, 0], "\(path)")
        #expect(directBanks("FPBarrierPieces.SplitWide", maps) == nil, "\(path)")
        #expect(banks("FPBarrierPieces.JoinedWide", maps) == [1, 3], "\(path)")
        #expect(directBanks("FPBarrierPieces.JoinedWide", maps) == [1, 3], "\(path)")
    }
}

/// Each formal after the struct is read from the register the struct's
/// pieces leave it: both bodies subtract their third formal from their
/// second, from x2 and x3 after `Split`, x1 and x2 after `Joined`, d0 and
/// d1 after the address of a `SplitWide`, d3 and d4 after a `JoinedWide`.
/// One register early or late, an operand has no formal and reads `?`.
@Test(arguments: images)
func formalsAfterAStructWithAFloat16FieldAreInTheirOwnRegistersIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    for name in ["afterSplit", "afterJoined", "afterSplitWide", "afterJoinedWide"] {
        let text = try await structured(path, name)
        #expect(text.contains("return (arg1 - arg2)"), "\(name):\n\(text)")
        // The struct is no one formal's register, and no operand is unknown.
        #expect(!text.contains("arg0"), "\(name):\n\(text)")
        #expect(!text.contains("?"), "\(name):\n\(text)")
    }
}

/// `secondOfSplit(_ s: Split, _ k: Int)` returns `s.b`, sign-extended from
/// w1, and never reads `k`, which is x2: no formal is in its result.
/// `secondOfJoined` returns `k` from x1. Its -O body is `mov x0, x1`, which
/// the linker folds onto `Split.b.getter`, so only -Onone has it by name.
@Test(arguments: images)
func theIntegerAfterTheFloatIsNotTheNextFormalIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let split = try await structured(path, "secondOfSplit")
    #expect(split.contains("return"), "\(split)")
    #expect(!split.contains("arg1"), "\(split)")
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    guard let joined = functions.first(where: { $0.displayName.hasPrefix("FPBarrierPieces.secondOfJoined(") })
    else { return }
    #expect(joined.renderStructured().contains("return arg1"), "\(joined.renderStructured())")
}

/// A constant stored to a Float16 field is the half its bits spell:
/// `withHalf` writes 1.5, the pattern 0x3e00, to `h` of its result.
@Test func aFloat16FieldConstantIsItsHalfIfPresent() async throws {
    let path = "Fixtures/Sample/libFPBarrierPieces.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try await structured(path, "withHalf")
    #expect(text.contains("h: 1.5"), "\(text)")
    #expect(!text.contains("15872") && !text.lowercased().contains("3e00"), "\(text)")
}

/// A two-byte field stored with `strh w0` holds the register's low sixteen
/// bits. The 32-bit mask that w0 itself carries is wider than the field:
/// `a: (arg0 & 0xffffffff)` named bits the field does not have.
@Test(arguments: ["libFPBarrierPieces.dylib", "libFPBarrierPieces.onone.dylib"])
func aNarrowFieldOfAResultIsItsStoredWidthIfPresent(image: String) async throws {
    let path = "Fixtures/Sample/\(image)"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try await structured(path, "SplitWide.init")
    #expect(text.contains("a: (arg0 & 0xffff),"), "\(text)")
    #expect(text.contains("b: (arg2 & 0xffff),"), "\(text)")
    #expect(!text.contains("0xffffffff"), "\(text)")
    // A floating-point register's store is not masked.
    #expect(text.contains("h: arg1,") && text.contains("d: arg3, e: arg4"), "\(text)")
}
