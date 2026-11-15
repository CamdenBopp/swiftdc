import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private struct NaNFormat {
    let width: Int
    let type: String
    let result: String
    let sign: UInt64
    let finite: UInt64
    let patterns: [(String, UInt64)]
    func literal(_ pattern: UInt64) -> String { "\(type)(bitPattern: 0x\(String(pattern, radix: 16)))" }
}
// Independent expected encodings, not read from the fixture generator or tracer.
private let nanFormats = [
    NaNFormat(width: 64, type: "Double", result: "Sd", sign: 0x8000000000000000, finite: 0x4004000000000000,
        patterns: [("quiet", 0x7ff8000000000001), ("negative", 0xfff8000000000001),
                   ("signaling", 0x7ff0000000000001), ("negativeSignaling", 0xfff0000000000001), ("payload", 0x7ff8000000000002)]),
    NaNFormat(width: 32, type: "Float", result: "Sf", sign: 0x80000000, finite: 0x40200000,
        patterns: [("quiet", 0x7fc00001), ("negative", 0xffc00001),
                   ("signaling", 0x7f800001), ("negativeSignaling", 0xff800001), ("payload", 0x7fc00002)]),
    NaNFormat(width: 16, type: "Float16", result: "s7Float16V", sign: 0x8000, finite: 0x4100,
        patterns: [("quiet", 0x7e01), ("negative", 0xfe01),
                   ("signaling", 0x7c01), ("negativeSignaling", 0xfc01), ("payload", 0x7e02)]),
]
private let nanLiteralPath = "Fixtures/Sample/libNaNLiterals.dylib"

@Test func nanFormattingRetainsEveryEncodingAndTypeAlias() {
    let aliases = [64: ["Swift.Double", "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat"],
                   32: ["Swift.Float", "Swift.Float32"], 16: ["Swift.Float16"]]
    for format in nanFormats {
        let mask = format.width == 64 ? UInt64.max : (UInt64(1) << format.width) - 1
        let patterns = format.patterns.map(\.1) + [format.patterns[0].1 & ~1,
            format.patterns[1].1 & ~1, mask >> 1, mask]
        for pattern in patterns {
            #expect(Disassembler.renderFloatingConstant(bits: pattern, width: format.width) == format.literal(pattern))
            // Upper register bits do not belong to a single/half constant.
            let dirty = format.width == 64 ? pattern : pattern | (UInt64.max << format.width)
            for alias in aliases[format.width]! {
                #expect(Disassembler.renderTypedConstant(bits: dirty, type: alias) == format.literal(pattern))
            }
        }
        #expect(Disassembler.renderFloatingConstant(bits: format.finite, width: format.width) == "2.5")
        #expect(Disassembler.renderFloatingConstant(bits: 0, width: format.width) == "0.0")
        #expect(Disassembler.renderFloatingConstant(bits: format.sign, width: format.width) == "-0.0")
    }
    for (width, infinity) in [(64, UInt64(0x7ff0000000000000)), (32, 0x7f800000), (16, 0x7c00)] {
        #expect(Disassembler.renderFloatingConstant(bits: infinity, width: width) == "inf")
    }
    #expect(Disassembler.renderFloatingConstant(bits: 0x7fefffffffffffff, width: 64) == String(Double.greatestFiniteMagnitude))
    #expect(Disassembler.renderFloatingConstant(bits: 0x7f7fffff, width: 32) == String(Float.greatestFiniteMagnitude))
    #expect(Disassembler.renderFloatingConstant(bits: 0x7bff, width: 16) == String(Float(Float16.greatestFiniteMagnitude)))
    #expect(Disassembler.renderFloatingConstant(bits: .max, width: 8) == nil)
    #expect(Disassembler.renderTypedConstant(bits: 0x7ff8000000000001, type: "Swift.UInt64") == nil)
}

@Test func nanLiteralsKeepTheirExactBitsInEveryAnalysisPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: nanLiteralPath) else { return }
    let image = try BinaryLoader.load(path: nanLiteralPath)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: nanLiteralPath) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: nanLiteralPath, functionFilter: "NaNBits")
    }
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    var expected: [String: String] = [:]
    for format in nanFormats {
        for (kind, pattern) in format.patterns { expected[kind + String(format.width)] = format.literal(pattern) }
        expected["finite\(format.width)"] = "2.5"
        let negative = "-" + format.literal(format.patterns[0].1)
        expected["neg\(format.width)"] = format.width == 16 ? negative
            : format.width == 32 ? "((\(negative)).bitPattern & 0xffffffff)" : "(\(negative)).bitPattern"
        if format.width != 16 {
            expected["consume\(format.width)"] = format.width == 32 ? "(arg0.bitPattern & 0xffffffff)" : "arg0.bitPattern"
            expected["call\(format.width)"] = "NaNBits.consume\(format.width)(\(format.literal(format.patterns[3].1)))"
            expected["finiteCall\(format.width)"] = "NaNBits.consume\(format.width)(2.5)"
        }
    }
    #expect(expected.count == 27)
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for (name, expression) in expected.sorted(by: { $0.key < $1.key }) {
            let function = try #require(group.first { $0.displayName.hasPrefix("NaNBits.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let returns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("return ") }
                #expect(returns == ["return " + expression], Comment(rawValue: text))
            }
        }
    }
}

#if arch(arm64)
@Test func nanLiteralNativeOraclePreservesSignsSignalingAndPayloadsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: nanLiteralPath) else { return }
    let handle = try #require(dlopen(nanLiteralPath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    func symbol(_ name: String, _ result: String) throws -> UnsafeMutableRawPointer {
        try #require(dlsym(handle, "$s7NaNBits\(name.count)\(name)\(result)yF"))
    }
    for format in nanFormats {
        for (name, expected) in format.patterns + [("finite", format.finite)] {
            let pointer = try symbol(name + String(format.width), format.result)
            let actual: UInt64
            switch format.width {
            case 64: actual = unsafeBitCast(pointer, to: (@convention(thin) () -> Double).self)().bitPattern
            case 32: actual = UInt64(unsafeBitCast(pointer, to: (@convention(thin) () -> Float).self)().bitPattern)
            default: actual = UInt64(unsafeBitCast(pointer, to: (@convention(thin) () -> Float16).self)().bitPattern)
            }
            #expect(actual == expected, Comment(rawValue: name + String(format.width)))
        }
        let result = format.width == 16 ? format.result : "s6UInt\(format.width)V"
        let pointer = try symbol("neg\(format.width)", result)
        let actual: UInt64
        switch format.width {
        case 64: actual = unsafeBitCast(pointer, to: (@convention(thin) () -> UInt64).self)()
        case 32: actual = UInt64(unsafeBitCast(pointer, to: (@convention(thin) () -> UInt32).self)())
        default: actual = UInt64(unsafeBitCast(pointer, to: (@convention(thin) () -> Float16).self)().bitPattern)
        }
        #expect(actual == format.patterns[0].1 ^ format.sign)
        guard format.width != 16 else { continue }
        for (kind, expected) in [("call", format.patterns[3].1), ("finiteCall", format.finite)] {
            let pointer = try symbol(kind + String(format.width), result)
            let actual = format.width == 64 ? unsafeBitCast(pointer, to: (@convention(thin) () -> UInt64).self)()
                : UInt64(unsafeBitCast(pointer, to: (@convention(thin) () -> UInt32).self)())
            #expect(actual == expected)
        }
        let inputType = format.width == 64 ? "Sd" : "Sf"
        let consume = try #require(dlsym(handle, "$s7NaNBits9consume\(format.width)ys6UInt\(format.width)V\(inputType)F"))
        for (_, pattern) in format.patterns {
            let actual = format.width == 64
                ? unsafeBitCast(consume, to: (@convention(thin) (Double) -> UInt64).self)(Double(bitPattern: pattern))
                : UInt64(unsafeBitCast(consume, to: (@convention(thin) (Float) -> UInt32).self)(Float(bitPattern: UInt32(pattern))))
            #expect(actual == pattern)
        }
    }
}
#endif
