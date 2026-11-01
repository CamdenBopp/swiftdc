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
