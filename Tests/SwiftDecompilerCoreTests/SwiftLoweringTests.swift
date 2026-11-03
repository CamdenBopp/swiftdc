import Testing
@testable import SwiftDecompilerCore

/// The one classification of how a Swift value travels, for the shapes the
/// result-register consumers relied on before they shared it.
@Test func swiftLoweringClassifiesKnownShapes() {
    let cases: [(String, SwiftLowering)] = [
        ("()", .zeroSized), ("Swift.Never", .zeroSized),
        ("Swift.Int", .oneInteger), ("Swift.Bool", .oneInteger), ("Swift.UInt32", .oneInteger),
        ("Swift.Error", .oneInteger), ("Swift.AnyObject", .oneInteger), ("Builtin.Int1", .oneInteger),
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
