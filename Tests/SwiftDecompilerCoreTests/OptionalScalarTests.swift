import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An Optional of a fixed-width scalar has no spare bits for nil, so Swift
/// passes the payload and a tag byte, and the layout declined it: the
/// positional fallback read one argument per register. `takeOptInt(nil, 7)`
/// rendered `takeOptInt(0, 1, 7)`, `takeOptDouble(2.5, 7)` rendered
/// `takeOptDouble(0x4004000000000000, 0, 7)`, and `takeOptInt32(nil, 7)`,
/// whose payload and tag share x0, rendered `takeOptInt32(0x100000000, 7)`
/// (`optionalscalars.swift`, -O). Each caller names its true call.
@Test func anOptionalScalarParameterIsOneArgumentIfPresent() async throws {
    let path = "Fixtures/Sample/libOptionalScalars.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let expected: [(caller: String, call: String)] = [
        ("callOptInt", "takeOptInt(?, 7)"),
        ("callOptIntSome", "takeOptInt(5, 7)"),
        ("callOptIntNil", "takeOptInt(nil, 7)"),
        ("callOptDouble", "takeOptDouble(?, 7)"),
        ("callOptDoubleSome", "takeOptDouble(2.5, 7)"),
        ("callOptInt32", "takeOptInt32(?, 7)"),
        ("callOptInt32Some", "takeOptInt32(5, 7)"),
        ("callOptInt32Nil", "takeOptInt32(nil, 7)"),
    ]
    for (caller, call) in expected {
        let function = try #require(functions.first { $0.displayName.hasPrefix("OptionalScalars.\(caller)(") })
        let text = function.renderPseudo()
        #expect(text.contains("OptionalScalars.\(call)"), "\(caller): \(text)")
    }
}

/// The registers: two for an eight-byte payload, one for a narrower one,
/// and a tag other than 0 or 1, or an unknown one, is no value.
@Test func anOptionalScalarTakesItsPayloadAndTagRegisters() {
    func slots(_ name: String) -> [Int]? {
        Disassembler.swiftCallArgumentSlots(
            callee: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())?.map(\.registers)
    }
    #expect(slots("M.f(Swift.Optional<Swift.Int>, Swift.Int) -> Swift.Int") == [2, 1])
    #expect(slots("M.f(Swift.Double?, Swift.Int) -> Swift.Int") == [2, 1])
    #expect(slots("M.f(Swift.Optional<CoreGraphics.CGFloat>, Swift.Int32?) -> ()") == [2, 1])
    #expect(slots("M.f(Swift.Optional<Swift.UInt8>, Swift.Optional<Swift.Float>) -> ()") == [1, 1])
    let argument = Disassembler.optionalScalarArgument
    #expect(argument([.immediate(5), .immediate(0)], 8) == .aggregate([.immediate(5), .immediate(0)]))
    #expect(argument([.immediate(0), .immediate(1)], 8) == .aggregate([.immediate(0), .immediate(1)]))
    #expect(argument([.immediate(5), .unknown], 8) == .unknown)
    #expect(argument([.immediate(5), .immediate(2)], 8) == .unknown)
    #expect(argument([.unknown, .immediate(0)], 8) == .unknown)
    #expect(argument([.immediate(0x1_0000_0000)], 4) == .aggregate([.immediate(0), .immediate(1)]))
    #expect(argument([.immediate(0xFFFF_FFFF)], 4) == .aggregate([.immediate(0xFFFF_FFFF), .immediate(0)]))
    #expect(argument([.immediate(0x205)], 1) == .unknown)
    #expect(argument([.argument(0)], 4) == .unknown)
}
