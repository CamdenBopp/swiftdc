import Foundation
import Testing
@testable import SwiftDecompilerCore

#if DEBUG
struct FinalFunctionCFGTests {
    private static func decoded(_ words: [UInt32]) throws -> [Instruction] {
        let engine = try #require(CapstoneEngine())
        let body = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000)
        try #require(body.count == words.count)
        return body.map { Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                                      branchTarget: $0.branchTarget, detail: $0.detail) }
    }

    private static func function(_ instructions: [Instruction], source: RecoverySource = .symbol,
                                 tables: [UInt64: [UInt64]] = [:]) -> DisassembledFunction {
        DisassembledFunction(symbol: "_final_cfg", demangledName: "IRFixture.run() -> Swift.Int",
            startAddress: 0x1000, instructions: instructions, source: source, switchTargets: tables)
    }

    private static func roles(_ recorder: ProbeRecorder) -> Set<String> {
        Set(recorder.records.compactMap { record in
            guard record.event == .cfgGraphUsed,
                  case .label(let role)? = record["consumer"] else { return nil }
            return role
        })
    }

    private static func requireFresh(_ recorder: ProbeRecorder) {
        let uses = recorder.records.filter { $0.event == .cfgGraphUsed }
        #expect(!uses.isEmpty)
        #expect(uses.allSatisfy { $0["matches-fresh"] == .bool(true) }, "\(uses)")
    }

    /// The graph is topology only. Every consumer must read the current
    /// instruction array rather than retain an earlier BasicBlock payload.
    @Test func payloadAndMetadataCopiesKeepGraphButExposeCurrentFacts() throws {
        let raw = Self.function([
            Instruction(address: 0x1000, text: "bl fixture_before", controlFlow: .call,
                        branchTarget: 0x3000, callArguments: ["1"], callee: .kept("fixture_before")),
            Instruction(address: 0x1004, text: "ret", controlFlow: .return,
                        facts: Instruction.Facts(exit: .normal("7"))),
        ], source: .address)
        let cached = raw.retainingCFG(FunctionCFG(raw))
        let replacement = [
            Instruction(address: 0x1000, text: "bl fixture_before", annotation: "fresh call note",
                        controlFlow: .call, branchTarget: 0x3000, callArguments: ["9"],
                        callee: .kept("fixture_after")),
            Instruction(address: 0x1004, text: "ret", annotation: "fresh return note",
                        controlFlow: .return, facts: Instruction.Facts(exit: .normal("123"))),
        ]
        let info = AsyncFuncletInfo(parent: 0x800, parentName: "IRFixture.owner() async -> Swift.Int",
            ordinal: 1, kind: .continuation, predecessor: 0x800, chain: [0x800, 0x1000])
        let recorder = ProbeRecorder()
        Probe.recording(recorder) {
            let updated = cached.replacingInstructionPayload(replacement).attachingAsyncFunclet(info)
            #expect(updated.instructions[0].callee == "fixture_after")
            #expect(updated.asyncFunclet == info)
            #expect(updated.source == .asyncFunclet)
            let blocks = updated.basicBlocks()
            #expect(blocks.flatMap(\.instructions).map(\.annotation) == replacement.map(\.annotation))
            #expect(blocks.flatMap(\.instructions).map(\.exit) == replacement.map(\.exit))
            #expect(updated.renderCFG().contains("fresh return note"))
            #expect(updated.renderPseudo().contains("fixture_after"))
            #expect(updated.renderStructured().contains("return 123"))
            let json = [updated].jsonString()
            #expect(json.contains("fresh call note") && json.contains("fixture_after") && json.contains("return 123"))
        }
        #expect(recorder.count(of: .cfgGraphBuilt) == 0)
        Self.requireFresh(recorder)
    }

    @Test func retainedGraphServesEveryDefaultConsumerWithoutRecovery() throws {
        let raw = Self.function(try Self.decoded([0xd28000e0, 0xd65f03c0]))
        let cached = raw.retainingCFG(FunctionCFG(raw))
        let analysis = ValueTracer().analyze(raw, entry: nil)
        let recorder = ProbeRecorder()
        Probe.recording(recorder) {
            for _ in 0..<3 {
                #expect(!cached.basicBlocks().isEmpty)
                #expect(!cached.renderCFG().isEmpty)
                #expect(!cached.renderStructured().isEmpty)
                #expect(![cached].jsonString().isEmpty)
                Probe.observe(analysis, of: cached)
                #expect(Probe.returnPathConditions(analysis, of: cached)[0x1004] == .immediate(1))
                #expect(ValueTracer().analyze(cached, entry: nil).exitValues[0x1004] == .immediate(7))
                #expect(Disassembler.indirectResultUse(of: cached) == .neverReads)
                #expect(AsyncContextEscapes().lowestOffset(in: cached) == nil)
                #expect(ObjCDumper.isSynthesizedAccessor(cached) == false)
            }
        }
        #expect(recorder.count(of: .cfgGraphBuilt) == 0)
        Self.requireFresh(recorder)
        #expect(Self.roles(recorder).isSuperset(of: ["structured-renderer", "json-output", "cfg-renderer",
            "probe-snapshot", "return-paths", "value-tracer", "indirect-result-use",
            "async-context-escapes", "accessor-classifier"]))
    }

    @Test func genericEqualLengthReplacementInvalidatesRetainedTopology() throws {
        let body = [
            Instruction(address: 0x1000, text: "nop", controlFlow: .sequential),
            Instruction(address: 0x1004, text: "nop", controlFlow: .sequential),
            Instruction(address: 0x1008, text: "ret", controlFlow: .return),
        ]
        let raw = Self.function(body)
        let cached = raw.retainingCFG(FunctionCFG(raw))
        var variants: [[Instruction]] = []
        for first in [
            Instruction(address: 0x1000, text: "b 0x3000", controlFlow: .branch, branchTarget: 0x3000),
            Instruction(address: 0x1000, text: "ret", controlFlow: .return),
            Instruction(address: 0x1000, text: "brk #1", controlFlow: .sequential),
            Instruction(address: 0x2000, text: "nop", controlFlow: .sequential),
        ] { variants.append([first, body[1], body[2]]) }
        variants.append([body[1], body[0], body[2]])
        for instructions in variants {
            let updated = cached.replacingInstructions(instructions)
            let expected = FunctionCFG(updated)
            let recorder = ProbeRecorder()
            let actual = Probe.recording(recorder) { updated.controlFlowGraph }
            #expect(recorder.count(of: .cfgGraphBuilt) == 1)
            #expect(actual == expected)
            #expect(actual.basicBlocks(of: updated).flatMap(\.instructions).map(\.address) == instructions.map(\.address))
        }
    }

    @Test func changingRepeatedSwitchCasesInvalidatesTheirRetainedOrder() {
        let raw = Self.function([
            Instruction(address: 0x1000, text: "br x9", controlFlow: .branch),
            Instruction(address: 0x1004, text: "ret", controlFlow: .return),
            Instruction(address: 0x1008, text: "ret", controlFlow: .return),
        ], tables: [0x1000: [0x1004, 0x1004, 0x1008]])
        let cached = raw.retainingCFG(FunctionCFG(raw))
        let updated = cached.attachingSwitchTargets([0x1000: [0x1008, 0x1004, 0x1008]])
        let recorder = ProbeRecorder()
        let graph = Probe.recording(recorder) { updated.controlFlowGraph }
        #expect(recorder.count(of: .cfgGraphBuilt) == 1)
        #expect(graph.blocks[0].switchCases == [0x1008, 0x1004, 0x1008])
        #expect(graph.blocks[0].successorAddresses == [0x1008, 0x1004])
        #expect(graph == FunctionCFG(updated))
    }

    @Test func publicManualInitializationRemainsASafeUncachedFallback() throws {
        let function = Self.function(try Self.decoded([0xd28000e0, 0xd65f03c0]))
        let expected = FunctionCFG(function)
        let recorder = ProbeRecorder()
        Probe.recording(recorder) {
            for _ in 0..<2 { #expect(function.controlFlowGraph == expected) }
        }
        #expect(recorder.count(of: .cfgGraphBuilt) == 2)
        #expect(ValueTracer().analyze(function, entry: nil).exitValues[0x1004] == .immediate(7))
    }

    @Test func everyEnrichmentExitRetainsTheFinalVersionIncludingResolvedTails() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("final-cfg-\(UUID().uuidString).o")
        let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
        var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        data.append(Data(count: 1024 - data.count)); try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try await withStableDependencies {
            let machO = try BinaryLoader.load(path: file.path)
            let resolver = Disassembler.ReferenceResolver(names: [0x3000: "IRFixture.external() -> Swift.Int"],
                stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
            let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [0x3000],
                objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
                selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
                enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
                classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
                asyncIndex: .empty, asyncChainSlots: [:])
            let noFacts = try Self.decoded([0xd503201f, 0xd65f03c0]) // nop; ret, with no x0 value
            let noFactsInt = Self.function(noFacts)
            let noFactsVoid = DisassembledFunction(symbol: "_final_cfg_void", demangledName: "IRFixture.empty() -> ()",
                startAddress: 0x1000, instructions: noFacts, source: .symbol)
            let rawAnalysis = ValueTracer().analyze(noFactsInt, entry: .swiftFunction(scalarArguments: [:]))
            try #require(rawAnalysis.callSites.isEmpty && rawAnalysis.exitValues.isEmpty && rawAnalysis.exitFloatValues.isEmpty)
            try #require(noFactsInt.hasProvenMachineValueReturn && !noFactsVoid.hasProvenMachineValueReturn)
            let cases = [noFactsInt, noFactsVoid] + (try [[UInt32(0xd28000e0), 0xd65f03c0],
                [UInt32(0xd2860009), 0xd63f0120, 0xd65f03c0], [UInt32(0xd2860009), 0xd61f0120]].map {
                    Self.function(try Self.decoded($0))
                })
            for raw in cases {
                let function = Disassembler().analyzeFunction(raw, context: context)
                let expected = FunctionCFG(function)
                let recorder = ProbeRecorder()
                Probe.recording(recorder) {
                    #expect(function.controlFlowGraph == expected)
                    #expect(!function.renderCFG().isEmpty)
                    #expect(!function.renderStructured().isEmpty)
                    #expect(![function].jsonString().isEmpty)
                }
                #expect(recorder.count(of: .cfgGraphBuilt) == 0, "\(raw.displayName): \(raw.instructions.map(\.text))")
                Self.requireFresh(recorder)
                if raw.instructions.last?.controlFlow == .branch {
                    #expect(function.instructions.last?.branchTarget == 0x3000)
                    #expect(expected.blocks.last?.successorAddresses == [0x3000])
                }
            }
        }
    }

    @Test func finalAsyncReturnViewsUseCurrentInstructionsIfPresent() async throws {
        let path = "Fixtures/Sample/libAsyncFns.opt.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "fetchOrThrow")
        }
        let returns = functions.filter { function in function.instructions.contains { insn in
            insn.controlFlow == .return && insn.text.split(whereSeparator: \.isWhitespace).first == "br"
        } }
        try #require(!returns.isEmpty)
        for function in returns {
            let recorder = ProbeRecorder()
            Probe.recording(recorder) {
                let blocks = function.basicBlocks()
                #expect(blocks.flatMap(\.instructions).map(\.controlFlow) == function.instructions.map(\.controlFlow))
                #expect(blocks.flatMap(\.instructions).contains { $0.controlFlow == .return && $0.text.split(whereSeparator: \.isWhitespace).first == "br" })
                #expect(![function].jsonString().isEmpty)
                #expect(!function.renderStructured().isEmpty)
                #expect(!function.renderCFG().isEmpty)
            }
            #expect(recorder.count(of: .cfgGraphBuilt) == 0)
            Self.requireFresh(recorder)
        }
    }
}
#endif
