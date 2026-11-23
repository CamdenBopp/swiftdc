import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Native wrappers return 42 or 3.0, and each helper increments a counter.
/// Their bodies cannot be inlined: they store and rewrite caller-owned x19.
/// The helper is an effect, never the producer of an unwritten result bank.
@Test func unwrittenOutlinedResultBanksKeepTheirValuesInEveryPipelineIfPresent() async throws {
    for path in ["Fixtures/Sample/libOutlinedResults.dylib", "Fixtures/Sample/libOutlinedResults.stripped.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let pipelines = try await outlinedResultPipelines(path)
        for group in pipelines {
            for name in ["writeGP", "writeFP"] {
                let f = try #require(group.first { $0.displayName.hasPrefix("OutlinedResults." + name + "(") })
                let helper = try #require(f.instructions.last { $0.controlFlow == .call }.flatMap(DisassembledFunction.calleeName(of:)))
                for text in [f.renderStructured(), f.renderPseudo()] {
                    #expect(text.components(separatedBy: helper + "(").count == 2, Comment(rawValue: text))
                    let returned = try #require(text.split(separator: "\n").first { $0.contains("return ") })
                    #expect(returned.contains(helper) || returned.contains("r0"), Comment(rawValue: text))
                    #expect(!returned.contains("42") && !returned.contains("1.5"), Comment(rawValue: text))
                }
            }
            for name in ["keepGP", "keepFP", "gpAcrossFP", "fpAcrossGP", "keepProducer"] {
                let f = try #require(group.first { $0.displayName.hasPrefix("OutlinedResults." + name + "(") })
                let callInstructions = f.instructions.filter { $0.controlFlow == .call }
                let helper = try #require(callInstructions.last.flatMap(DisassembledFunction.calleeName(of:)))
                for text in [f.renderStructured(), f.renderPseudo()] {
                    let returned = try #require(text.split(separator: "\n").first { $0.contains("return ") })
                    #expect(!returned.contains("OUTLINED_FUNCTION") && !returned.contains("sub_"), Comment(rawValue: text))
                    if name != "keepProducer" { #expect(!text.contains("let r0 ="), Comment(rawValue: text)) }
                    // Each helper's memory effect must still be evaluated once.
                    #expect(text.components(separatedBy: helper + "(").count == 2, Comment(rawValue: text))
                    if name == "keepProducer" {
                        let producer = try #require(callInstructions.first.flatMap(DisassembledFunction.calleeName(of:)))
                        #expect(callInstructions.count == 2)
                        #expect(text.components(separatedBy: DisassembledFunction.strippedCallee(producer)).count == 2, Comment(rawValue: text))
                        #expect(returned.contains("producer()") || returned.contains("r0"), Comment(rawValue: text))
                    } else if name == "keepGP" || name == "gpAcrossFP" {
                        #expect(returned.contains("42"), Comment(rawValue: text))
                    } else {
                        #expect(returned.contains("1.5") || returned.contains("3.0"), Comment(rawValue: text))
                    }
                }
            }
        }
    }
    // These are real compiler-generated -Osize outlined helpers and native
    // Task/executor frames, independent of the assembly reduction above.
    for path in ["Fixtures/Sample/async-isolation-Osize-concurrent-oracle",
                 "Fixtures/Sample/async-isolation-Osize-nonsending-oracle"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for group in try await outlinedResultPipelines(path, filter: "Oracle.main") {
            for render in [group.map { $0.renderStructured() }, group.map { $0.renderPseudo() }] {
                let text = render.joined(separator: "\n")
                #expect(text.contains("AsyncIsolation.mix(?, 0.25, ?)"), Comment(rawValue: path + "\n" + text))
                #expect(text.contains("AsyncIsolation.mixOuter(?, 0.25, ?)"), Comment(rawValue: path + "\n" + text))
            }
        }
    }
}

private func outlinedResultPipelines(_ path: String, filter: String = "OutlinedResults") async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: filter) }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    return [listing, array, filtered, streamed, Array(each.values)]
}

#if arch(arm64)
@Test func outlinedResultRegisterTransportMatchesNativeEffectsIfPresent() throws {
    for (path, success) in [
        ("Fixtures/Sample/outlined_results_native", "PASS 21 outlined result observations; 21 helper effects"),
        ("Fixtures/Sample/async-isolation-Osize-concurrent-oracle", "PASS 71 native async isolation observations"),
        ("Fixtures/Sample/async-isolation-Osize-nonsending-oracle", "PASS 71 native async isolation observations"),
    ] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: output))
        #expect(output.contains(success), Comment(rawValue: output))
    }
}
#endif

private func outlinedResultBody(_ words: [UInt32], callee: String = "unknown", namedABI: Bool = false) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(bytes, address: 0x1000)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "probe", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail,
                callee: .kept($0.controlFlow == .call ? callee : nil), facts: {
                    var facts = Instruction.Facts()
                    facts.namedABIContract = namedABI
                    return facts
                }())
        }, source: .address)
}

@Test func unwrittenResultTransportKeepsPrecisionAndRespectsLogicalResultBanks() throws {
    let function = try outlinedResultBody([0x94000800, 0xd65f03c0]) // bl 0x3000; ret
    let entry = MethodEntryConvention.swiftFunction(scalarArguments: ["x0":0, "v0":1])
    let both: CalleeRegisterSummary.ResultRead = [.x0, .v0]
    for width in [16, 32, 64] {
        for mask: CalleeRegisterSummary.ResultRead in [[], .x0, .v0, both] {
            var tracer = ValueTracer()
            tracer.entryFloatWidths = ["v0":width]
            if !mask.isEmpty { tracer.calleeUnwrittenResults[0x3000] = mask }
            let result = tracer.analyze(function, entry: entry)
            #expect(result.exitValues[0x1004] == (mask.contains(.x0) ? .argument(0) : .callResult(0x1000)))
            let fp = AbstractValue.unary(.floatResult(bits: width, upperZero: width == 64), .argument(1))
            #expect(result.exitFloatValues[0x1004] == (mask.contains(.v0) ? fp : .callResult(0x1000)))
        }
    }
    // A C declaration also owns its result bank. These are analysis-only
    // contract controls; the native fixture uses no borrowed C API names.
    for name in ["memcmp", "cosf"] {
        let declared = try outlinedResultBody([0x94000800, 0xd65f03c0], callee: name, namedABI: true)
        var tracer = ValueTracer()
        tracer.entryFloatWidths = ["v0":16]
        tracer.calleeUnwrittenResults[0x3000] = both
        let result = tracer.analyze(declared, entry: entry)
        if name == "memcmp" {
            #expect(result.exitValues[0x1004] == .callResult(0x1000))
        } else {
            #expect(result.exitFloatValues[0x1004] == .unary(.floatResult(bits: 32, upperZero: false), .callResult(0x1000)))
        }
    }
    for name in ["Calls.string() -> Swift.String", "Calls.tuple() -> (Swift.Int, Swift.Double)"] {
        let declared = try outlinedResultBody([0x94000800, 0xd65f03c0], callee: name)
        var tracer = ValueTracer()
        tracer.calleeUnwrittenResults[0x3000] = both
        let result = tracer.analyze(declared, entry: entry)
        if name.contains("String") {
            #expect(result.exitValues[0x1004] == .callResult(0x1000))
            #expect(result.exitFloatValues[0x1004] == .callResult(0x1000))
        } else {
            #expect((result.exitValues[0x1004] ?? .unknown) == .unknown)
            #expect(result.exitFloatValues[0x1004] == nil)
        }
    }
    for bank: ValueTracer.CallResultBank in [.integer, .scalarFloating(bits: 32), .notOneRegister] {
        var tracer = ValueTracer()
        tracer.entryFloatWidths = ["v0":16]
        tracer.calleeUnwrittenResults[0x3000] = both
        tracer.callResultBank = { _ in bank }
        let result = tracer.analyze(function, entry: entry)
        #expect(result.exitValues[0x1004] == (bank.isFloating ? .argument(0) : .callResult(0x1000)))
        if bank == .integer {
            #expect(result.exitFloatValues[0x1004] == .unary(.floatResult(bits: 16, upperZero: false), .argument(1)))
        } else if bank.isFloating {
            #expect(result.exitFloatValues[0x1004] == .unary(.floatResult(bits: 32, upperZero: false), .callResult(0x1000)))
        } else {
            #expect(result.exitFloatValues[0x1004] == nil)
        }
    }
}

@Test func unchangedResultRegistersDoNotReviveInvalidatedFieldAliases() throws {
    let function = try outlinedResultBody([0x94000800, 0xd65f03c0])
    let entry = MethodEntryConvention.swiftValueInstance(seededRegisters: [
        "x0":.selfFieldValue(offset: 8), "v0":.selfFieldValue(offset: 16), "x20":.selfPointer,
    ])
    for fieldsSurvive in [false, true] {
        var tracer = ValueTracer()
        tracer.calleeUnwrittenResults[0x3000] = [.x0, .v0]
        if fieldsSurvive { tracer.fieldPreservingCallees.insert(0x3000) }
        let result = tracer.analyze(function, entry: entry)
        #expect((result.exitValues[0x1004] ?? .unknown) == (fieldsSurvive ? .selfFieldValue(offset: 8) : .unknown))
        #expect((result.exitFloatValues[0x1004] ?? .unknown) == (fieldsSurvive ? .selfFieldValue(offset: 16) : .unknown))
    }
}

@Test func unwrittenResultSummaryRequiresDecodedBanksAndNoOutgoingCall() throws {
    for (words, gp, fp): ([UInt32], Bool, Bool) in [
        ([0xaa0003f3, 0xd65f03c0], false, false), // mov x19,x0; ret
        ([0x52800160, 0xd65f03c0], true, false), // mov w0,#11; ret
        ([0x1e601000, 0xd65f03c0], false, true), // fmov d0,#2; ret
        ([0x94000800, 0xd65f03c0], true, true), // outgoing bl
        ([0x14000800], true, true), // outgoing b
        ([0xd61f0040], true, true), // unresolved br x2
    ] {
        let summary = try #require(CalleeRegisterSummary.of(try outlinedResultBody(words)))
        #expect(summary.mayWriteResult == gp)
        #expect(summary.mayWriteFloatResult == fp)
    }
}
