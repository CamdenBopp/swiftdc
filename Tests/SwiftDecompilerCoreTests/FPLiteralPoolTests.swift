import Darwin
import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let poolPath = "Fixtures/Sample/libFPPools.dylib"
private let edgePath = "Fixtures/Sample/libFPPoolEdges.dylib"
private let poolWidths = [64, 32, 16]
private func poolType(_ width: Int) -> String { width == 64 ? "Double" : width == 32 ? "Float" : "Float16" }
private func poolResult(_ width: Int) -> String { width == 64 ? "Sd" : width == 32 ? "Sf" : "s7Float16V" }
private func poolLast(_ width: Int) -> UInt64 { width == 64 ? 0xfff8000000000002 : width == 32 ? 0xffc00002 : 0xfe02 }
private func poolFinite(_ width: Int) -> UInt64 { width == 64 ? 0x4004000000000000 : width == 32 ? 0x3dcccccd : 0x2e66 }
private func poolSign(_ width: Int) -> UInt64 { UInt64(1) << (width - 1) }
private func poolResolver(_ image: MachOFile) -> Disassembler.ReferenceResolver {
    .init(names: [:], stringRanges: [], machO: image, demangleSymbol: { _ in nil })
}

@Test func scalarPoolExpressionsKeepDomainWidthAndRoundingInEveryPipelineIfPresent() async throws {
    for path in [poolPath, edgePath] where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "FPPools") }
        let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        var expected: [String: String] = [:]
        for width in poolWidths {
            let finite = width == 64 ? "2.5" : width == 32 ? "Float(0.1)" : "Float16(0.099975586)"
            let nan = width == 64 ? "Double(bitPattern: 0x7ff8000000000001)" : width == 32 ? "Float(bitPattern: 0x7fc00001)" : "Float16(bitPattern: 0x7e01)"
            let last = "\(poolType(width))(bitPattern: 0x\(String(poolLast(width), radix: 16)))"
            if path == edgePath {
                expected["edge\(width)"] = last
            } else {
                expected["negative\(width)"] = width == 16 ? "-" + finite : width == 32 ? "((-\(finite)).bitPattern & 0xffffffff)" : "(-\(finite)).bitPattern"
                expected["nan\(width)"] = width == 16 ? "-" + nan : width == 32 ? "((-\(nan)).bitPattern & 0xffffffff)" : "(-\(nan)).bitPattern"
                expected["add\(width)"] = "(\(finite) + \(finite))"
                expected["convert\(width)"] = "\(width == 32 ? "Double" : "Float")(\(finite))"
                expected["last\(width)"] = last
                expected["mutable\(width)"] = "?"
            }
        }
        if path == edgePath {
            expected["edgeGPR32"] = "Float(bitPattern: 0xffc00002)"
            expected["edgeView64"] = String(Double(bitPattern: 0xffc00002))
        } else {
            expected["gpr32"] = "Float(bitPattern: 0xffc00002)"
            expected["raw32"] = "(0xffc00002 & 0xffffffff)"
        }
        for group in [listing, array, filtered, streamed, Array(each.values)] {
            for (name, expression) in expected.sorted(by: { $0.key < $1.key }) {
                let function = try #require(group.first { $0.displayName.hasPrefix("FPPools.\(name)(") })
                for text in [function.renderPseudo(), function.renderStructured()] {
                    let returns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("return ") }
                    #expect(returns == ["return " + expression], Comment(rawValue: text))
                }
            }
        }
    }
}

@Test func scalarPoolReaderUsesOnlyTheRequestedBackedBytesIfPresent() async throws {
    for path in [poolPath, edgePath] where FileManager.default.fileExists(atPath: path) {
      try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        let resolver = poolResolver(image)
        let functions = try await Disassembler().disassemble(path: path, functionFilter: "FPPools")
        for width in poolWidths {
            let name = (path == edgePath ? "edge" : "last") + String(width)
            let function = try #require(functions.first { $0.displayName.hasPrefix("FPPools.\(name)(") })
            let analysis = ValueTracer().analyze(function, entry: nil)
            let value = try #require(analysis.exitFloatValues[function.instructions.last!.address])
            let address: UInt64
            switch value {
            case .loaded(let at): address = at
            case .loadedBits(let at, let bytes): address = at; #expect(bytes == width / 8)
            default: Issue.record("Not a deferred load: \(value)"); continue
            }
            let section = try #require(image.sections64.first {
                $0.segmentName == "__TEXT" && $0.layout.addr <= address && address - $0.layout.addr < $0.layout.size
            })
            #expect(resolver.literalBits(at: address, bytes: width / 8) == poolLast(width))
            let end = section.layout.addr + section.layout.size
            #expect(resolver.literalBits(at: end - UInt64(width / 8) + 1, bytes: width / 8) == nil)
            if (path == edgePath && width == 32) || (path == poolPath && width == 16) {
                #expect(address + UInt64(width / 8) == end)
                #expect(resolver.literalWord(at: address) == nil)
            }
        }
        for count in [1, 3, 16] { #expect(resolver.literalBits(at: 0, bytes: count) == nil) }
        #expect(resolver.literalBits(at: .max, bytes: 8) == nil)
        let text = try #require(image.sections64.first { $0.sectionName == "__text" })
        #expect(resolver.literalWord(at: text.layout.addr) == nil)
      }
    }
}

@Test func scalarPoolLoadedBitsRemainRawUntilAnFPOperation() throws {
    let raw = AbstractValue.loadedBits(address: 0x1000, bytes: 4)
    #expect(TypeInference.typeOf(raw, arguments: [:]) == .unknown)
    #expect(ValueTracer.floatOperand(raw, bits: 32) == .unary(.floatConstant(bits: 32), raw))
    #expect(ValueTracer.floatOperand(.loaded(0x1000), bits: 64) == .unary(.floatConstant(bits: 64), .loaded(0x1000)))
    let snapshot = ProbeValue.abstractValue(raw)
    #expect(snapshot == .object(["schema": .label("swiftdc-value/1"), "expression": .object([
        "kind": .label("loaded-bits"), "address": .address(0x1000), "bytes": .int(4),
    ])]))
    // Narrow constants must keep their original rounding inside widening.
    #expect(Disassembler.renderFloatingConstant(bits: 0x3dcccccd, width: 32, explicitWidth: true) == "Float(0.1)")
    #expect(Disassembler.renderFloatingConstant(bits: 0x3dcccccd, width: 32) == "0.1")
}

#if arch(arm64)
@Test func scalarPoolNativeOracleChecksValuesAndMutableControlsIfPresent() throws {
    for path in [poolPath, edgePath] where FileManager.default.fileExists(atPath: path) {
        let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(handle) }
        func pointer(_ name: String, _ result: String) throws -> UnsafeMutableRawPointer {
            try #require(dlsym(handle, "$s7FPPools\(name.count)\(name)\(result)yF"))
        }
        func floating(_ name: String, _ width: Int) throws -> UInt64 {
            let p = try pointer(name, poolResult(width))
            switch width {
            case 64: return unsafeBitCast(p, to: (@convention(thin) () -> Double).self)().bitPattern
            case 32: return UInt64(unsafeBitCast(p, to: (@convention(thin) () -> Float).self)().bitPattern)
            default: return UInt64(unsafeBitCast(p, to: (@convention(thin) () -> Float16).self)().bitPattern)
            }
        }
        for width in poolWidths {
            if path == edgePath {
                #expect(try floating("edge\(width)", width) == poolLast(width))
                continue
            }
            for (name, bits) in [("negative", poolFinite(width)), ("nan", width == 64 ? UInt64(0x7ff8000000000001) : width == 32 ? 0x7fc00001 : 0x7e01)] {
                let actual: UInt64
                if width == 16 { actual = try floating(name + String(width), width) }
                else {
                    let p = try pointer(name + String(width), "s6UInt\(width)V")
                    actual = width == 64 ? unsafeBitCast(p, to: (@convention(thin) () -> UInt64).self)()
                        : UInt64(unsafeBitCast(p, to: (@convention(thin) () -> UInt32).self)())
                }
                #expect(actual == bits ^ poolSign(width))
            }
            #expect(try floating("add\(width)", width) == (width == 64 ? 0x4014000000000000 : width == 32 ? 0x3e4ccccd : 0x3266))
            #expect(try floating("convert\(width)", width == 32 ? 64 : 32) == (width == 32 ? 0x3fb99999a0000000 : width == 64 ? 0x40200000 : 0x3dccc000))
            #expect(try floating("last\(width)", width) == poolLast(width))
            let variable = try #require(dlsym(handle, "fpPoolMutable\(width)"))
            func store(_ bits: UInt64) {
                switch width {
                case 64: variable.storeBytes(of: bits, as: UInt64.self)
                case 32: variable.storeBytes(of: UInt32(bits), as: UInt32.self)
                default: variable.storeBytes(of: UInt16(bits), as: UInt16.self)
                }
            }
            defer { store(poolFinite(width)) }
            #expect(try floating("mutable\(width)", width) == poolFinite(width) ^ poolSign(width))
            store(poolFinite(width) ^ poolSign(width))
            #expect(try floating("mutable\(width)", width) == poolFinite(width))
        }
        if path == edgePath {
            #expect(try floating("edgeGPR32", 32) == poolLast(32))
            #expect(try floating("edgeView64", 64) == poolLast(32))
        } else {
            #expect(try floating("gpr32", 32) == poolLast(32))
            let p = try pointer("raw32", "s6UInt32V")
            #expect(UInt64(unsafeBitCast(p, to: (@convention(thin) () -> UInt32).self)()) == poolLast(32))
        }
    }
}
#endif
