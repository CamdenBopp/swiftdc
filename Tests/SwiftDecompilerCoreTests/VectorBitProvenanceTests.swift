import Foundation
import Testing
#if os(macOS)
import Darwin
#endif
@testable import SwiftDecompilerCore

private let vectorBitsPath = "Fixtures/Sample/libVectorBits.dylib"

@Test func vectorFloatingPredecessorExitsProjectRawLanes() throws {
    // cbz x0, 0x100c; dup v0.2d,x0; b 0x1010; dup v0.2d,x1; ret
    let words: [UInt32] = [0xb4000060, 0x4e080c00, 0x14000002, 0x4e080c20, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let engine = try #require(CapstoneEngine())
    let body = engine.disassemble(Data(bytes), address: 0x1000).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    #expect(body.count == words.count)
    let function = DisassembledFunction(symbol: "_vectorExit", demangledName: nil,
        startAddress: 0x1000, instructions: body, source: .symbol)
    let analysis = ValueTracer().analyze(function,
        entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
    let exits = try #require(analysis.exitFloatValuesByPredecessor[0x1010])
    #expect(exits.count == 2)
    #expect(exits.values.contains(.unary(.floatFromBits(bits: 64), .argument(0))))
    #expect(exits.values.contains(.unary(.floatFromBits(bits: 64), .argument(1))))
}

@Test func symbolicVectorLanesKeepTheirBitInterpretationIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: vectorBitsPath) else { return }
    let image = try BinaryLoader.load(path: vectorBitsPath)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: vectorBitsPath) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: vectorBitsPath, functionFilter: "BitVector")
    }
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    for functions in [listing, array, filtered, streamed, Array(each.values)] {
        for (name, expected) in [
            ("bits", "return Double(bitPattern: arg0)"),
            ("spill", "return Double(bitPattern: arg0)"),
            ("word", "return arg0.bitPattern"),
            ("direct", "return arg0.bitPattern"),
            ("float", "return arg0"),
            ("round", "return arg0"),
        ] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("BitVector.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let returns = text.split(separator: "\n").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { $0.hasPrefix("return ") }
                #expect(returns == [expected], Comment(rawValue: text))
            }
        }
    }
}

#if os(macOS) && arch(arm64)
@Test func symbolicVectorLaneNativeValuesMatchBitInterpretationsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: vectorBitsPath) else { return }
    let handle = try #require(dlopen(vectorBitsPath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let inputs: [UInt64] = [0, 1, 0x3ff0000000000000, 0x4000000000000000,
        0xbff0000000000000, 0x8000000000000000, 0x7ff0000000000000, 0x7ff8000000000001]
    for (name, length) in [("bits", 4), ("spill", 5)] {
        let pointer = try #require(dlsym(handle, "$s9BitVector\(length)\(name)ySds6UInt64VF"))
        let native = unsafeBitCast(pointer, to: (@convention(thin) (UInt64) -> Double).self)
        for bits in inputs { #expect(native(bits).bitPattern == bits) }
    }
    let wordPointer = try #require(dlsym(handle, "$s9BitVector4wordys6UInt64VSdF"))
    let word = unsafeBitCast(wordPointer, to: (@convention(thin) (Double) -> UInt64).self)
    let floatPointer = try #require(dlsym(handle, "$s9BitVector5floatyS2dF"))
    let float = unsafeBitCast(floatPointer, to: (@convention(thin) (Double) -> Double).self)
    let roundPointer = try #require(dlsym(handle, "$s9BitVector5roundys6UInt64VADF"))
    let round = unsafeBitCast(roundPointer, to: (@convention(thin) (UInt64) -> UInt64).self)
    let directPointer = try #require(dlsym(handle, "$s9BitVector6directys6UInt64VSdF"))
    let direct = unsafeBitCast(directPointer, to: (@convention(thin) (Double) -> UInt64).self)
    for bits in inputs {
        #expect(word(Double(bitPattern: bits)) == bits)
        #expect(float(Double(bitPattern: bits)).bitPattern == bits)
        #expect(round(bits) == bits)
        #expect(direct(Double(bitPattern: bits)) == bits)
    }
}
#endif
