import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An instance getter takes no formal parameter. One whose `self` is a
/// float takes it in v0, and the integer registers at the call hold the
/// caller's own formals or an earlier call's result: at -Onone
/// `Float.bitPattern.getter` rendered `getter(arg1, arg2)` and then
/// `getter(r0)`. bitpatterngetters.swift states each function's value.
private let bitPatternImage = "Fixtures/Sample/libBitPatternGetters.onone.dylib"

private func bitPatternViews(_ name: String) async throws -> [String]? {
    guard FileManager.default.fileExists(atPath: bitPatternImage) else { return nil }
    let image = try BinaryLoader.load(path: bitPatternImage)
    let listing = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: bitPatternImage)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: bitPatternImage, functionFilter: name)
    }
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreaming(machO: image, transform: { $0 })
    }
    return try [listing, filtered, streamed].flatMap { functions -> [String] in
        let function = try #require(functions.first { $0.displayName.contains("BitPatternGetters.\(name)(") })
        return [function.renderStructured(), function.renderPseudo()]
    }
}

@Test(arguments: [("floatBits", "Swift.Float.bitPattern.getter", 2), ("doubleBits", "Swift.Double.bitPattern.getter", 1)])
func aFloatGetterTakesNoIntegerRegisterIfPresent(name: String, getter: String, calls: Int) async throws {
    guard let views = try await bitPatternViews(name) else { return }
    for text in views {
        // Every call is shown, with an unknown receiver and no argument.
        #expect(text.components(separatedBy: "\(getter)(self: ?)").count == calls + 1, "\(text)")
        #expect(text.components(separatedBy: "\(getter)(").count == calls + 1, "\(text)")
        // The caller's formals are still its own terms of the sum.
        #expect(text.contains("arg1"), "\(text)")
    }
}

/// A fixed-width integer receiver is in x0, and its getter takes nothing
/// after it: `Int.hashValue.getter(arg0, arg1)` named the caller's second
/// formal, still in x1, as an argument.
@Test func anIntegerGetterTakesItsReceiverAndNothingElseIfPresent() async throws {
    guard let views = try await bitPatternViews("intHash") else { return }
    for text in views {
        #expect(text.contains("(Swift.Int.hashValue.getter(self: arg0) + arg1)"), "\(text)")
    }
}

/// A static getter of a float type has no receiver, known or unknown.
@Test func aStaticFloatGetterHasNoReceiverIfPresent() async throws {
    guard let views = try await bitPatternViews("staticBits") else { return }
    for text in views {
        #expect(text.contains("static Swift.Float.pi.getter()"), "\(text)")
    }
}
