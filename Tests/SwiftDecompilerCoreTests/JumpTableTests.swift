import Testing
import Foundation
@testable import SwiftDecompilerCore
import Ccapstone

/// A `br xN` had no successors, so a jump table's arms were orphaned from the
/// CFG: `pickByte` rendered nine `// continues at` lines and no case bodies.
/// LLVM's compressed table (`adrp; add; adr; ldrb|ldrh; add; br`) is now
/// recovered where its `cmp; b.hi` guard proves the bound.
private let fixture = "Fixtures/Sample/libSwitches.dylib"

private func function(_ name: String) async throws -> DisassembledFunction? {
    guard FileManager.default.fileExists(atPath: fixture) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: name)
    }
    return functions.first { $0.symbol == "_\(name)" }
}

@Test func byteAndHalfwordTablesAreRecoveredIfPresent() async throws {
    guard let pickByte = try await function("pickByte"),
          let pickHalf = try await function("pickHalf")
    else { return }
    let byteTable = try #require(pickByte.switchTargets.values.first, "no table in pickByte")
    #expect(byteTable.count == 10)
    // case 7's body is case 0's, so clang points both entries at one arm.
    #expect(byteTable[0] == byteTable[7])
    #expect(Set(byteTable).count == 9)

    let halfTable = try #require(pickHalf.switchTargets.values.first, "no table in pickHalf")
    #expect(halfTable.count == 10)
    #expect(Set(halfTable).count == 10)
    // Halfword entries: some arm sits beyond a byte entry's reach (255 * 4).
    let anchor = halfTable.min()!
    #expect(halfTable.contains { $0 - anchor > 255 * 4 })

    let text = pickByte.renderStructured()
    #expect(text.contains("switch (?) {"), "\(text)")
    #expect(text.contains("case 0, 7:"), "\(text)")
}

/// arm64e's hardened form: the index is clamped by `csel …, ls` in the table
/// block and the entries are signed 32-bit offsets. Same switches, same shape.
@Test func hardenedTablesAreRecoveredIfPresent() async throws {
    let path = "Fixtures/Sample/libSwitches.arm64e.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for name in ["pickByte", "pickHalf"] {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: path, functionFilter: name)
        }
        let function = try #require(functions.first { $0.symbol == "_\(name)" })
        let table = try #require(function.switchTargets.values.first, "no hardened table in \(name)")
        #expect(table.count == 10, "\(name)")
        if name == "pickByte" { #expect(table[0] == table[7] && Set(table).count == 9) }
        else { #expect(Set(table).count == 10) }
    }
}

@Test func aTableWithoutItsGuardIsDeclinedIfPresent() async throws {
    guard let pickByte = try await function("pickByte") else { return }
    let machO = try BinaryLoader.load(path: fixture)
    #expect(!JumpTables.recognize(in: pickByte, machO: machO).isEmpty)
    // Without `b.hi` nothing bounds the index: the entry count is unknown.
    let unguarded = pickByte.replacingInstructions(pickByte.instructions.filter {
        $0.detail?.conditionCode != AArch64CC_HI
    })
    #expect(JumpTables.recognize(in: unguarded, machO: machO).isEmpty)
}
