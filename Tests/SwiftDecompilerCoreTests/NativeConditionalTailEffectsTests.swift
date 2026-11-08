import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func conditionalTailNativeCallersRejectStaleConstantsIfPresent() async throws {
    let path = "Fixtures/Sample/libConditionalTailEffects.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let cases = [
        ("8gprTakens6UInt64VyF", false, 1, false), ("10gprUntakens6UInt64VyF", false, 2, false),
        ("7gprSafes6UInt64VyF", false, 2, true), ("9gprReloads6UInt64VyF", false, 2, true),
        ("11vectorTakenSdyF", true, 1, false), ("13vectorUntakenSdyF", true, 2, false),
        ("10vectorSafeSdyF", true, 2, true), ("12vectorReloadSdyF", true, 2, true),
        ("12frameScratchs6UInt64VyF", false, 1, false),
    ]
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    for (suffix, floating, expected, _) in cases {
        let pointer = try #require(dlsym(library, "$s11TailEffects" + suffix))
        if floating {
            #expect(unsafeBitCast(pointer, to: (@convention(c) () -> Double).self)() == Double(expected))
        } else {
            #expect(unsafeBitCast(pointer, to: (@convention(c) () -> UInt64).self)() == UInt64(expected))
        }
    }
    let array = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "TailEffects") }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    try #require(array.count == 17 && streamed.count == 17 && filtered.count == 9)
    let symbols = Set(cases.map { "_$s11TailEffects" + $0.0 })
    try #require(Set(filtered.map(\.symbol)) == symbols)
    for (mode, functions) in [("array", array), ("filtered", filtered), ("streaming", streamed)] {
        for (suffix, floating, native, precise) in cases {
            let matches = functions.filter { $0.symbol == "_$s11TailEffects" + suffix }
            try #require(matches.count == 1)
            let function = try #require(matches.first)
            let exits = function.instructions.compactMap { $0.exit?.statement }
            try #require(exits.count == 1, "\(mode): \(function.renderPseudo())")
            let expected = "return " + String(native) + (floating ? ".0" : "")
            #expect(exits == [expected] || (!precise && exits == ["return ?"]), "\(mode): \(function.renderPseudo())")
        }
    }
}
