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
