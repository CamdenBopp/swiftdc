import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func ownershipSummary(saveOffset: Int64, store: UInt32) throws -> CalleeRegisterSummary {
    let displacement = UInt32(truncatingIfNeeded: saveOffset) & 0x1ff
    let words: [UInt32] = [0xf80003f3 | (displacement << 12), 0xaa1f03f3,
                           store, 0xf84003f3 | (displacement << 12), 0xd65f03c0]
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let function = DisassembledFunction(symbol: "_frameOwnership", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
    return try #require(CalleeRegisterSummary.of(function))
}

@Test func abiUnknownCallsCannotPreserveCallerOwnedSaves() throws {
    // The incoming pointer can already address caller-owned memory. An
    // unknown helper may write through it without a new local pointer escape.
    for offset: Int64 in [0, 16, -4, -7] {
        #expect(try ownershipSummary(saveOffset: offset, store: 0x94000010).clobberedCalleeSaved == ["x19"])
    }
    for offset: Int64 in [-8, -16] {
        #expect(try ownershipSummary(saveOffset: offset, store: 0x94000010).clobberedCalleeSaved.isEmpty)
    }
}

@Test func abiUnknownPointerWritesCannotPreserveCallerOwnedSaves() throws {
    // Incoming x0 can reach caller-owned memory even when no pointer escapes
    // from the fragment itself. Both supported STR and unmodelled STLR write it.
    for store: UInt32 in [0xf9000001, 0xc89ffc01] { // str / stlr x1,[x0]
        for offset: Int64 in [0, 16, -4, -7] {
            #expect(try ownershipSummary(saveOffset: offset, store: store).clobberedCalleeSaved == ["x19"],
                    Comment(rawValue: "offset=\(offset), store=\(String(store, radix: 16))"))
        }
        // [entrySP-8, entrySP) is wholly below entry SP, including its boundary.
        // Existing nonescaping ABI-owned save assumptions remain in force.
        for offset: Int64 in [-8, -16] {
            #expect(try ownershipSummary(saveOffset: offset, store: store).clobberedCalleeSaved.isEmpty)
        }
    }
}

private let ownershipFixture = "Fixtures/Sample/libABIFrameOwnership.dylib"

@Test func abiFrameOwnershipNativeOracleIfPresent() throws {
    guard FileManager.default.fileExists(atPath: ownershipFixture) else { return }
    let handle = try #require(dlopen(ownershipFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    for name in ["8positive", "8straddle", "8callthru", "5owned"] {
        let pointer = try #require(dlsym(handle, "$s8ABIFrame\(name)yS2i_SitF"))
        let function = unsafeBitCast(pointer, to: (@convention(thin) (Int, Int) -> Int).self)
        for seed: UInt in [0, 0x1122334455667788, .max, 1 << 63] {
            for replacement: UInt in [0, 0xaa, 0xaabbccdd00112233, .max] {
                let expected: UInt
                switch name {
                case "8positive", "8callthru": expected = replacement
                case "8straddle": expected = (seed & 0xffffffff) | ((replacement & 0xffffffff) << 32)
                default: expected = seed
                }
                #expect(UInt(bitPattern: function(Int(bitPattern: seed), Int(bitPattern: replacement))) == expected,
                        Comment(rawValue: name))
            }
        }
    }
}

@Test func abiFrameOwnershipCallersDeclineChangedResultsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: ownershipFixture) else { return }
    for filter: String? in [nil, "ABIFrame"] {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: ownershipFixture, functionFilter: filter)
        }
        let callers = functions.filter { $0.displayName.hasPrefix("ABIFrame.") }
        #expect(callers.count == 4)
        for function in callers {
            let control = function.displayName.contains(".owned(")
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains(control ? "return arg0" : "return ?"), Comment(rawValue: text))
                if !control { #expect(!text.contains("return arg0"), Comment(rawValue: text)) }
            }
        }
    }
}
