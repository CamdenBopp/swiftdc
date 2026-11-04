import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func fpAliasFunction(_ words: [UInt32], at address: UInt64 = 0x1000) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(bytes, address: address)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_OUTLINED_FUNCTION_FP", demangledName: nil,
        startAddress: address, instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

private func fpAliasSummary(_ words: [UInt32], imported: Bool, arity: Int? = nil) throws -> CalleeRegisterSummary {
    let call: UInt32 = imported ? 0x94000400 : 0xd63f0200
    let body = try fpAliasFunction(words.map { $0 == 0xd63f0200 ? call : $0 })
    return try #require(CalleeRegisterSummary.of(body, calleeArity: { _ in arity },
                                                isImportStub: { _ in imported }))
}

private func fpAliasWords(register: Int) -> [UInt32] {
    // Save x19/lr; put the saved-slot address in dN; clear x0; call; reload.
    // The private outlined fragment need not preserve x19. Its callback does
    // obey AAPCS64: double arguments use d0-d7.
    [0xa9bf7bf3, 0x910003e0, 0x9e670000 | UInt32(register), 0xaa1f03e0,
     0xd63f0200, 0xa8c17bf3, 0xd65f03c0]
}

@Test func fpArgumentAliasesInvalidateUnknownABICallSavedSlots() throws {
    for imported in [false, true] {
        for register in 0...7 {
            #expect(try fpAliasSummary(fpAliasWords(register: register), imported: imported)
                .clobberedCalleeSaved.contains("x19"))
        }
    }
}

@Test func vectorUpperArgumentAliasesInvalidateUnknownABICallSavedSlots() throws {
    // A short-vector parameter, not a double, consumes the high lane.
    // clang emits MOV X8,V0.D[1] in such a callback.
    let words: [UInt32] = [0xa9bf7bf3, 0x910003e0, 0x6f00e400, 0x4e181c00,
                            0xaa1f03e0, 0xd63f0200, 0xa8c17bf3, 0xd65f03c0]
    for imported in [false, true] {
        #expect(try fpAliasSummary(words, imported: imported).clobberedCalleeSaved.contains("x19"))
    }
}

@Test func fpArgumentAliasesSurviveControlFlowJoins() throws {
    // d0 is either the saved-slot pointer or 1.0. A lost must-value is not
    // evidence that the pointer cannot reach the callback on one path.
    let words: [UInt32] = [0xa9bf7bf3, 0xb4000081, 0x910003e0, 0x9e670000,
                            0x14000002, 0x1e6e1000, 0xaa1f03e0, 0xd63f0200,
                            0xa8c17bf3, 0xd65f03c0]
    for imported in [false, true] {
        #expect(try fpAliasSummary(words, imported: imported).clobberedCalleeSaved.contains("x19"))
    }
}

@Test func integerOnlyCallsAndNonargumentVectorsDoNotEscapeFPAliases() throws {
    // knownCArity is only a GPR-only signature. A fake integer arity for a
    // double callback would be invalid ABI evidence, so do not use one.
    #expect(DisassembledFunction.cPrototype(of: "sin")?.parameters == ["d"])
    #expect(DisassembledFunction.knownCArity(of: "sin") == nil)
    for arity in 0...8 {
        for register in 0...7 {
            #expect(try fpAliasSummary(fpAliasWords(register: register), imported: true, arity: arity)
                .clobberedCalleeSaved.contains("x19") == false)
        }
    }
    for imported in [false, true] {
        for register in 8...31 {
            #expect(try fpAliasSummary(fpAliasWords(register: register), imported: imported)
                .clobberedCalleeSaved.contains("x19") == false)
        }
    }
}

@Test func fpArgumentAliasesKeepProvenDisjointLocalBounds() throws {
    // 48-byte frame: local at sp, x19/lr saved at sp+32. The callback may
    // change the local, but that bounded escape does not reach the save.
    let direct: [UInt32] = [0xd100c3ff, 0xa9027bf3, 0x910003e0, 0x9e670000,
                             0xaa1f03e0, 0xd63f0200, 0xa9427bf3, 0x9100c3ff, 0xd65f03c0]
    let joined: [UInt32] = [0xd100c3ff, 0xa9027bf3, 0xb4000081, 0x910003e0, 0x9e670000,
                             0x14000002, 0x1e6e1000, 0xaa1f03e0, 0xd63f0200,
                             0xa9427bf3, 0x9100c3ff, 0xd65f03c0]
    for imported in [false, true] {
        for words in [direct, joined] {
            #expect(try fpAliasSummary(words, imported: imported).clobberedCalleeSaved.isEmpty)
        }
    }
}

@Test func fpAliasConsumersHaveRealCompilerParameterBanks() throws {
    // clang -O2 emits these from poke_bits(double) and poke_eighth(...,double).
    for register in [0, 7] {
        let body = try fpAliasFunction([0x9e660008 | UInt32(register << 5),
                                        0x52800c69, 0xf9000109, 0xd65f03c0])
        let summary = try #require(CalleeRegisterSummary.of(body))
        #expect(summary.provenFloatArgumentReads == [register])
        #expect(summary.floatArgumentWidths[register] == 64)
        #expect(summary.provenArgumentReads.isEmpty)
    }
}

@Test func anFPCallbackCannotLeaveTheCallersSavedRegisterStale() throws {
    let callee = try fpAliasSummary(fpAliasWords(register: 0), imported: false)
    let caller = try fpAliasFunction([0xd28000f3, 0x940003ff, 0xaa1303e0, 0xd65f03c0])
    #expect(ValueTracer().analyze(caller, entry: nil).exitValues[0x100c] == .immediate(7))
    var tracer = ValueTracer()
    tracer.calleeClobbers[0x2000] = callee.clobberedCalleeSaved
    #expect(tracer.analyze(caller, entry: nil).exitValues[0x100c] == nil)
}

private let fpAliasFixture = "Fixtures/Sample/libFPAlias.dylib"

@Test func fpArgumentAliasesAreNotFabricatedInWholeOrFilteredOutputIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fpAliasFixture) else { return }
    for filter: String? in [nil, "FPAlias"] {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: fpAliasFixture, functionFilter: filter)
        }
        for name in ["indirect", "upper"] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("FPAlias.\(name)(") })
            let text = function.renderStructured()
            #expect(text.contains("return ?"), Comment(rawValue: text))
            #expect(!text.contains("return 7"), Comment(rawValue: text))
        }
    }
}

/// The fixture run on this machine: the callback really does write the save.
@Test func fpArgumentAliasNativeOracleIfPresent() throws {
    #if arch(arm64)
    guard FileManager.default.fileExists(atPath: fpAliasFixture) else { return }
    let handle = try #require(dlopen(fpAliasFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    for symbol in ["$s7FPAlias8indirectSiyF", "$s7FPAlias5upperSiyF"] {
        let pointer = try #require(dlsym(handle, symbol))
        #expect(unsafeBitCast(pointer, to: (@convention(c) () -> Int).self)() == 99)
    }
    #endif
}

@Test func aCallEndsWhatAnArgumentVectorMayAlias() throws {
    // The slot's address reaches d0, then an integer-only call clobbers d0.
    // The indirect call after it gets no frame address, so x19 stays proven.
    let words: [UInt32] = [0xa9bf7bf3, 0x910003e0, 0x9e670000, 0xaa1f03e0,
                           0x94000400, 0xd63f0200, 0xa8c17bf3, 0xd65f03c0]
    let body = try fpAliasFunction(words)
    let summary = try #require(CalleeRegisterSummary.of(body, calleeArity: { _ in 0 }, isImportStub: { _ in true }))
    #expect(!summary.clobberedCalleeSaved.contains("x19"))
}

@Test func aVectorWriteEndsWhatTheRegisterMayAlias() throws {
    // `movi v0.2d, #0` replaces the address before the call.
    let words: [UInt32] = [0xa9bf7bf3, 0x910003e0, 0x9e670000, 0x6f00e400,
                           0xaa1f03e0, 0xd63f0200, 0xa8c17bf3, 0xd65f03c0]
    #expect(try !fpAliasSummary(words, imported: false).clobberedCalleeSaved.contains("x19"))
}

@Test func anSVEWriteOfAFrameAddressReachesTheVectorBank() throws {
    // `mov z0.d, x0`: v0 is z0's low 128 bits, so the address is an argument.
    let words: [UInt32] = [0xa9bf7bf3, 0x910003e0, 0x05e03800,
                           0xaa1f03e0, 0xd63f0200, 0xa8c17bf3, 0xd65f03c0]
    #expect(try fpAliasSummary(words, imported: false).clobberedCalleeSaved.contains("x19"))
}
