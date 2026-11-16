import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let fpCopyPath = "Fixtures/Sample/libFPCopies.dylib"

@Test func fpArgumentCopiesPreserveEncodingsInEveryPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fpCopyPath) else { return }
    let image = try BinaryLoader.load(path: fpCopyPath)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: fpCopyPath) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: fpCopyPath, functionFilter: "FPCopies") }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    var expected: [String: String] = ["integerCopy": "arg0"]
    for width in [16, 32, 64] {
        for name in ["direct", "copy", "move"] { expected["\(name)\(width)"] = "arg0.bitPattern" }
        expected["byte\(width)"] = "(arg0.bitPattern & 255)"
        if width > 16 { expected["short\(width)"] = "(arg0.bitPattern & 0xffff)" }
        expected["fpCopy\(width)"] = "arg0"
        expected["overlap\(width)"] = "?"
        expected["cleared\(width)"] = "0"
    }
    #expect(expected.count == 24)
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for (name, expression) in expected.sorted(by: { $0.key < $1.key }) {
            let function = try #require(group.first { $0.displayName.hasPrefix("FPCopies.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let returns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("return ") }
                #expect(returns == ["return " + expression], Comment(rawValue: text))
            }
        }
    }
}

#if arch(arm64)
@Test func fpArgumentCopiesNativeOraclePreservesPayloadsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: fpCopyPath) else { return }
    let handle = try #require(dlopen(fpCopyPath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Fixtures/Sample/fpcopies.abi.json")))
    let symbols = try #require((manifest as? [String: Any])?["symbols"] as? [String: String])
    #expect(symbols.count == 24)
    func pointer(_ name: String) throws -> UnsafeMutableRawPointer {
        let symbol = try #require(symbols[name])
        return try #require(dlsym(handle, symbol), Comment(rawValue: symbol))
    }
    func integer(_ name: String, width: Int, raw: UInt64) throws -> UInt64 {
        let p = try pointer(name)
        switch width {
        case 16: return unsafeBitCast(p, to: (@convention(thin) (Float16) -> UInt64).self)(Float16(bitPattern: UInt16(truncatingIfNeeded: raw)))
        case 32: return unsafeBitCast(p, to: (@convention(thin) (Float) -> UInt64).self)(Float(bitPattern: UInt32(truncatingIfNeeded: raw)))
        default: return unsafeBitCast(p, to: (@convention(thin) (Double) -> UInt64).self)(Double(bitPattern: raw))
        }
    }
    var observations = 0
    func check(_ value: UInt64, _ expected: UInt64, _ name: String) {
        #expect(value == expected, Comment(rawValue: name + ": " + String(value, radix: 16)))
        observations += 1
    }
    let patterns: [Int: [UInt64]] = [
        16: [0, 1, 0x8000, 0x3c00, 0x7c00, 0x7c01, 0x7e01, 0xffff],
        32: [0, 1, 0x80000000, 0x3f800000, 0x7f800000, 0x7f800001, 0x7fc00001, 0xffffffff],
        64: [0, 1, 0x8000000000000000, 0x3ff0000000000000, 0x7ff0000000000000, 0x7ff0000000000001, 0x7ff8000000000001, .max],
    ]
    for width in [16, 32, 64] {
        let fp = try pointer("fpCopy\(width)")
        for raw in try #require(patterns[width]) {
            for name in ["direct", "copy", "move"] { check(try integer("\(name)\(width)", width: width, raw: raw), raw, "\(name)\(width)") }
            check(try integer("byte\(width)", width: width, raw: raw), raw & 255, "byte\(width)")
            if width > 16 { check(try integer("short\(width)", width: width, raw: raw), raw & 0xffff, "short\(width)") }
            check(try integer("overlap\(width)", width: width, raw: raw), (raw & ~UInt64(255)) | 7, "overlap\(width)")
            check(try integer("cleared\(width)", width: width, raw: raw), 0, "cleared\(width)")
            let copied: UInt64
            switch width {
            case 16: copied = UInt64(unsafeBitCast(fp, to: (@convention(thin) (Float16) -> Float16).self)(Float16(bitPattern: UInt16(raw))).bitPattern)
            case 32: copied = UInt64(unsafeBitCast(fp, to: (@convention(thin) (Float) -> Float).self)(Float(bitPattern: UInt32(raw))).bitPattern)
            default: copied = unsafeBitCast(fp, to: (@convention(thin) (Double) -> Double).self)(Double(bitPattern: raw)).bitPattern
            }
            check(copied, raw, "fpCopy\(width)")
        }
    }
    let integerCopy = unsafeBitCast(try pointer("integerCopy"), to: (@convention(thin) (UInt64) -> UInt64).self)
    for raw in try #require(patterns[64]) { check(integerCopy(raw), raw, "integerCopy") }
    #expect(observations == 192)
}
#endif

@Test func fpArgumentCopiesIntoResultBuffersRetainBankAndByteWidth() throws {
    let engine = try #require(CapstoneEngine())
    for (width, store): (Int, UInt32) in [(16, 0x7d0003e0), (32, 0xbd0003e0), (64, 0xfd0003e0), (0, 0xf90003e0)] {
        let fullCount = width == 0 ? 8 : width / 8
        for count in Array(Set([1, 2, fullCount])).sorted() {
            for literal in width == 0 ? [false] : [false, true] {
                for chained in [false, true] {
                    // Save LR/x19 and the incoming x8 result pointer. Store a
                    // scalar, optionally copy its whole encoding to a second
                    // frame slot, then copy count bytes into the result buffer.
                    let setup: [UInt32] = literal ? [width == 16 ? 0x1eee1000 : width == 32 ? 0x1e2e1000 : 0x1e6e1000] : []
                    var words: [UInt32] = [0xd100c3ff, 0xa9027bf3, 0xaa0803f3] + setup + [store]
                    if chained {
                        words += [0x910043e0, 0x910003e1, 0xd2800002 | UInt32(fullCount << 5), 0x94000800]
                    }
                    words += [0xaa1303e0, chained ? 0x910043e1 : 0x910003e1,
                        0xd2800002 | UInt32(count << 5), 0x94000800, 0xa9427bf3, 0x9100c3ff, 0xd65f03c0]
                    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
                    let body = engine.disassemble(Data(bytes), address: 0x1000).map {
                        Instruction(address: $0.address, text: $0.text, annotation: nil,
                            controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail,
                            callee: .kept($0.controlFlow == .call ? "memcpy" : nil))
                    }
                    let function = DisassembledFunction(symbol: "copy", demangledName: nil, startAddress: 0x1000,
                                                        instructions: body, source: .symbol)
                    let result = ValueTracer().analyze(function, entry: .swiftInstance(scalarArguments: [width == 0 ? "x0" : "v0": 0]))
                    let exit = try #require(result.exitIndirectResults[body.last!.address])
                    let expected: AbstractValue
                    if literal {
                        let bits: UInt64 = width == 16 ? 0x3c00 : width == 32 ? 0x3f800000 : 0x3ff0000000000000
                        expected = .immediate(count == 8 ? bits : bits & ((UInt64(1) << (count * 8)) - 1))
                    } else {
                        let raw: AbstractValue = width == 0 ? .argument(0) : .unary(.bitPattern(bits: width), .argument(0))
                        expected = count == fullCount ? raw
                            : .binary(.bitAnd, raw, .immediate((UInt64(1) << (count * 8)) - 1))
                    }
                    #expect(!exit.poisoned)
                    #expect(exit.stores == [0: IndirectResultExit.Store(bytes: count, value: expected)],
                        "width=\(width), bytes=\(count), literal=\(literal), chained=\(chained)")
                }
            }
        }
    }
}
