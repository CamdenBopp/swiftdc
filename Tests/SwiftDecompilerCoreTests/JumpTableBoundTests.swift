import Ccapstone
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let boundFixture = "Fixtures/Sample/libJumpTableBounds.dylib"

/// Exercise both the whole-file objdump listing and filtered Capstone decode.
private func boundFunction(_ name: String, wholeFile: Bool) async throws -> DisassembledFunction? {
    guard FileManager.default.fileExists(atPath: boundFixture) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence,
                "Build Fixtures/Sample/libJumpTableBounds.dylib with Fixtures/Sample/build.sh")
        return nil
    }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(
            path: boundFixture, functionFilter: wholeFile ? nil : name)
    }
    return try #require(functions.first { $0.symbol == "_\(name)" })
}

/// CMP w0 proves only the low half. CSEL x0 and an x0-indexed load preserve and
/// read the upper half, so 0x100000001 passes the compare and escapes the table.
@Test(arguments: [false, true])
func hardenedTableDeclinesNarrowCompareWithWideIndexIfPresent(wholeFile: Bool) async throws {
    guard let function = try await boundFunction("jumpTableNarrowCompare", wholeFile: wholeFile) else { return }
    let compare = try #require(function.instructions.first?.detail)
    #expect(compare.operands.first?.operand.register?.widthBits == 32)
    #expect(function.switchTargets.isEmpty)
    let branch = try #require(function.instructions.first { $0.detail?.id == AARCH64_INS_BR })
    let block = try #require(function.basicBlocks().first { $0.instructions.last?.address == branch.address })
    #expect(block.successors.isEmpty)
    #expect(block.switchCases == nil)
    #expect(!function.renderStructured().contains("switch (?)"))
}

/// AAPCS does not preserve NZCV across a call. The fixture's callee sets LS
/// true, so the full index is selected even when it exceeded the prior bound.
@Test(arguments: [false, true])
func hardenedTableDeclinesCallClobberedClampFlagsIfPresent(wholeFile: Bool) async throws {
    guard let function = try await boundFunction("jumpTableClobberedFlags", wholeFile: wholeFile) else { return }
    #expect(function.instructions.contains { $0.controlFlow == .call })
    #expect(function.switchTargets.isEmpty)
    let branch = try #require(function.instructions.first { $0.detail?.id == AARCH64_INS_BR })
    let block = try #require(function.basicBlocks().first { $0.instructions.last?.address == branch.address })
    #expect(block.successors.isEmpty)
    #expect(block.switchCases == nil)
    #expect(!function.renderStructured().contains("switch (?)"))
}

/// SUBS sets flags from the pre-write index; selecting/loading its result is
/// not bounded by those flags. At input zero the result is UInt64.max.
@Test(arguments: [false, true])
func hardenedTableDeclinesCompareRewrittenIndexIfPresent(wholeFile: Bool) async throws {
    guard let function = try await boundFunction("jumpTableRewrittenClampIndex", wholeFile: wholeFile) else { return }
    #expect(function.instructions.first?.detail?.id == AARCH64_INS_SUBS)
    #expect(function.switchTargets.isEmpty)
}

/// The same destructive SUBS cannot prove the table index on B.HI fall-through.
@Test(arguments: [false, true])
func compressedTableDeclinesCompareRewrittenIndexIfPresent(wholeFile: Bool) async throws {
    guard let function = try await boundFunction("jumpTableRewrittenGuardIndex", wholeFile: wholeFile) else { return }
    #expect(function.instructions.first?.detail?.id == AARCH64_INS_SUBS)
    #expect(function.switchTargets.isEmpty)
}

/// Full-width CMP is sufficient, as is a narrow CMP when UXTW makes the load
/// read only that half. Rechecking after a call restores valid clamp flags.
@Test(arguments: [false, true])
func jumpTablesAcceptSufficientBoundsIfPresent(wholeFile: Bool) async throws {
    for name in ["jumpTableWideCompare", "jumpTableNarrowLoad", "jumpTableRecheckedFlags",
                 "jumpTableSeparateClampResult", "jumpTableSeparateGuardResult"] {
        guard let function = try await boundFunction(name, wholeFile: wholeFile) else { return }
        let table = try #require(function.switchTargets.values.first, "No proven table in \(name)")
        #expect(table.count == 2)
        #expect(Set(table).count == 2)
        let block = try #require(function.basicBlocks().first { $0.switchCases != nil })
        #expect(block.successors == table)
        #expect(function.renderStructured().contains("switch (?)"))
    }
}
