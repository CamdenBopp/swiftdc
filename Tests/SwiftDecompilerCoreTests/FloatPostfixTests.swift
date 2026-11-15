import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let floatPostfixPath = "Fixtures/Sample/libFloatPostfix.dylib"

@Test func floatBitPatternReceiversKeepTheirPrefixGroupingInEveryPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: floatPostfixPath) else { return }
    let image = try BinaryLoader.load(path: floatPostfixPath)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: floatPostfixPath) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: floatPostfixPath, functionFilter: "FloatPostfix")
    }
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    for functions in [listing, array, filtered, streamed, Array(each.values)] {
        for (name, expected) in [
            ("neg64", "return (-arg0).bitPattern"),
            ("neg32", "return ((-arg0).bitPattern & 0xffffffff)"),
            ("spilled", "return (-arg0).bitPattern"),
            ("literal", "return (-1.0).bitPattern"),
            ("zero", "return (-0.0).bitPattern"),
            ("compound", "return (-arg0 + -arg0).bitPattern"),
            ("plain", "return arg0.bitPattern"),
        ] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("FloatPostfix.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let returns = text.split(separator: "\n").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { $0.hasPrefix("return ") }
                #expect(returns == [expected], Comment(rawValue: text))
            }
        }
    }
}

#if arch(arm64)
@Test func floatPostfixNativeOracleChecksSignBitsBeforeIntegerReadsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: floatPostfixPath) else { return }
    let handle = try #require(dlopen(floatPostfixPath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let doubleInputs: [UInt64] = [0, 0x8000000000000000, 0x3ff0000000000000,
        0xbff0000000000000, 0x4000000000000000, 1, 0x7ff0000000000000, 0x7ff8000000000001]
    for (name, length) in [("neg64", 5), ("spilled", 7), ("compound", 8), ("plain", 5)] {
        let pointer = try #require(dlsym(handle, "$s12FloatPostfix\(length)\(name)ys6UInt64VSdF"))
        let native = unsafeBitCast(pointer, to: (@convention(thin) (Double) -> UInt64).self)
        for bits in doubleInputs {
            let value = Double(bitPattern: bits)
            let expected = name == "plain" ? bits : name == "compound"
                ? ((-value) + (-value)).bitPattern : bits ^ (1 << 63)
            #expect(native(value) == expected, Comment(rawValue: name + ": " + String(bits, radix: 16)))
        }
    }
    let pointer = try #require(dlsym(handle, "$s12FloatPostfix5neg32ys6UInt32VSfF"))
    let native = unsafeBitCast(pointer, to: (@convention(thin) (Float) -> UInt32).self)
    let floatInputs: [UInt32] = [0, 0x80000000, 0x3f800000, 0xbf800000,
        0x40000000, 1, 0x7f800000, 0x7fc00001]
    for bits in floatInputs { #expect(native(Float(bitPattern: bits)) == bits ^ (1 << 31)) }
    for (name, length, expected): (String, Int, UInt64) in [
        ("literal", 7, 0xbff0000000000000), ("zero", 4, 0x8000000000000000),
    ] {
        let pointer = try #require(dlsym(handle, "$s12FloatPostfix\(length)\(name)ys6UInt64VyF"))
        let native = unsafeBitCast(pointer, to: (@convention(thin) () -> UInt64).self)
        #expect(native() == expected)
    }
}
#endif
