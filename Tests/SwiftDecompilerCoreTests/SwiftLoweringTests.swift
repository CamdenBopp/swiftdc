import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The one classification of how a Swift value travels, for the shapes the
/// result-register consumers relied on before they shared it.
@Test func swiftLoweringClassifiesKnownShapes() {
    let cases: [(String, SwiftLowering)] = [
        ("()", .zeroSized), ("Swift.Never", .zeroSized),
        ("Swift.Int", .oneInteger), ("Swift.Bool", .oneInteger), ("Swift.UInt32", .oneInteger),
        ("Swift.Error", .oneInteger), ("Swift.AnyObject", .oneInteger), ("Builtin.Int1", .oneInteger),
        // A variadic parameter is its Array; a String.Index is its raw bits.
        ("Any...", .oneInteger), ("Swift.Int...", .oneInteger), ("Swift.String.Index", .oneInteger),
        ("...", .unknown),
        ("Swift._StringComparisonResult", .oneInteger), ("Swift._StringGuts", .direct),
        ("Any.Type", .oneInteger),
        ("Swift.UnsafeMutableRawPointer", .oneInteger), ("Swift.UnsafePointer<Swift.Int>", .oneInteger),
        ("Swift.Array<Swift.Int>", .oneInteger), ("Swift.Dictionary<Swift.Int, Swift.String>", .oneInteger),
        ("Swift.Optional<Swift.UnsafeRawPointer>", .oneInteger),
        ("Swift.Double", .oneFloat), ("CoreGraphics.CGFloat", .oneFloat),
        ("Swift.String", .direct), ("Swift.Optional<Swift.Int>", .direct), ("Swift.Int.Type", .direct),
        ("Swift.UnsafeBufferPointer<Swift.UInt8>", .direct), ("(Swift.Int) -> Swift.Int", .direct),
        ("@escaping @Sendable (Swift.Int) -> ()", .direct),
        ("M.Pair", .unknown), ("A", .unknown), ("(Swift.Int, Swift.Int)", .unknown),
    ]
    for (type, expected) in cases {
        #expect(SwiftLowering.of(type) == expected, "\(type)")
    }
    // The result register follows it: x0 for one integer, v0 for one float.
    #expect(Disassembler.swiftReturnRegister(forReturnType: "Swift.Int") == .integer)
    #expect(Disassembler.swiftReturnRegister(forReturnType: "Swift.Float") == .floating)
    #expect(Disassembler.swiftReturnRegister(forReturnType: "Swift.String") == nil)
    #expect(Disassembler.swiftReturnRegister(forReturnType: "Swift.Optional<Swift.Int>") == nil)
}

/// A result through x8 is no direct result: a tuple of closures, or a type
/// nested in a one-pointer collection, is not that collection or a closure
/// (ABI review a3 #4).
@Test func aTupleOfClosuresOrANestedCollectionTypeIsNoDirectResult() {
    let index = ClassTypeIndex()
    #expect(!Disassembler.isKnownDirectReturnType(
        "((Swift.Int) -> Swift.Int, (Swift.Int) -> Swift.Int, (Swift.Int) -> Swift.Int)", classTypeIndex: index))
    #expect(!Disassembler.isKnownDirectReturnType("Swift.Dictionary<Swift.Int, Swift.Int>.Iterator", classTypeIndex: index))
    #expect(!Disassembler.isKnownDirectReturnType("Swift.Array<(Swift.Int) -> Swift.Int>.Index.Stride", classTypeIndex: index))
    #expect(Disassembler.isKnownDirectReturnType("(Swift.Int) -> Swift.Int", classTypeIndex: index))
    #expect(Disassembler.isKnownDirectReturnType("Swift.Dictionary<Swift.Int, Swift.Int>", classTypeIndex: index))
    #expect(Disassembler.isKnownDirectReturnType("Swift.Optional<Swift.String>", classTypeIndex: index))
}

/// `>` in a function arrow is not the end of a generic argument list.
/// Closure arrays and dictionaries keep their one-pointer representation;
/// names nested in those collections still do not inherit that layout.
@Test func functionValuedCollectionsKeepTheirOwnLowering() {
    let oneWord = [
        "Swift.Array<(Swift.Int) -> Swift.Int>",
        "Swift.ContiguousArray<@Sendable (Swift.Int) async throws -> Swift.String>",
        "Swift.Dictionary<Swift.String, (Swift.Int) -> Swift.Int>",
        "Swift.Dictionary<Swift.String, Swift.Array<(Swift.Int) -> Swift.Int>>",
        "Swift.Array<((Swift.Int) -> Swift.Int) -> (Swift.Int) -> Swift.Int>",
        "Swift.Array<() -> Swift.Array<Swift.Int>>",
        "Swift._ArrayBuffer<(Swift.Int) -> Swift.Int>",
        "Swift._ContiguousArrayBuffer<(Swift.Int) -> Swift.Int>",
    ]
    for type in oneWord {
        #expect(SwiftLowering.of(type) == .oneInteger, "\(type)")
        #expect(Disassembler.swiftReturnRegister(forReturnType: type) == .integer, "\(type)")
        #expect(SwiftLowering.of(type + ".Iterator") == .unknown, "\(type).Iterator")
        #expect(SwiftLowering.of(type + ".Nested<Swift.Int>") == .unknown, "\(type).Nested<Swift.Int>")
    }
    for generic in ["Swift.UnsafeBufferPointer", "Swift.UnsafeMutableBufferPointer"] {
        let type = generic + "<(Swift.Int) -> Swift.Int>"
        #expect(SwiftLowering.of(type) == .direct, "\(type)")
        #expect(Disassembler.swiftReturnRegister(forReturnType: type) == nil, "\(type)")
        #expect(SwiftLowering.of(type + ".Iterator") == .unknown, "\(type).Iterator")
    }
    #expect(SwiftLowering.of("Swift.Optional<Swift.Array<(Swift.Int) -> Swift.Int>>") == .direct)
}

/// The shared lowering reaches both entry seeding and call layout, so an
/// Int after a collection of closures is still x1, not left unknown.
@Test func functionValuedCollectionsDoNotHideFollowingArguments() {
    for type in ["Swift.Array<(Swift.Int) -> Swift.Int>",
                 "Swift.Dictionary<Swift.String, (Swift.Int) -> Swift.Int>"] {
        let name = "M.take(\(type), Swift.Int) -> Swift.Int"
        let function = DisassembledFunction(symbol: "$s1M4take", demangledName: name,
                                            startAddress: 0x1000, instructions: [], source: .symbol)
        #expect(Disassembler.swiftScalarArgumentRegisters(of: function) == ["x0": 0, "x1": 1])
        let layout: [Disassembler.ScalarParameterClass]? = Disassembler.swiftCallArgumentLayout(
            callee: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())
        #expect(layout == [.integer, .integer])
    }
}

@Test func functionValuedCollectionCallsKeepFollowingArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/libClosureCollections.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    for (shape, constant) in [("Array", 1), ("Contiguous", 2), ("Dictionary", 3), ("Nested", 4)] {
        let function = try #require(functions.first {
            $0.displayName.hasPrefix("ClosureCollections.pass\(shape)(")
        })
        let text = function.renderStructured()
        #expect(text.contains("return (ClosureCollections.take\(shape)(arg0, arg1) + \(constant))"),
                Comment(rawValue: text))
    }
}
