import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `-f 0x<hex>` selects the function whose span holds the address, from its
/// first instruction or any later one; an address in no function selects
/// nothing.
@Test func anAddressFilterSelectsTheFunctionHoldingItIfPresent() async throws {
    let path = "Fixtures/Sample/libStaticText.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let report = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "StaticText.report")
    }
    let start = try #require(report.first?.startAddress)
    for address in [start, start + 8] {
        let found = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "0x" + String(address, radix: 16))
        }
        #expect(found.map(\.startAddress) == [start], "0x\(String(address, radix: 16))")
    }
    let none = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "0x7fffffff")
    }
    #expect(none.isEmpty)
}

/// A start LC_FUNCTION_STARTS marks over a table in `__text` is one function
/// at its own address on every path (`datastarts.s`): `mixed` (0x28c), whose
/// first word does not decode, and `table` (0x298), where nothing does.
/// The streaming path dropped `table`, an in-process decode ran `mixed` on
/// from the function before it, and a filter on `mixed` named it
/// `sub_290`.
@Test func aMarkedStartOverDataIsItsOwnFunctionIfPresent() async throws {
    let path = "Fixtures/Sample/libDataStarts.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreamingRender(machO: machO) { $0.renderPseudo() }
    }.joined(separator: "\n")
    #expect(streamed.contains("sub_298 {\n    \(DisassembledFunction.noDecodedInstructionNote)\n}"), Comment(rawValue: streamed))
    let whole = await withStableDependencies { await Disassembler().disassemble(machO: machO) }
    #expect(whole.map(\.startAddress) == [0x288, 0x28c, 0x298, 0x2a4], "\(whole.map(\.startAddress))")
    #expect(whole.first { $0.startAddress == 0x298 }?.instructions.isEmpty == true)
    for (filter, start) in [("0x28c", UInt64(0x28c)), ("0x290", 0x28c), ("0x298", 0x298)] {
        let found = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: filter)
        }
        #expect(found.map(\.startAddress) == [start], "\(filter): \(found.map(\.startAddress))")
    }
}
