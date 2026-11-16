import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let halfMovePath = "Fixtures/Sample/libHalfMoves.dylib"
private func halfMoveSymbol(_ name: String, argument: String?, result: String) -> String {
    let input = argument == result ? "AD" : argument ?? "y"
    return "$s9HalfMoves\(name.count)\(name)\(argument == nil ? "" : "y")\(result)\(input)F"
}

@Test func halfMovesPreserveBitsAndTruncationInEveryPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: halfMovePath) else { return }
    let image = try BinaryLoader.load(path: halfMovePath)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: halfMovePath) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: halfMovePath, functionFilter: "HalfMoves") }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    var expected = ["producer": "2.5"]
    for suffix in ["W", "X"] {
        let half = "Float16(bitPattern: UInt16(truncatingIfNeeded: (arg0 & 0xffff)))"
        func word(_ expression: String) -> String { suffix == "W" ? "(\(expression) & 0xffffffff)" : expression }
        expected["neg" + suffix] = word("(-Float16(1.0)).bitPattern")
        expected["arg" + suffix] = word("arg0.bitPattern")
        expected["narrow" + suffix] = word("(-arg0).bitPattern")
        expected["from" + suffix] = half
        expected["view" + suffix] = "Double(bitPattern: (arg0 & 0xffff))"
        expected["single" + suffix] = "Float(bitPattern: (arg0 & 0xffff))"
        expected["viewConst" + suffix] = String(Double(bitPattern: 0x7e01))
        expected["add" + suffix] = "(\(half) + \(half))"
        expected["round" + suffix] = "(arg0 & 0xffff)"
        expected["back" + suffix] = "arg0"
        expected["raw" + suffix] = "0x7e01"
        expected["low" + suffix] = "0x7e01"
        expected["call" + suffix] = word("HalfMoves.producer().bitPattern")
    }
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for (name, expression) in expected.sorted(by: { $0.key < $1.key }) {
            let function = try #require(group.first { $0.displayName.hasPrefix("HalfMoves.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let returns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("return ") }
                #expect(returns == ["return " + expression], Comment(rawValue: text))
            }
        }
    }
}

#if arch(arm64)
@Test func halfMovesNativeOracleChecksAllFourFormsAndDirtyUpperBitsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: halfMovePath) else { return }
    let handle = try #require(dlopen(halfMovePath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    var observations = 0
    func check(_ actual: UInt64, _ expected: UInt64) {
        #expect(actual == expected)
        observations += 1
    }
    func pointer(_ name: String, _ argument: String?, _ result: String) throws -> UnsafeMutableRawPointer {
        try #require(dlsym(handle, halfMoveSymbol(name, argument: argument, result: result)))
    }
    for wide in [false, true] {
        let suffix = wide ? "X" : "W"
        let integer = wide ? "s6UInt64V" : "s6UInt32V"
        let half = "s7Float16V"
        for (name, expected) in [("neg", UInt64(0xbc00)), ("raw", 0x7e01), ("low", 0x7e01), ("call", 0x4100)] {
            let p = try pointer(name + suffix, nil, integer)
            let result = wide ? unsafeBitCast(p, to: (@convention(thin) () -> UInt64).self)()
                : UInt64(unsafeBitCast(p, to: (@convention(thin) () -> UInt32).self)())
            check(result, expected)
        }
        let viewConstant = unsafeBitCast(try pointer("viewConst" + suffix, nil, "Sd"), to: (@convention(thin) () -> Double).self)
        check(viewConstant().bitPattern, 0x7e01)
        for bits: UInt16 in [0, 0x8000, 0x3c00, 0xbc00, 0x7e01, 0x7c01, 0xffff] {
            let input = Float16(bitPattern: bits)
            for name in ["arg", "narrow"] {
                let p = try pointer(name + suffix, half, integer)
                let result = wide ? unsafeBitCast(p, to: (@convention(thin) (Float16) -> UInt64).self)(input)
                    : UInt64(unsafeBitCast(p, to: (@convention(thin) (Float16) -> UInt32).self)(input))
                check(result, UInt64(bits ^ (name == "narrow" ? 0x8000 : 0)))
            }
            let back = unsafeBitCast(try pointer("back" + suffix, half, half), to: (@convention(thin) (Float16) -> Float16).self)
            check(UInt64(back(input).bitPattern), UInt64(bits))
        }
        for input: UInt64 in [0, 0x8000, 0x3c00, 0x3d00, 0xabcd7e01, 0xffff7c01, 0x12340000abcd2e66, .max] {
            let expected = input & 0xffff
            let from = try pointer("from" + suffix, integer, half)
            let value = wide ? unsafeBitCast(from, to: (@convention(thin) (UInt64) -> Float16).self)(input)
                : unsafeBitCast(from, to: (@convention(thin) (UInt32) -> Float16).self)(UInt32(truncatingIfNeeded: input))
            check(UInt64(value.bitPattern), expected)
            let round = try pointer("round" + suffix, integer, integer)
            let bits = wide ? unsafeBitCast(round, to: (@convention(thin) (UInt64) -> UInt64).self)(input)
                : UInt64(unsafeBitCast(round, to: (@convention(thin) (UInt32) -> UInt32).self)(UInt32(truncatingIfNeeded: input)))
            check(bits, expected)
            let view = try pointer("view" + suffix, integer, "Sd")
            let double = wide ? unsafeBitCast(view, to: (@convention(thin) (UInt64) -> Double).self)(input)
                : unsafeBitCast(view, to: (@convention(thin) (UInt32) -> Double).self)(UInt32(truncatingIfNeeded: input))
            check(double.bitPattern, expected)
            let single = try pointer("single" + suffix, integer, "Sf")
            let float = wide ? unsafeBitCast(single, to: (@convention(thin) (UInt64) -> Float).self)(input)
                : unsafeBitCast(single, to: (@convention(thin) (UInt32) -> Float).self)(UInt32(truncatingIfNeeded: input))
            check(UInt64(float.bitPattern), expected)
        }
        for bits: UInt16 in [0, 0x8000, 0x3c00, 0xbc00, 0x2e66] {
            let input = UInt64(bits) | (wide ? 0x12340000abcd0000 : 0xabcd0000)
            let add = try pointer("add" + suffix, integer, half)
            let value = wide ? unsafeBitCast(add, to: (@convention(thin) (UInt64) -> Float16).self)(input)
                : unsafeBitCast(add, to: (@convention(thin) (UInt32) -> Float16).self)(UInt32(truncatingIfNeeded: input))
            let operand = Float16(bitPattern: bits)
            check(UInt64(value.bitPattern), UInt64((operand + operand).bitPattern))
        }
    }
    let producer = unsafeBitCast(try pointer("producer", nil, "s7Float16V"), to: (@convention(thin) () -> Float16).self)
    check(UInt64(producer().bitPattern), 0x4100)
    #expect(observations == 127)
}
#endif

@Test func halfMovesWiderViewsPreserveOnlyTheLowRawWord() {
    let word = AbstractValue.binary(.bitAnd, .argument(0), .immediate(0xffff))
    let selected = AbstractValue.select(condition: .argument(1), whenTrue: .immediate(1), whenFalse: .immediate(2))
    var deep = word
    // The leaf has depth zero; normalization adds the eighth operation.
    for _ in 0..<6 { deep = .unary(.bitwiseNot, deep) }
    for bits in [32, 64] {
        let expected = AbstractValue.unary(.floatFromBits(bits: bits), word)
        #expect(ValueTracer.floatOperand(.unary(.floatFromBits(bits: 16), word), bits: bits) == expected)
        #expect(ValueTracer.floatOperand(.unary(.floatFromBits(bits: 16), .argument(0)), bits: bits) == expected)
        #expect(ValueTracer.floatOperand(.unary(.floatFromBits(bits: 16), selected), bits: bits)
            == .unary(.floatFromBits(bits: bits), selected))
        #expect(ValueTracer.floatOperand(.unary(.floatFromBits(bits: 16), deep), bits: bits) == .unknown)
    }
}
