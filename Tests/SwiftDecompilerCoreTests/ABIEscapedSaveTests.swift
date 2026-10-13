import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func escapedSaveSummary(_ words: [UInt32]) throws -> CalleeRegisterSummary {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let function = DisassembledFunction(symbol: "_escapedSave", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
    return try #require(CalleeRegisterSummary.of(function))
}

@Test func abiSavePointersPassedToCallsInvalidateRestorationProofs() throws {
    // STP x19,x30,[sp,#-16]!; MOV x19,xzr; MOV x0,sp; BL external;
    // LDP x19,x30,[sp],#16; RET. The callee may write through x0.
    #expect(try escapedSaveSummary([
        0xa9bf7bf3, 0xaa1f03f3, 0x910003e0, 0x94000010, 0xa8c17bf3, 0xd65f03c0,
    ]).clobberedCalleeSaved == ["x19"])
    // Standard frame bookkeeping and an ordinary call preserve the proof.
    #expect(try escapedSaveSummary([
        0xa9bf7bf3, 0x910003fd, 0xaa1f03f3, 0x94000010, 0xa8c17bf3, 0xd65f03c0,
    ]).clobberedCalleeSaved == ["x29"])
}

@Test func abiSavePointerEscapesPersistBeforeAndAfterSaveCreation() throws {
    // The frame pointer is stored through an incoming pointer, then x9 dies.
    // A later call can reload the escaped address even without an outgoing alias.
    for prefix: [UInt32] in [
        [0xd10083ff, 0x910003e9, 0xf9000009, 0xaa1f03e9, 0xf90003f3],
        [0xd10083ff, 0xf90003f3, 0x910003e9, 0xf9000009, 0xaa1f03e9],
    ] {
        #expect(try escapedSaveSummary(prefix + [
            0xaa1f03f3, 0x94000010, 0xf94003f3, 0x910083ff, 0xd65f03c0,
        ]).clobberedCalleeSaved == ["x19"])
    }
    // A first call may retain the pointer before any save exists. A later
    // call can then modify a newly created save without a live register alias.
    #expect(try escapedSaveSummary([
        0xd10083ff, 0x910003e0, 0x94000010, 0xf90003f3, 0xaa1f03f3,
        0x94000010, 0xf94003f3, 0x910083ff, 0xd65f03c0,
    ]).clobberedCalleeSaved == ["x19"])
    // Even without a call, an unknown pointer can reload the escaped address.
    #expect(try escapedSaveSummary([
        0xd10083ff, 0xf90003f3, 0x910003e9, 0xf9000009, 0xaa1f03e9,
        0xaa1f03f3, 0xf9000141, 0xf94003f3, 0x910083ff, 0xd65f03c0,
    ]).clobberedCalleeSaved == ["x19"])
}

@Test func abiSavePointerMayAliasesSurviveJoinsAndUnsupportedOffsets() throws {
    // On one branch x9 is the frame; on the other it is an incoming pointer.
    // The joined must-value is unknown, but the feasible frame alias remains.
    #expect(try escapedSaveSummary([
        0xf81e0ff3, 0xaa1f03f3, 0x910003e9, 0xb4000040, 0xaa0203e9,
        0xf9000121, 0xf84207f3, 0xd65f03c0,
    ]).clobberedCalleeSaved == ["x19"])
    // Register-indexed ADD is not an exact offset this summary can model.
    #expect(try escapedSaveSummary([
        0xf81e0ff3, 0xaa1f03f3, 0x910003e9, 0x8b020129,
        0xf9000121, 0xf84207f3, 0xd65f03c0,
    ]).clobberedCalleeSaved == ["x19"])
}

private let escapedSaveFixture = "Fixtures/Sample/libABIEscapedSaves.dylib"
private let escapedSaveFunctions = [("7escaped", true), ("6before", true), ("6merged", true),
                                    ("6offset", true), ("6stored", true), ("7control", false)]

@Test func abiEscapedSaveNativeOracleIfPresent() throws {
    guard FileManager.default.fileExists(atPath: escapedSaveFixture) else { return }
    let handle = try #require(dlopen(escapedSaveFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    for (name, replaced) in escapedSaveFunctions {
        let pointer = try #require(dlsym(handle, "$s8ABIAlias\(name)yS2i_SitF"))
        let function = unsafeBitCast(pointer, to: (@convention(thin) (Int, Int) -> Int).self)
        for seed: UInt in [0, 0x1122334455667788, .max, 1 << 63] {
            for replacement: UInt in [0, 0xaa, 0xaabbccdd00112233, .max] {
                #expect(UInt(bitPattern: function(Int(bitPattern: seed), Int(bitPattern: replacement)))
                    == (replaced ? replacement : seed), Comment(rawValue: name))
            }
        }
    }
}

@Test func abiEscapedSaveCallersDeclineChangedResultsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: escapedSaveFixture) else { return }
    for filter: String? in [nil, "ABIAlias"] {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: escapedSaveFixture, functionFilter: filter)
        }
        let callers = functions.filter { $0.displayName.hasPrefix("ABIAlias.") }
        #expect(callers.count == 6)
        for function in callers {
            let control = function.displayName.contains(".control(")
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains(control ? "return arg0" : "return ?"), Comment(rawValue: text))
                if !control { #expect(!text.contains("return arg0"), Comment(rawValue: text)) }
            }
        }
    }
}
