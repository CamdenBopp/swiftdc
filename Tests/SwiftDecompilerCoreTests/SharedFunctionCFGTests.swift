import Foundation
import Testing
@testable import SwiftDecompilerCore

struct SharedFunctionCFGTests {
    private static func decoded(_ words: [UInt32]) throws -> [Instruction] {
        let engine = try #require(CapstoneEngine())
        let body = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000)
        try #require(body.count == words.count)
        return body.map { Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }
    }

    private static func function(_ instructions: [Instruction], tables: [UInt64: [UInt64]] = [:]) -> DisassembledFunction {
        DisassembledFunction(symbol: "_shared_cfg", demangledName: "IRFixture.run() -> Swift.Int",
                             startAddress: 0x1000, instructions: instructions, source: .symbol, switchTargets: tables)
    }

    @Test func sharedTopologyReadsCurrentInstructionFacts() throws {
        let original = Self.function(try Self.decoded([0xd28000e0, 0xd65f03c0])) // mov x0,#7; ret
        let cfg = FunctionCFG(original)
        let updated = original.replacingInstructions(original.instructions.map { insn in
            Instruction(address: insn.address, text: insn.text, annotation: "fresh display note",
                        controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                        detail: insn.detail, callee: .kept("fresh typed callee"), facts: Instruction.Facts(exit: .normal("fresh typed exit")))
        })
        #expect(cfg == FunctionCFG(updated))
        let blocks = cfg.basicBlocks(of: updated)
        #expect(blocks.flatMap(\.instructions).allSatisfy { $0.annotation == "fresh display note" && $0.callee == "fresh typed callee" && $0.exit == .normal("fresh typed exit") })
        let supplied = ValueTracer().analyze(updated, entry: nil, cfg: cfg)
        #expect(supplied.exitValues[0x1004] == .immediate(7))
        #expect(supplied.exitValues == ValueTracer().analyze(updated, entry: nil).exitValues)
    }

    #if DEBUG
    @Test func graphEvidenceRejectsEqualLengthStaleEdges() throws {
        let unresolved = Self.function(try Self.decoded([0xd61f0120, 0xd65f03c0])) // br x9; ret
        let cfg = FunctionCFG(unresolved)
        let recorder = ProbeRecorder()
        let variants = [
            unresolved,
            unresolved.replacingInstructions([
                Instruction(address: 0x1000, text: "br x9", controlFlow: .branch, branchTarget: 0x3000),
                unresolved.instructions[1]]),
            unresolved.attachingSwitchTargets([0x1000: [0x1004, 0x1004]]),
            unresolved.replacingInstructions([
                Instruction(address: 0x1000, text: "brk #1", controlFlow: .sequential),
                unresolved.instructions[1]]),
        ]
        Probe.recording(recorder) {
            for variant in variants { cfg.observeUse(of: variant, consumer: "stale-edge-oracle") }
        }
        #expect(recorder.records.map { $0["matches-fresh"] } == [.bool(true), .bool(false), .bool(false), .bool(true)])
        // A nil-target BR and a trap both have no successors. A targeted BR
        // becoming a return really does change topology, at the same count.
        let targeted = variants[1]
        let returned = targeted.replacingInstructions([
            Instruction(address: 0x1000, text: "br x9", controlFlow: .return, branchTarget: 0x3000),
            targeted.instructions[1]])
        #expect(FunctionCFG(targeted) != FunctionCFG(returned))
        #expect(FunctionCFG(unresolved) == FunctionCFG(returned))
    }

    @Test func analysisSharesOneGraphAndRefreshesResolvedTailEdges() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shared-cfg-\(UUID().uuidString).o")
        let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
        var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        data.append(Data(count: 1024 - data.count))
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try await withStableDependencies {
            let machO = try BinaryLoader.load(path: file.path)
            // Independently decodable shapes: mov x9,#0x3000; BLR/BR x9.
            for (words, callee, expectedBuilds, retraces) in [
                ([UInt32(0xd28000e0), 0xd65f03c0], "IRFixture.external() -> Swift.Int", 1, false),
                ([UInt32(0xd2860009), 0xd63f0120, 0xd28000e0, 0xd65f03c0], "IRFixture.Box.value.setter : Swift.Int", 1, true),
                ([UInt32(0xd2860009), 0xd61f0120], "IRFixture.external() -> Swift.Int", 2, false),
                ([UInt32(0xd2820009), 0xd61f0120], "IRFixture.run() -> Swift.Int", 1, false),
            ] {
                let function = Self.function(try Self.decoded(words))
                let resolver = Disassembler.ReferenceResolver(names: [0x1000: "IRFixture.run() -> Swift.Int", 0x3000: callee], stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
                let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [0x3000],
                    objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
                    selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
                    enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
                    classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
                    asyncIndex: .empty, asyncChainSlots: [:])
                let recorder = ProbeRecorder()
                let result = Probe.recording(recorder) { Disassembler().analyzeFunction(function, context: context) }
                #expect(recorder.count(of: .cfgGraphBuilt) == expectedBuilds, "\(words): \(recorder.records.map { ($0.event.id, $0["consumer"]) })")
                let uses = recorder.records.filter { $0.event == .cfgGraphUsed }
                #expect(!uses.isEmpty)
                #expect(uses.allSatisfy { $0["matches-fresh"] == .bool(true) }, "\(uses)")
                let roles = Set(uses.compactMap { record -> String? in
                    if case .label(let role)? = record["consumer"] { return role }; return nil
                })
                #expect(roles.isSuperset(of: ["value-tracer", "indirect-result-use", "probe-snapshot"]))
                #expect(roles.contains("resolved-setter-retrace") == retraces)
                if expectedBuilds == 2 {
                    #expect(result.instructions.last?.branchTarget == 0x3000)
                    #expect(FunctionCFG(result).blocks.last?.successorAddresses == [0x3000])
                }
            }
        }
    }
    #endif
}

struct SharedFunctionCFGAdditionalTests {
    private static func role(_ record: ProbeRecord) -> String? {
        if case .label(let value)? = record["consumer"] { return value }
        return nil
    }

    private static func roles(_ recorder: ProbeRecorder) -> Set<String> {
        Set(recorder.records.filter { $0.event == .cfgGraphUsed }.compactMap(role))
    }

    // Fixture discovery/decoding is deliberately outside recording. Each
    // recorder surrounds only one actual analyzeFunction invocation.
    private static func analyses(path: String, filter: String) async throws
        -> [(DisassembledFunction, ProbeRecorder)]? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try await withStableDependencies {
            let disassembler = Disassembler()
            let machO = try BinaryLoader.load(path: path)
            let all = try await disassembler.disassemble(path: path)
            try #require(!all.isEmpty)
            let selected = all.filter { $0.displayName.contains(filter) || $0.symbol.contains(filter) }
            try #require(!selected.isEmpty, "No fixture function for \(filter)")
            let boundaries = Array(Set(all.map(\.startAddress))).sorted()
            let names = Dictionary(all.map { ($0.startAddress, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            let resolver = Disassembler.ReferenceResolver(names: names, stringRanges: [], machO: machO,
                                                           demangleSymbol: { _ in nil })
            let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: Set(names.keys),
                objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
                selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
                enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
                classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
                asyncIndex: .empty, asyncChainSlots: [:])
            var output: [(DisassembledFunction, ProbeRecorder)] = []
            for selectedFunction in selected {
                // Restore machine flow (not final async .return) and remove
                // preattached tables: production must recognize them itself.
                let decoded = disassembler.decodeFunction(at: selectedFunction.startAddress,
                                                           boundaries: boundaries, in: machO)
                try #require(!decoded.isEmpty && decoded.count == selectedFunction.instructions.count,
                             "Raw body extent differs for \(selectedFunction.displayName)")
                let raw = selectedFunction.replacingInstructions(decoded).attachingSwitchTargets([:])
                let recorder = ProbeRecorder()
                let result = Probe.recording(recorder) { disassembler.analyzeFunction(raw, context: context) }
                let changesTarget = zip(raw.instructions, result.instructions).contains { before, after in
                    before.controlFlow == .branch && before.branchTarget == nil && after.branchTarget != nil
                }
                #expect(recorder.count(of: .cfgGraphBuilt) == (changesTarget ? 2 : 1),
                        "\(raw.displayName): \(recorder.records.map { ($0.event.id, $0["consumer"]) })")
                let uses = recorder.records.filter { $0.event == .cfgGraphUsed }
                #expect(!uses.isEmpty)
                #expect(uses.allSatisfy { $0["matches-fresh"] == .bool(true) }, "\(raw.displayName): \(uses)")
                output.append((result, recorder))
            }
            return output
        }
    }

    #if DEBUG
    @Test func recognizedJumpTablesReachTheSharedAnalysisGraphIfPresent() async throws {
        let path = "Fixtures/Sample/libSwitches.dylib"
        guard let results = try await Self.analyses(path: path, filter: "pickByte") else { return }
        let (function, recorder) = try #require(results.first { $0.0.symbol == "_pickByte" })
        let cases = try #require(function.switchTargets.values.first)
        #expect(cases.count == 10 && cases[0] == cases[7] && Set(cases).count == 9)
        #expect(recorder.count(of: .cfgGraphBuilt) == 1)
        #expect(Self.roles(recorder).isSuperset(of: ["value-tracer", "indirect-result-use",
                                                    "probe-snapshot", "result-bindings"]))
    }

    @Test func throwingAsyncAndBindingConsumersReceiveTheSharedGraphIfPresent() async throws {
        let asyncPath = "Fixtures/Sample/libAsyncFns.opt.dylib"
        guard let throwing = try await Self.analyses(path: asyncPath, filter: "fetchOrThrow") else { return }
        let required: Set<String> = ["async-throw-exits", "error-proof", "result-bindings"]
        #expect(throwing.contains { Self.roles($0.1).isSuperset(of: required) },
                "\(throwing.map { ($0.0.displayName, Self.roles($0.1)) })")

        let errorPath = "Fixtures/Sample/libErrorExitControls.dylib"
        guard let synchronous = try await Self.analyses(path: errorPath, filter: "spillReload") else { return }
        #expect(synchronous.contains { Self.roles($0.1).contains("error-proof") })

        let bindingPath = "Fixtures/Sample/libCompares.dylib"
        guard let bindings = try await Self.analyses(path: bindingPath, filter: "Compares.doubledSink") else { return }
        #expect(bindings.contains { Self.roles($0.1).isSuperset(of: ["result-bindings", "return-paths"]) },
                "\(bindings.map { ($0.0.displayName, Self.roles($0.1)) })")
    }

    private static func decoded(_ words: [UInt32], at address: UInt64) throws -> [Instruction] {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: address)
        try #require(body.count == words.count)
        return body.map { Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }
    }

    @Test func eachFuncletTraceAndEscapePassSharesItsOneGraph() throws {
        // Same compiler-style own-context continuation seam as the existing
        // AsyncContextEscapeTests; index construction is outside recording.
        let entry = try Self.decoded([0xd28000e8, 0xf9000ac8, 0x10007fc0, 0x14000bfd], at: 0x1000)
        let resume = try Self.decoded([0xf9400ac0, 0xd65f03c0], at: 0x2000)
        let raw: [UInt64: DisassembledFunction] = [
            0x1000: .init(symbol: "entry", demangledName: "M.entry() async -> Swift.Int", startAddress: 0x1000,
                          instructions: entry, source: .address),
            0x2000: .init(symbol: "resume", demangledName: nil, startAddress: 0x2000,
                          instructions: resume, source: .address),
        ]
        let index = AsyncFuncletIndex.build(hints: .init(entries: [0x1000], awaitReturns: [], continuations: [0x2000]),
            functionStarts: Set(raw.keys), instructions: { raw[$0]?.instructions ?? [] },
            nameOf: { $0 == 0x4000 ? "swift_task_switch" : raw[$0]?.displayName })
        try #require(index.chains[0x1000] == [0x1000, 0x2000])
        let functions = raw.mapValues { function in
            index.info(for: function.startAddress, parentName: { raw[$0]?.displayName })
                .map(function.attachingAsyncFunclet) ?? function
        }
        let recorder = ProbeRecorder()
        let slots = Probe.recording(recorder) {
            Disassembler().asyncChainSlots(index: index, function: { functions[$0] },
                enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())
        }
        #expect(slots[0x2000]?[16] == .immediate(7))
        let uses = recorder.records.filter { $0.event == .cfgGraphUsed }
        #expect(uses.allSatisfy { $0["matches-fresh"] == .bool(true) })
        for address: UInt64 in [0x1000, 0x2000] {
            // A chain may need multiple rounds. Compare per-entry counts for
            // this isolated chain invocation instead of assuming one round.
            let builds = recorder.records.filter { $0.event == .cfgGraphBuilt && $0.address == address }.count
            let traces = uses.filter { $0.address == address && Self.role($0) == "value-tracer" }.count
            let escapes = uses.filter { $0.address == address && Self.role($0) == "async-context-escapes" }.count
            #expect(builds > 0 && traces > 0 && escapes > 0)
            #expect(builds == traces && builds == escapes,
                    "\(address): builds=\(builds), traces=\(traces), escapes=\(escapes)")
        }
    }
    #endif
}
