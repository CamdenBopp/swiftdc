import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let callForwardInputImages = [
    "Fixtures/Sample/libCallForwardInputs.dylib",
    "Fixtures/Sample/libCallForwardInputs.stripped.dylib",
]

private let callForwardInputNativePrograms = [
    "Fixtures/Sample/bl-call-input-O0-oracle",
    "Fixtures/Sample/bl-call-input-O2-oracle",
    "Fixtures/Sample/bl-call-input-Os-oracle",
]

private enum ForwardedInputContract { case opaque, empty, oneProvedWord, mixedUnknownPosition }

@Test func ordinaryBLGPForwardersKeepUnknownInputArityIfPresent() async throws {
    try await requireOrdinaryBLInputContracts([
        ("caller", .opaque), ("liveGPCaller", .opaque), ("sparseGPCaller", .opaque),
        ("zeroGPCaller", .empty), ("overwriteGPCaller", .empty), ("resultGPCaller", .empty),
        ("canonicalGPCaller", .oneProvedWord),
    ])
}

@Test func ordinaryBLFPForwardersKeepUnknownInputArityIfPresent() async throws {
    try await requireOrdinaryBLInputContracts([
        ("fpCaller", .opaque), ("liveFPCaller", .opaque), ("sparseFPCaller", .opaque),
        ("zeroFPCaller", .empty), ("overwriteFPCaller", .empty), ("resultFPCaller", .empty),
        ("canonicalFPCaller", .oneProvedWord),
    ])
}

@Test func ordinaryBLMixedForwardersDeclineUnprovedInputOrderIfPresent() async throws {
    try await requireOrdinaryBLInputContracts([
        ("mixedCaller", .mixedUnknownPosition), ("liveMixedCaller", .mixedUnknownPosition),
    ])
}

private func requireOrdinaryBLInputContracts(_ entries: [(String, ForwardedInputContract)]) async throws {
    for path in callForwardInputImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        // Choose exact entries from independent binary symbols, including in
        // the locally stripped image. No preliminary SUT analysis selects them.
        let contracts = try Dictionary(uniqueKeysWithValues: entries.map { name, contract in
            (UInt64(try #require(image.symbols.first { $0.name == "_sub_BLInput_" + name }).offset), contract)
        })
        let starts = Set(contracts.keys)
        for stage in 0..<5 {
            let functions: [DisassembledFunction] = try await withStableDependencies {
                switch stage {
                case 0:
                    return try await Disassembler().disassemble(path: path)
                case 1:
                    return await Disassembler().disassemble(machO: image)
                case 2:
                    return try await Disassembler().disassemble(path: path, functionFilter: "sub_BLInput_")
                case 3:
                    let selected: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                        machO: image, transform: { starts.contains($0.startAddress) ? $0 : nil })
                    return selected.compactMap { $0 }
                default:
                    let selected = await Disassembler().analyzeEachFunction(
                        at: starts, in: image, transform: { $0 })
                    return Array(selected.values)
                }
            }
            for start in starts.sorted() {
                let caller = try #require(functions.first { $0.startAddress == start })
                let call = try #require(caller.instructions.first { $0.controlFlow == .call })
                // A valid LR-only wrapper consumes an incoming GP or FP word
                // through BL. That establishes no concrete source count, but
                // an absent snapshot must not turn it into an empty list.
                let note = Comment(rawValue: "stage \(stage), \(path): " + caller.renderStructured())
                switch try #require(contracts[start]) {
                case .opaque:
                    #expect(call.callArguments == ["…"], note)
                    for text in [caller.renderStructured(), caller.renderPseudo()] {
                        // An unnamed target can use the raw recovered_args spelling.
                        #expect(text.contains("…"), Comment(rawValue: text))
                        #expect(!text.contains("recovered_args: []"), Comment(rawValue: text))
                    }
                case .empty:
                    #expect(call.callArguments == nil, note)
                case .oneProvedWord:
                    #expect(call.callArguments == ["?"], note)
                case .mixedUnknownPosition:
                    #expect(call.callArguments == ["?", "…"], note)
                }
            }
        }
    }
}

@Test func nativeBLForwardedGPAndFPInputsAgreeAtEveryOptimizationLevelIfPresent() throws {
    for path in callForwardInputNativePrograms {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, Comment(rawValue: text))
        #expect(text.contains("PASS 65 native GP/FP BL-forwarded input observations"), Comment(rawValue: text))
    }
}

@Test func pendingOrdinaryCallGPAndFPBanksStayIndependentAndInline() {
    let gpMasks: [UInt32] = [0, 1, 0xff, (1 << 29) | (1 << 22) | (1 << 20)]
    let fpMasks: [UInt8] = [0, 1, 0x80, 0xff]
    for gp in gpMasks {
        for fp in fpMasks {
            let read = CalleeRegisterSummary.PendingRead(target: 0x3000, unwritten: gp,
                unwrittenRegisters: 0x12345678, unwrittenFloatArguments: fp)
            #expect(read.unwritten == gp)
            #expect(read.unwrittenFloatArguments == fp)
            #expect(read.unwrittenRegisters == 0x12345678)
        }
    }
    #expect(MemoryLayout<CalleeRegisterSummary.PendingRead>.stride == 16)
}

@Test func ordinaryBLFloatingUncertaintyClosesOnItsOwnAndSurvivesCopies() throws {
    // Only the FP bit changes: the opaque flag and all GP facts start closed.
    // Address order visits the outer caller before its provider. This must
    // requeue callers even when no GP mask or source-count flag changes.
    let leaf = CalleeRegisterSummary(argumentReads: [], provenFloatArgumentReads: [7],
        floatArgumentWidths: [7: 64], clobberedCalleeSaved: [])
    func relay(_ target: UInt64, fp: UInt8 = 0x80) -> CalleeRegisterSummary {
        CalleeRegisterSummary(argumentReads: [], pendingReads: [
            .init(target: target, unwritten: 0, unwrittenRegisters: 0, unwrittenFloatArguments: fp),
        ], clobberedCalleeSaved: [], hasOpaqueInputTransfer: true)
    }
    var summaries: [UInt64: CalleeRegisterSummary] = [
        0x1000: relay(0x2000), 0x2000: relay(0x3000), 0x3000: leaf,
        0x4000: relay(0x3000, fp: 0),
    ]
    CalleeRegisterSummary.closeOverReads(&summaries)
    for start: UInt64 in [0x1000, 0x2000] {
        let value = try #require(summaries[start])
        #expect(value.mayReadFloatArguments == 0x80)
        #expect(value.provenFloatArgumentReads.isEmpty && value.floatArgumentWidths.isEmpty)
        #expect(value.argumentReads.isEmpty && value.provenArgumentReads.isEmpty)
        #expect(value.pendingReads.isEmpty)
        #expect(value.claimingNothing().mayReadFloatArguments == 0x80)
    }
    #expect(summaries[0x4000]?.mayReadFloatArguments == 0)
    let closed = summaries
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries == closed)
    for capped in [false, true] {
        var copied = closed
        // Explicitly schedule the relays: an empty worklist would make both
        // the rebuild and cap assertions pass without exercising either path.
        for start: UInt64 in [0x1000, 0x2000] { copied[start]?.needsEntryPreservation = true }
        var rebuiltEntries: [UInt64] = []
        // A preservation rebuild is deliberately empty of read facts. The
        // closed MAY evidence belongs to the immutable original body.
        CalleeRegisterSummary.closeOverCalls(&copied, cap: capped ? 0 : 128,
            recompute: { start, _, _, _ in
                rebuiltEntries.append(start)
                return CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [])
            })
        #expect(rebuiltEntries == (capped ? [] : [0x1000, 0x2000]))
        for start: UInt64 in [0x1000, 0x2000] {
            #expect(copied[start]?.mayReadFloatArguments == 0x80)
            #expect(copied[start]?.provenFloatArgumentReads.isEmpty == true)
        }
        let facts = CalleeRegisterFacts.finish(&copied).facts
        for start: UInt64 in [0x1000, 0x2000] {
            #expect(facts[start]?.mayReadFloatArguments == 0x80)
            #expect(facts[start]?.provenFloatArgumentReads.isEmpty == true)
        }
    }
}

@Test func ordinaryBLFloatingCyclesNeedAFiniteReadAndRespectOverwrites() {
    func relay(_ target: UInt64, fp: UInt8 = 0xff) -> CalleeRegisterSummary {
        CalleeRegisterSummary(argumentReads: [], pendingReads: [
            .init(target: target, unwritten: 0, unwrittenRegisters: 0, unwrittenFloatArguments: fp),
        ], clobberedCalleeSaved: [])
    }
    var cycle: [UInt64: CalleeRegisterSummary] = [0x1000: relay(0x2000), 0x2000: relay(0x1000)]
    CalleeRegisterSummary.closeOverReads(&cycle)
    #expect(cycle.values.allSatisfy { $0.mayReadFloatArguments == 0 && $0.provenFloatArgumentReads.isEmpty && !$0.hasOpaqueInputTransfer })

    var grounded: [UInt64: CalleeRegisterSummary] = [
        0x1000: relay(0x2000), 0x2000: relay(0x1000),
        0x3000: CalleeRegisterSummary(argumentReads: [], provenFloatArgumentReads: [3], clobberedCalleeSaved: []),
        0x4000: relay(0x2000, fp: 0),
    ]
    grounded[0x2000]?.pendingReads.append(
        .init(target: 0x3000, unwritten: 0, unwrittenRegisters: 0, unwrittenFloatArguments: 0x08))
    CalleeRegisterSummary.closeOverReads(&grounded)
    #expect(grounded[0x1000]?.mayReadFloatArguments == 0x08)
    #expect(grounded[0x2000]?.mayReadFloatArguments == 0x08)
    #expect(grounded[0x4000]?.mayReadFloatArguments == 0)
    #expect(grounded[0x1000]?.hasOpaqueInputTransfer == true)
    #expect(grounded[0x2000]?.hasOpaqueInputTransfer == true)
    #expect(grounded[0x4000]?.hasOpaqueInputTransfer == false)
    #expect(grounded[0x1000]?.provenFloatArgumentReads.isEmpty == true)
    #expect(grounded[0x2000]?.provenFloatArgumentReads.isEmpty == true)
    var missing: [UInt64: CalleeRegisterSummary] = [0x1000: relay(0x7000, fp: 0x80)]
    CalleeRegisterSummary.closeOverReads(&missing)
    #expect(missing[0x1000]?.mayReadFloatArguments == 0x80)
    #expect(missing[0x1000]?.hasOpaqueInputTransfer == true)
    #expect(missing[0x1000]?.provenFloatArgumentReads.isEmpty == true)
}

@Test func ordinaryBLFloatingReadsSurvivePreservationReanalysis() throws {
    let engine = try #require(CapstoneEngine())
    // fadd d0,d7,d7; ret. The same immutable body is analysed once for
    // reads and then again for preservation with its read pass disabled.
    let words: [UInt32] = [0x1e6728e0, 0xd65f03c0]
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let instructions = engine.disassemble(bytes, address: 0x8000).map(Disassembler.instruction(decoded:))
    let function = DisassembledFunction(symbol: "sub_BLInput_preservationLeaf", demangledName: nil,
        startAddress: 0x8000, instructions: instructions, source: .symbol)
    let original = try #require(CalleeRegisterSummary.of(function))
    #expect(original.mayReadFloatArguments == 0x80)
    #expect(original.provenFloatArgumentReads == [7])
    for reuse in [false, true] {
        let rebuilt = try #require(CalleeRegisterSummary.recomputingPreservation(
            function, retainingReadsFrom: original, reusingPreservation: reuse,
            calleeEffects: { _ in CalleeEffect() }))
        #expect(rebuilt.mayReadFloatArguments == 0x80)
        #expect(rebuilt.provenFloatArgumentReads == [7])
        #expect(rebuilt.floatArgumentWidths == original.floatArgumentWidths)
    }
}

@Test func ordinaryBLHelperPointerPositionsRequireUnambiguousCompilerSymbols() {
    let symbols = ["_$s2HS2AOVWOc": "outlined init with copy of HS.AO",
                   "_$s2HS2AOVWOf": "outlined assign with copy of HS.AO",
                   "___swift_assign_boxed_opaque_existential_1": "__swift_assign_boxed_opaque_existential_1"]
    for (symbol, name) in symbols {
        #expect(DisassembledFunction.compilerHelperGPInputPrefix(symbol: symbol, printedName: name) == 2)
        #expect(DisassembledFunction.compilerHelperGPInputPrefix(symbol: symbol, printedName: name + " fake") == nil)
        #expect(DisassembledFunction.compilerHelperGPInputPrefix(symbol: "not_a_helper", printedName: name) == nil)
        let labels: [UInt64: String] = [0x1000: symbol]
        let names: [UInt64: String] = [0x1000: name]
        #expect(Disassembler.ReferenceResolver.compilerHelperGPInputPrefixes(labels: labels, names: names, folded: [:]) == [0x1000: 2])
        #expect(Disassembler.ReferenceResolver.compilerHelperGPInputPrefixes(labels: labels, names: names,
            folded: [0x1000: [name, "incompatible alias"]]).isEmpty)
    }
    #expect(DisassembledFunction.compilerHelperGPInputPrefix(
        symbol: "_swift_willThrowTyped", printedName: "swift_willThrowTyped") == 3)
    #expect(DisassembledFunction.compilerHelperGPInputPrefix(
        symbol: "_swift_willThrowTyped", printedName: "swift_willThrowTyped changed") == nil)
    for (symbol, name) in [
        ("_$s2HS2AOVWOcTm", "merged outlined init with copy of HS.AO"),
        ("_$s2HS2AOVWOh", "outlined destroy of HS.AO"),
        ("___swift_assign_boxed_opaque_existential_1junk", "__swift_assign_boxed_opaque_existential_1junk"),
        ("___swift_assign_boxed_opaque_existential_", "__swift_assign_boxed_opaque_existential_"),
    ] {
        #expect(DisassembledFunction.compilerHelperGPInputPrefix(symbol: symbol, printedName: name) == nil)
    }
}

@Test func ordinaryBLCompilerHelpersKeepProvedPointerPositionsAcrossPipelinesIfPresent() async throws {
    let entries = ["_$s2HS1HC5setAOyyAA0C0VF", "_$s2HS6copyAOyAA0C0VADF",
                   "_$s2HS11assignShapeyyAA0C0_pz_AaC_ptF"]
    for path in ["Fixtures/Sample/libHiddenStore.Onone.dylib", "Fixtures/Sample/libHiddenStore.O.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let starts = try Set(entries.map { name in
            UInt64(try #require(image.symbols.first { $0.name == name }).offset)
        })
        for stage in 0..<5 {
            let functions: [DisassembledFunction] = try await withStableDependencies {
                switch stage {
                case 0: return try await Disassembler().disassemble(path: path)
                case 1: return await Disassembler().disassemble(machO: image)
                case 2: return try await Disassembler().disassemble(path: path, functionFilter: "HS.")
                case 3:
                    let selected: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                        machO: image, transform: { starts.contains($0.startAddress) ? $0 : nil })
                    return selected.compactMap { $0 }
                default:
                    return Array(await Disassembler().analyzeEachFunction(at: starts, in: image, transform: { $0 }).values)
                }
            }
            for start in starts.sorted() {
                let function = try #require(functions.first { $0.startAddress == start })
                let expected: String
                if function.displayName.hasPrefix("HS.H.setAO(") {
                    expected = "outlined assign with copy of HS.AO(?, &self.ao, …)"
                } else if function.displayName.hasPrefix("HS.copyAO(") {
                    expected = "outlined init with copy of HS.AO(?, &result, …)"
                } else {
                    #expect(function.displayName.hasPrefix("HS.assignShape("))
                    expected = path.contains(".Onone.")
                        ? "__swift_assign_boxed_opaque_existential_1(arg0, arg1, …)"
                        : "outlined init with copy of HS.Shape(arg1, arg0, …)"
                }
                for text in [function.renderStructured(), function.renderPseudo()] {
                    #expect(text.contains(expected), Comment(rawValue: "stage \(stage), \(path): " + text))
                }
            }
        }
    }
}
