import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let x8ScratchImages = [
    "Fixtures/Sample/libX8EntryScratch.dylib", "Fixtures/Sample/libX8EntryScratch.stripped.dylib",
    "Fixtures/Sample/libX8EntryScratchPreserved.dylib", "Fixtures/Sample/libX8EntryScratchPreserved.stripped.dylib",
]

private let x8GoImages = ["Fixtures/Sample/x8-entry-go-oracle", "Fixtures/Sample/x8-entry-go-stripped-oracle"]

private func x8Pipelines(_ path: String) async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    let listed = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let factory = try #require(listed.first { $0.displayName.hasPrefix("OutlineScratch.unchanged(") })
    let target = try #require(factory.instructions.first { $0.controlFlow == .call }?.branchTarget)
    let helper = try #require(listed.first { $0.startAddress == target })
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filteredHelper = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: helper.displayName) }
    let filteredFactory = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "OutlineScratch.unchanged(") }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies { await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 }) }
    return [listed, array, filteredHelper + filteredFactory, streamed, Array(each.values)]
}

@Test func anOutlinedX8DataWordIsNoResultPointerInEveryPipelineIfPresent() async throws {
    for path in x8ScratchImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for group in try await x8Pipelines(path) {
            let factory = try #require(group.first { $0.displayName.hasPrefix("OutlineScratch.unchanged(") })
            let target = try #require(factory.instructions.first { $0.controlFlow == .call }?.branchTarget)
            let helper = try #require(group.first { $0.startAddress == target })
            for text in [helper.renderStructured(), helper.renderPseudo()] {
                #expect(text.contains("mem64[") && text.contains("0x8"), Comment(rawValue: text))
                #expect(!text.contains("&result"), Comment(rawValue: path + "\n" + text))
            }
        }
    }
}

@Test func readingX8AsDataDoesNotFillTheCallersResultInEveryPipelineIfPresent() async throws {
    for path in x8ScratchImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for group in try await x8Pipelines(path) {
            let factory = try #require(group.first { $0.displayName.hasPrefix("OutlineScratch.unchanged(") })
            let call = try #require(factory.instructions.first { $0.controlFlow == .call })
            let name = try #require(DisassembledFunction.calleeName(of: call))
            for text in [factory.renderStructured(), factory.renderPseudo()] {
                #expect(text.contains("return ?"), Comment(rawValue: text))
                #expect(!text.contains("return " + name), Comment(rawValue: text))
                #expect(text.components(separatedBy: name + "(").count == 2, Comment(rawValue: text))
            }
        }
    }
}

@Test func realX8ResultEntriesRetainTheirBufferFactsIfPresent() async throws {
    let paths = [
        "Fixtures/Sample/libX8EntryResults.Onone.fixed.dylib", "Fixtures/Sample/libX8EntryResults.Onone.resilient.dylib",
        "Fixtures/Sample/libX8EntryResults.O.fixed.dylib", "Fixtures/Sample/libX8EntryResults.O.resilient.dylib",
        "Fixtures/Sample/libX8EntryResults.Osize.fixed.dylib", "Fixtures/Sample/libX8EntryResults.Osize.resilient.dylib",
        "Fixtures/Sample/libX8EntryReabstract.Onone.dylib", "Fixtures/Sample/libX8EntryReabstract.O.dylib", "Fixtures/Sample/libX8EntryReabstract.Osize.dylib",
        "Fixtures/Sample/libX8EntryObjC.O0.dylib", "Fixtures/Sample/libX8EntryObjC.O2.dylib", "Fixtures/Sample/libX8EntryObjC.Os.dylib",
    ]
    for path in paths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let listed = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        for stage in 0..<5 {
            let recorder = ProbeRecorder()
            let functions = try await Probe.recording(recorder) {
                try await withStableDependencies {
                    switch stage {
                    case 0: return try await Disassembler().disassemble(path: path)
                    case 1: return await Disassembler().disassemble(machO: image)
                    case 2:
                        let filter = path.contains("Reabstract") ? "Reabstract" : path.contains("ObjC") ? "EntryResultObject" : "EntryResults"
                        return try await Disassembler().disassemble(path: path, functionFilter: filter)
                    case 3: return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
                    default:
                        let each = await Disassembler().analyzeEachFunction(at: Set(listed.map(\.startAddress)), in: image, transform: { $0 })
                        return Array(each.values)
                    }
                }
            }
            let candidates = functions.filter {
                ($0.displayName.contains("EntryResults.") || $0.displayName.contains("ReabstractResult.") || $0.displayName.contains("reabstraction thunk") || $0.objcMethod?.selector == "wide:")
                    && (Disassembler.indirectResultUse(of: $0) == .reads || $0.displayName.hasPrefix("ReabstractResult.apply<"))
            }
            #expect(!candidates.isEmpty, Comment(rawValue: path + " stage " + String(stage)))
            for function in candidates {
                let record = try #require(recorder.records.first { $0.event.id == ProbeEvent.entryConvention.id && $0.function?.start == function.startAddress })
                guard case .object(let seeds)? = record["seeds"] else { Issue.record("No entry seeds"); continue }
                #expect(seeds["x8"] == ProbeValue.abstractValue(.indirectResultPointer), Comment(rawValue: path + " stage " + String(stage) + "\n" + function.displayName))
            }
        }
    }
}

#if arch(arm64)
@Test func x8EntryABIControlsMatchNativeIfPresent() throws {
    let paths = [
        "Fixtures/Sample/x8-entry-scratch-oracle",
        "Fixtures/Sample/x8-entry-scratch-preserved-oracle",
        "Fixtures/Sample/x8-entry-go-oracle", "Fixtures/Sample/x8-entry-go-stripped-oracle",
        "Fixtures/Sample/x8-entry-Onone-fixed-oracle", "Fixtures/Sample/x8-entry-Onone-resilient-oracle",
        "Fixtures/Sample/x8-entry-O-fixed-oracle", "Fixtures/Sample/x8-entry-O-resilient-oracle",
        "Fixtures/Sample/x8-entry-Osize-fixed-oracle", "Fixtures/Sample/x8-entry-Osize-resilient-oracle",
        "Fixtures/Sample/x8-entry-reabstract-Onone-oracle", "Fixtures/Sample/x8-entry-reabstract-O-oracle", "Fixtures/Sample/x8-entry-reabstract-Osize-oracle",
        "Fixtures/Sample/x8-entry-objc-O0-oracle", "Fixtures/Sample/x8-entry-objc-O2-oracle", "Fixtures/Sample/x8-entry-objc-Os-oracle",
    ]
    for path in paths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.standardOutput = pipe; process.standardError = pipe
        try process.run(); let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: path + "\n" + output))
        #expect(output.hasPrefix("PASS "), Comment(rawValue: output))
    }
}
#endif

private func x8RawBody(_ words: [UInt32], at address: UInt64 = 0x1000) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(bytes, address: address)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "probe", demangledName: nil, startAddress: address,
        instructions: decoded.map { Instruction(address: $0.address, text: $0.text,
            controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }, source: .address)
}

@Test func x8EntryModeControlsAnalysisAndProbeSeedsIncludingNestedEntries() throws {
    let body = try x8RawBody([0xaa0803e0, 0xd65f03c0]) // mov x0,x8; ret
    let base = MethodEntryConvention.swiftInstance(scalarArguments: ["x1":0, "v0":1])
    for entry in [base, .asyncFunclet(base: base, seededRegisters: ["x22":.asyncContext])] {
        for owned in [false, true] {
            let result = ValueTracer(entryHasResultBuffer: owned).analyze(body, entry: entry)
            #expect((result.exitValues[0x1004] ?? .unknown) == (owned ? .indirectResultPointer : .unknown))
            let seeds = ValueTracer.entrySeeds(entry, floatWidths: ["v0":32], entryHasResultBuffer: owned)
            let byRegister = Dictionary(uniqueKeysWithValues: seeds.map { ($0.register,$0.value) })
            #expect(byRegister["x8"] == (owned ? .indirectResultPointer : nil))
            #expect(byRegister["x20"] == .selfPointer)
            #expect(byRegister["x1"] == .argument(0))
            #expect(byRegister["v0"] == .unary(.floatResult(bits: 32, upperZero: false), .argument(1)))
        }
    }
}

@Test func x8ABIInterpretationRequiresPreservationAndSeparatesSwiftErrorOutput() throws {
    func facts(_ words: [UInt32]) throws -> CalleeRegisterFacts {
        let body = try x8RawBody(words)
        var summaries = [body.startAddress:try #require(CalleeRegisterSummary.of(body))]
        return try #require(CalleeRegisterFacts.finish(&summaries).facts[body.startAddress])
    }
    let plain = try facts([0xd65f03c0])
    let context = try facts([0xa9002016,0xaa0003f6,0xd65f03c0]) // store x22/x8 as data, overwrite x22
    #expect(context.clobberedCalleeSaved.contains("x22"))
    let restored = try facts([0xa9bf7bf6,0xaa0003f6,0xa8c17bf6,0xd65f03c0])
    #expect(!restored.clobberedCalleeSaved.contains("x22"))
    let go = GoFunctionTable(entries: [(0x1000, "first"), (0x2000, "last")])
    for address: UInt64 in [0x1000, 0x2000] { #expect(go.containsEntry(at: address)) }
    for address: UInt64 in [0, 0xfff, 0x1001, 0x1004, 0x1fff, 0x2001, UInt64.max] {
        #expect(!go.containsEntry(at: address))
    }
    let error = try facts([0xd2800015,0xd65f03c0])
    #expect(error.clobberedCalleeSaved.contains("x21"))
    for swift in [false,true] {
        #expect(Disassembler.permitsX8ResultABI(name: "ordinary", summary: plain, swiftABI: swift, asyncABI: false))
        #expect(Disassembler.permitsX8ResultABI(name: "ordinary", summary: restored, swiftABI: swift, asyncABI: false))
        #expect(!Disassembler.permitsX8ResultABI(name: "ordinary", summary: context, swiftABI: swift, asyncABI: false))
        #expect(!Disassembler.permitsX8ResultABI(name: "_OUTLINED_FUNCTION_0", summary: plain, swiftABI: swift, asyncABI: false))
        #expect(!Disassembler.permitsX8ResultABI(name: "ordinary", summary: plain, swiftABI: swift, asyncABI: true))
        #expect(!Disassembler.permitsX8ResultABI(name: "main.store9", summary: plain, swiftABI: swift, asyncABI: false, goABI: true))
        #expect(!Disassembler.permitsX8ResultABI(name: "ordinary", summary: nil, swiftABI: swift, asyncABI: false))
        for unresolved in [nil, "", "sub_1000", "_sub_1000"] as [String?] {
            #expect(!Disassembler.permitsX8ResultABI(name: unresolved, summary: plain, swiftABI: swift, asyncABI: false))
        }
        #expect(Disassembler.permitsX8ResultABI(name: "ordinary", summary: error, swiftABI: swift, asyncABI: false) == swift)
    }
}

@Test func x8CalleeDataReadHasNoIndirectResultConventionIfPresent() async throws {
    func convention(_ target: DisassembledFunction, in image: MachOFile, swift: Bool) throws -> CalleeResultConvention? {
        let caller = DisassembledFunction(symbol: "caller", demangledName: nil, startAddress: 0x1000,
            instructions: [Instruction(address: 0x1000, text: "bl target", controlFlow: .call,
                branchTarget: target.startAddress, callee: .kept(target.displayName))], source: .address)
        var summaries = [target.startAddress:try #require(CalleeRegisterSummary.of(target))]
        let facts = CalleeRegisterFacts.finish(&summaries).facts
        let resolver = Disassembler.ReferenceResolver(names: [target.startAddress:target.displayName], stringRanges: [],
            machO: image, demangleSymbol: { $0 })
        return Disassembler.calleeResultConventions(in: caller,
            indirectResultUses: [target.startAddress:Disassembler.indirectResultUse(of: target)],
            resolver: resolver, fieldMaps: [:], classTypeIndex: ClassTypeIndex(),
            registerSummaries: facts, swiftTargets: swift ? [target.startAddress] : [], asyncIndex: .empty,
            goFunctions: Disassembler().goFunctions(in: image))[0x1000]
    }
    for path in x8ScratchImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let factory = try #require(functions.first { $0.displayName.hasPrefix("OutlineScratch.unchanged(") })
        let target = try #require(factory.instructions.first { $0.controlFlow == .call }?.branchTarget)
        let helper = try #require(functions.first { $0.startAddress == target })
        #expect(Disassembler.indirectResultUse(of: helper) == .reads)
        if path.contains("Preserved") {
            var summaries = [helper.startAddress: try #require(CalleeRegisterSummary.of(helper))]
            let facts = try #require(CalleeRegisterFacts.finish(&summaries).facts[helper.startAddress])
            #expect(facts.clobberedCalleeSaved.isEmpty)
        }
        // Both native named/stripped helpers store x8 as data and leave all
        // five caller-owned words untouched. No indirect result is produced.
        #expect(try convention(helper, in: image, swift: false) == nil)
    }
    for path in x8GoImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let table = try #require(Disassembler().goFunctions(in: image))
        let entry = try #require(table.entries.first { $0.name == "main.store9" })
        let bytes = try #require(Disassembler().sectionBytes(address: entry.address, size: 8, in: image))
        // Independently compiled Go leaf: str x8,[x0]; ret. Inspect its actual
        // bytes, rather than asking analysis to manufacture the callee body.
        #expect(bytes == Data([0x08, 0x00, 0x00, 0xf9, 0xc0, 0x03, 0x5f, 0xd6]))
        let engine = try #require(CapstoneEngine())
        let decoded = engine.disassemble(bytes, address: entry.address)
        let helper = DisassembledFunction(symbol: "_" + entry.name, demangledName: nil,
            startAddress: entry.address, instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .symbol)
        #expect(Disassembler.indirectResultUse(of: helper) == .reads)
        #expect(try convention(helper, in: image, swift: false) == nil)
    }
    let positive = "Fixtures/Sample/libX8EntryObjC.O2.dylib"
    guard FileManager.default.fileExists(atPath: positive) else { return }
    let image = try BinaryLoader.load(path: positive)
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: positive) }
    let wide = try #require(functions.first { $0.objcMethod?.selector == "wide:" })
    #expect(Disassembler.indirectResultUse(of: wide) == .reads)
    // Clang's actual Triple-returning IMP uses x8 sret; the independent
    // native Objective-C oracle checks all three output words.
    #expect(try convention(wide, in: image, swift: false) == .indirect(sizeBytes: nil))
}


@Test func goX8EntryABIMetadataIsAppliedInFilteredPipelinesIfPresent() async throws {
    for path in x8GoImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let table = try #require(Disassembler().goFunctions(in: image))
        let recorder = ProbeRecorder()
        let functions = try await Probe.recording(recorder) {
            try await withStableDependencies {
                try await Disassembler().disassemble(path: path, functionFilter: "main.store9")
            }
        }
        let helper = try #require(functions.first { $0.symbol.contains("main.store9") })
        #expect(table.containsEntry(at: helper.startAddress))
        #expect(!table.containsEntry(at: helper.startAddress + 4))
        for text in [helper.renderStructured(), helper.renderPseudo()] {
            #expect(text.contains("mem64[arg0] = x8"), Comment(rawValue: text))
            #expect(!text.contains("&result"), Comment(rawValue: text))
        }
        let entry = try #require(recorder.records.first { $0.event.id == ProbeEvent.entryConvention.id && $0.function?.start == helper.startAddress })
        guard case .object(let seeds)? = entry["seeds"] else { Issue.record("No entry seeds"); continue }
        #expect(seeds["x8"] == nil)
    }
}

private func goX8PipelineStages(_ stages: [Int]) async throws {
    for path in x8GoImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let table = try #require(Disassembler().goFunctions(in: image))
        let start = try #require(table.entries.first { $0.name == "main.store9" }?.address)
        let mainStart = try #require(table.entries.first { $0.name == "main.main" }?.address)
        let growthTargets = Set(table.entries.filter { x8GoStackGrowthNames.contains($0.name) }.map(\.address))
        for stage in stages {
            let functions: [DisassembledFunction] = try await withStableDependencies {
                switch stage {
                case 0: return try await Disassembler().disassemble(path: path)
                case 1: return await Disassembler().disassemble(machO: image)
                case 2: return try await Disassembler().disassemble(path: path, functionFilter: "main.")
                case 3:
                    let selected: [DisassembledFunction?] = await Disassembler().disassembleStreaming(machO: image,
                        transform: { $0.startAddress == start || $0.startAddress == mainStart ? $0 : nil })
                    return selected.compactMap { $0 }
                default:
                    let each = await Disassembler().analyzeEachFunction(at: [start, mainStart], in: image, transform: { $0 })
                    return Array(each.values)
                }
            }
            let main = try #require(functions.first { $0.startAddress == mainStart })
            let mainStructured = main.renderStructured()
            let mainPseudo = main.renderPseudo()
            let growth = main.instructions.filter {
                ($0.controlFlow == .call || $0.controlFlow == .branch) && $0.branchTarget.map(growthTargets.contains) == true
            }
            #expect(!growth.isEmpty, Comment(rawValue: "stage \(stage): " + mainStructured))
            for call in growth { #expect(call.callArguments == nil, Comment(rawValue: mainStructured)) }
            for text in [mainStructured, mainPseudo] {
                #expect(text.contains("runtime.morestack_noctxt()") || text.contains("runtime.morestack_noctxt.abi0()"), Comment(rawValue: text))
            }
            let helper = try #require(functions.first { $0.startAddress == start })
            for text in [helper.renderStructured(), helper.renderPseudo()] {
                #expect(text.contains("mem64[arg0] = x8"), Comment(rawValue: "stage \(stage): " + text))
                #expect(!text.contains("&result"), Comment(rawValue: "stage \(stage): " + text))
            }
        }
    }
}


@Test func goX8ArrayPipelinesKeepIncomingDataUnownedIfPresent() async throws {
    try await goX8PipelineStages([0, 1, 2])
}

@Test func goX8StreamingPipelineKeepsIncomingDataUnownedIfPresent() async throws {
    try await goX8PipelineStages([3])
}

@Test func goX8AnalyzeEachPipelineKeepsIncomingDataUnownedIfPresent() async throws {
    try await goX8PipelineStages([4])
}

private func x8EmptyArityCaller(_ kind: String, tail: Bool, indirect: Bool = false,
                                calleeName: String = "sub_2000", goFunctions: GoFunctionTable? = nil,
                                seedValue: Bool = false) throws -> DisassembledFunction {
    let image = try BinaryLoader.load(path: x8ScratchImages[0])
    func raw(_ words: [UInt32], at start: UInt64, name: String) throws -> DisassembledFunction {
        let engine = try #require(CapstoneEngine())
        let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        let decoded = engine.disassemble(bytes, address: start)
        try #require(decoded.count == words.count)
        return DisassembledFunction(symbol: name, demangledName: nil, startAddress: start,
            instructions: decoded.map { Instruction(address: $0.address, text: $0.text,
                controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }, source: .address)
    }
    let words: [UInt32] = (kind == "stack" || kind == "missing") ? [0xf94003e0, 0xd65f03c0] // ldr x0,[sp]; ret
        : kind == "mayTail" ? [0x90000003, 0x91000063, 0x14000800] // adrp/add x3; b unavailable body
        : kind == "may" ? [0xa9bf7bfd, 0x910003fd, 0x940007fe, 0xa8c17bfd, 0xd65f03c0] // frame; opaque bl; restore; ret
        : [0xd65f03c0]
    let target = try raw(words, at: 0x2000, name: calleeName)
    let summary = try #require(CalleeRegisterSummary.of(target))
    #expect(summary.provenArgumentReads.isEmpty && summary.provenFloatArgumentReads.isEmpty)
    #expect(summary.readsIncomingStack == (kind == "stack" || kind == "missing"))
    #expect(summary.argumentReads.isEmpty == (kind != "may" && kind != "mayTail"))
    // No GP/FP input value is known. A tail branch has no artificial result
    // fact either; the caller is explicitly a machine fragment, not x8 sret.
    var callerWords: [UInt32] = indirect
        ? (tail ? [0xb000001b, 0xd61f0360]
            : [0xf81f0ffe, 0xb000001b, 0xd63f0360, 0xf84107fe, 0xd65f03c0])
        : (tail ? [0x14000400] : [0xf81f0ffe, 0x940003ff, 0xf84107fe, 0xd65f03c0])
    if seedValue {
        callerWords.insert(0xd2800920, at: 0) // mov x0,#73: a live bookkeeping word, not a formal
        if !indirect { callerWords[tail ? 1 : 2] = tail ? 0x140003ff : 0x940003fe }
    }
    let caller = try raw(callerWords, at: 0x1000, name: "OUTLINED_FUNCTION_900")
    var summaries = [target.startAddress: summary,
                     caller.startAddress: try #require(CalleeRegisterSummary.of(caller))]
    var facts = CalleeRegisterFacts.finish(&summaries).facts
    if kind == "missing" { facts.removeValue(forKey: target.startAddress) }
    let resolver = Disassembler.ReferenceResolver(names: [0x1000: caller.symbol, 0x2000: target.symbol],
        stringRanges: [], machO: image, demangleSymbol: { _ in nil })
    let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [], goFunctions: goFunctions,
        objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:], selfIndex: SelfTypeIndex(bindings: [:]),
        vtableIndex: VTableIndex(), enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
        classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
        indirectResultUses: [target.startAddress: Disassembler.indirectResultUse(of: target)], registerSummaries: facts,
        asyncIndex: .empty, asyncChainSlots: [:])
    return Disassembler().analyzeFunction(caller, context: context)
}

@Test func anEmptyX8SnapshotDoesNotPromoteMAYReadsToParametersIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: x8ScratchImages[0]) else { return }
    try await withStableDependencies {
        for mode in [(false, false), (true, false), (false, true), (true, true)] {
            let body = try x8EmptyArityCaller("may", tail: mode.0, indirect: mode.1)
            let call = try #require(body.instructions.first { $0.controlFlow == .call || $0.controlFlow == .branch })
            // An opaque call can forward incoming words without proving any
            // concrete source count. Keep only the unknown extent, not eight
            // parameters from its MAY mask. Resolved BL wrappers remain under
            // the original policy exercised by PureTailInputTests.
            #expect(call.callArguments == ["…"], Comment(rawValue: body.renderStructured()))
            #expect(body.renderPseudo().contains("sub_2000(…)"), Comment(rawValue: body.renderPseudo()))
        }
    }
}

@Test func anEmptyX8SnapshotRetainsStackOnlyBodyInputsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: x8ScratchImages[0]) else { return }
    try await withStableDependencies {
        for mode in [(false, false), (true, false), (false, true), (true, true)] {
            let body = try x8EmptyArityCaller("stack", tail: mode.0, indirect: mode.1)
            let call = try #require(body.instructions.first { $0.controlFlow == .call || $0.controlFlow == .branch })
            #expect(call.callArguments == ["…"], Comment(rawValue: body.renderStructured()))
            #expect(body.renderPseudo().contains("sub_2000(…)"), Comment(rawValue: body.renderPseudo()))
            let zero = try x8EmptyArityCaller("zero", tail: mode.0, indirect: mode.1)
            #expect(zero.renderPseudo().contains("sub_2000()"), Comment(rawValue: zero.renderPseudo()))
            #expect(!zero.renderPseudo().contains("…"), Comment(rawValue: zero.renderPseudo()))
        }
    }
}


@Test func goX8ResolvedStackBranchesKeepTheirArgumentDeclineIfPresent() async throws {
    func baseName(_ name: String) -> String {
        let name = String(name.drop(while: { $0 == "_" }))
        return name.hasSuffix(".abi0") ? String(name.dropLast(5)) : name
    }
    for path in x8GoImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "runtime.reflectcall")
        }
        let caller = try #require(functions.first { function in
            function.instructions.contains {
                ($0.controlFlow == .call || $0.controlFlow == .branch)
                    && baseName(DisassembledFunction.calleeName(of: $0) ?? "") == "runtime.call16"
            }
        })
        let call = try #require(caller.instructions.first {
            ($0.controlFlow == .call || $0.controlFlow == .branch)
                && baseName(DisassembledFunction.calleeName(of: $0) ?? "") == "runtime.call16"
        })
        if call.callArguments != ["…"] {
            let targets = try await withStableDependencies {
                try await Disassembler().disassemble(path: path, functionFilter: "runtime.call16")
            }
            let target = try #require(targets.first { baseName($0.displayName) == "runtime.call16" })
            let summary = CalleeRegisterSummary.of(target)
            let detail = "Go stack-call decline lost; summary exists=\(summary != nil), MAY=\(String(describing: summary?.argumentReads)), stack=\(String(describing: summary?.readsIncomingStack)); " + caller.renderStructured()
            Issue.record(Comment(rawValue: detail))
        }
        #expect(call.callArguments == ["…"], Comment(rawValue: caller.renderPseudo()))
    }
}


@Test func anEmptyX8SnapshotWithAnUnavailableBodyKeepsUnknownArityIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: x8ScratchImages[0]) else { return }
    try await withStableDependencies {
        for mode in [(false, false), (true, false), (false, true), (true, true)] {
            let body = try x8EmptyArityCaller("missing", tail: mode.0, indirect: mode.1)
            let call = try #require(body.instructions.first { $0.controlFlow == .call || $0.controlFlow == .branch })
            #expect(call.callArguments == ["…"], Comment(rawValue: body.renderStructured()))
            #expect(body.renderPseudo().contains("sub_2000(…)"), Comment(rawValue: body.renderPseudo()))
        }
    }
}

@Test func anEmptyX8SnapshotRetainsRecursiveStackCallInputsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: x8ScratchImages[0]) else { return }
    let image = try BinaryLoader.load(path: x8ScratchImages[0])
    try await withStableDependencies {
        for indirect in [false, true] {
            // Read the caller's incoming stack before saving LR. The read is
            // positive input evidence even when every value remains unknown.
            // BL/BLR re-enters this function; an internal B would be a loop.
            let words: [UInt32] = indirect
                ? [0xf94003e9, 0xf81f0ffe, 0x9000001b, 0xd63f0360, 0xf84107fe, 0xd65f03c0]
                : [0xf94003e9, 0xf81f0ffe, 0x97fffffe, 0xf84107fe, 0xd65f03c0]
            let engine = try #require(CapstoneEngine())
            let decoded = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000)
            try #require(decoded.count == words.count)
            let function = DisassembledFunction(symbol: "OUTLINED_FUNCTION_900", demangledName: nil,
                startAddress: 0x1000, instructions: decoded.map(Disassembler.instruction(decoded:)), source: .address)
            var summaries = [function.startAddress: try #require(CalleeRegisterSummary.of(function))]
            let facts = CalleeRegisterFacts.finish(&summaries).facts
            #expect(facts[function.startAddress]?.readsIncomingStack == true)
            let resolver = Disassembler.ReferenceResolver(names: [0x1000: function.symbol], stringRanges: [],
                machO: image, demangleSymbol: { _ in nil })
            let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [],
                objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:], selfIndex: SelfTypeIndex(bindings: [:]),
                vtableIndex: VTableIndex(), enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
                classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
                registerSummaries: facts, asyncIndex: .empty, asyncChainSlots: [:])
            let body = Disassembler().analyzeFunction(function, context: context)
            let call = try #require(body.instructions.first { $0.controlFlow == .call })
            #expect(call.callArguments == ["…"], Comment(rawValue: body.renderStructured()))
            var loopWords = words
            loopWords[indirect ? 3 : 2] = indirect ? 0xd61f0360 : 0x17fffffe
            let loopDecoded = engine.disassemble(loopWords.withUnsafeBytes { Data($0) }, address: 0x1000)
            let loop = DisassembledFunction(symbol: function.symbol, demangledName: nil,
                startAddress: function.startAddress, instructions: loopDecoded.map(Disassembler.instruction(decoded:)), source: .address)
            let loopBody = Disassembler().analyzeFunction(loop, context: context)
            let branch = try #require(loopBody.instructions.first { $0.controlFlow == .branch })
            #expect(branch.callArguments == nil, Comment(rawValue: loopBody.renderStructured()))
        }
    }
}

@Test func anEmptyX8SnapshotKeepsTheRuntimeErrorRegisterLayoutIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: x8ScratchImages[0]) else { return }
    try await withStableDependencies {
        for mode in [(false, false), (true, false), (false, true), (true, true)] {
            let body = try x8EmptyArityCaller("missing", tail: mode.0, indirect: mode.1,
                calleeName: "swift_willThrow")
            let call = try #require(body.instructions.first { $0.controlFlow == .call || $0.controlFlow == .branch })
            // The existing runtime contract uses x21, not an unbounded GP
            // argument list. An unknown error value does not erase that ABI.
            #expect(call.callArguments == nil, Comment(rawValue: body.renderStructured()))
        }
    }
}

@Test func anEmptyX8SnapshotKeepsTheSwiftGetterFormalLayoutIfPresent() async throws {
    let path = "Fixtures/Sample/libStdSelf.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await withStableDependencies {
        let functions = try await Disassembler().disassemble(path: path)
        let calls = functions.flatMap(\.instructions).filter {
            ($0.controlFlow == .call || $0.controlFlow == .branch)
                && DisassembledFunction.calleeName(of: $0)?.hasPrefix("Swift._StringObject.sharedUTF8.getter") == true
        }
        #expect(!calls.isEmpty)
        for call in calls {
            // This imported Swift getter has no source formals. Its hidden
            // receiver follows the existing metadata layout, even when no
            // body or receiver value is available in the image.
            #expect(call.callArguments == nil, Comment(rawValue: call.annotation ?? call.text))
        }
    }
}

@Test func anEmptyX8SnapshotRetainsUnknownTailForwardedInputsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: x8ScratchImages[0]) else { return }
    try await withStableDependencies {
        for mode in [(false, false), (true, false), (false, true), (true, true)] {
            let body = try x8EmptyArityCaller("mayTail", tail: mode.0, indirect: mode.1)
            let call = try #require(body.instructions.first { $0.controlFlow == .call || $0.controlFlow == .branch })
            // Like a keypath thunk, the callee sets x3 and tail-forwards the
            // other incoming words. Their source count is still unknown.
            #expect(call.callArguments == ["…"], Comment(rawValue: body.renderStructured()))
            #expect(body.renderPseudo().contains("sub_2000(…)"), Comment(rawValue: body.renderPseudo()))
        }
    }
}

@Test func x8TailForwardingUncertaintySurvivesSummaryCopies() throws {
    let tail = try x8RawBody([0x90000003, 0x91000063, 0x14000800])
    let leaf = try x8RawBody([0x91000400, 0xd2800033, 0xd65f03c0], at: 0x3008)
    let originals = [tail.startAddress: tail, leaf.startAddress: leaf]
    let summary = try #require(CalleeRegisterSummary.of(tail, isFunction: { $0 == leaf.startAddress }))
    #expect(summary.hasOpaqueInputTransfer)
    #expect(summary.provenArgumentReads.isEmpty)
    #expect(summary.claimingNothing().hasOpaqueInputTransfer)
    let rebuilt = try #require(CalleeRegisterSummary.recomputingPreservation(tail,
        retainingReadsFrom: summary, calleeEffects: { _ in CalleeEffect() }))
    #expect(rebuilt.hasOpaqueInputTransfer)
    var summaries = [tail.startAddress: summary,
                     leaf.startAddress: try #require(CalleeRegisterSummary.of(leaf))]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[tail.startAddress]?.argumentReads == [0])
    #expect(summaries[tail.startAddress]?.provenArgumentReads.isEmpty == true)
    #expect(summaries[tail.startAddress]?.hasOpaqueInputTransfer == true)
    var recomputed = Set<UInt64>()
    CalleeRegisterSummary.closeOverCalls(&summaries) { address, effects, old, reusing in
        recomputed.insert(address)
        guard let body = originals[address] else { return nil }
        return CalleeRegisterSummary.recomputingPreservation(body, retainingReadsFrom: old,
            reusingPreservation: reusing, calleeEffects: effects,
            isFunction: { originals[$0] != nil })
    }
    #expect(recomputed.contains(tail.startAddress))
    let facts = CalleeRegisterFacts.finish(&summaries).facts
    #expect(facts[tail.startAddress]?.hasOpaqueInputTransfer == true)
    #expect(facts[leaf.startAddress]?.hasOpaqueInputTransfer == false)
    // An ordinary BL wrapper and an internal B supply no outgoing-tail fact.
    for words: [UInt32] in [[0x94000800, 0xd65f03c0], [0x14000000]] {
        let body = try x8RawBody(words)
        #expect(try #require(CalleeRegisterSummary.of(body, isFunction: { _ in true })).hasOpaqueInputTransfer == false)
    }
    // A pre-existing MAY mask can already be closed while the provenance of
    // its unknown extent is new. That fact must travel independently; it is
    // neither a concrete parameter prefix nor a reason to invent eight args.
    let relay = try x8RawBody([0x94000802, 0xd65f03c0])
    let opaque = try x8RawBody([0x94000800, 0xd65f03c0], at: 0x3008)
    let relayReads = try #require(CalleeRegisterSummary.of(relay, isFunction: { $0 == 0x3008 }))
    #expect(!relayReads.hasOpaqueInputTransfer)
    let opaqueSummary = try #require(CalleeRegisterSummary.of(opaque))
    var relayMay = CalleeRegisterSummary(argumentReads: RegisterSet(0..<8),
        pendingReads: relayReads.pendingReads, readsFramePointer: opaqueSummary.readsFramePointer,
        readsContextRegister: opaqueSummary.readsContextRegister, readsSelfRegister: opaqueSummary.readsSelfRegister,
        clobberedCalleeSaved: relayReads.clobberedCalleeSaved)
    relayMay.mayReadRegisters = opaqueSummary.mayReadRegisters
    var forwarded = [relay.startAddress: relayMay, opaque.startAddress: opaqueSummary]
    CalleeRegisterSummary.closeOverReads(&forwarded)
    #expect(forwarded[relay.startAddress]?.argumentCount == 8)
    #expect(forwarded[relay.startAddress]?.provenArgumentReads.isEmpty == true)
    #expect(forwarded[relay.startAddress]?.hasOpaqueInputTransfer == true)
}

@Test func x8OpaqueInputExtentStaysUnknownWhenADeclaredCalleeHasNoSummary() throws {
    // Summary-only caller reduction. The entry registry can know the target
    // while decoding/budget limits leave its body summary unavailable.
    let caller = try x8RawBody([0x94000802, 0xd65f03c0])
    let leaf = try x8RawBody([0x91000400, 0xd65f03c0], at: 0x3008)
    let initial = try #require(CalleeRegisterSummary.of(caller, isFunction: { $0 == leaf.startAddress }))
    #expect(initial.pendingReads.count == 1)
    #expect(initial.argumentReads.isEmpty && !initial.hasOpaqueInputTransfer)
    for hasBody in [false, true] {
        var summaries = [caller.startAddress: initial]
        if hasBody { summaries[leaf.startAddress] = try #require(CalleeRegisterSummary.of(leaf)) }
        CalleeRegisterSummary.closeOverReads(&summaries)
        let result = try #require(summaries[caller.startAddress])
        #expect(result.argumentCount == (hasBody ? 1 : 8))
        #expect(result.provenArgumentReads.isEmpty)
        // A missing body has an unknown extent. A present body that consumes
        // the forwarded word also leaves source arity unknown through BL;
        // neither case grants a positive parameter prefix to this caller.
        #expect(result.hasOpaqueInputTransfer)
        let facts = CalleeRegisterFacts.finish(&summaries).facts
        #expect(facts[caller.startAddress]?.hasOpaqueInputTransfer == true)
    }
    // Preserve an independently checked present/false control: this provider
    // overwrites x0 and takes no incoming GP or FP word.
    let zero = try x8RawBody([0xd2800b60, 0xd65f03c0], at: leaf.startAddress) // mov x0,#91; ret
    var noInputs = [caller.startAddress: initial,
                    zero.startAddress: try #require(CalleeRegisterSummary.of(zero))]
    CalleeRegisterSummary.closeOverReads(&noInputs)
    let zeroResult = try #require(noInputs[caller.startAddress])
    #expect(zeroResult.argumentCount == 0 && zeroResult.mayReadFloatArguments == 0)
    #expect(!zeroResult.hasOpaqueInputTransfer && zeroResult.provenArgumentReads.isEmpty)
    let zeroFacts = CalleeRegisterFacts.finish(&noInputs).facts
    #expect(zeroFacts[caller.startAddress]?.hasOpaqueInputTransfer == false)
}

private let x8GoStackGrowthNames = ["runtime.morestack", "runtime.morestack.abi0",
    "runtime.morestack_noctxt", "runtime.morestack_noctxt.abi0", "runtime.morestackc", "runtime.morestackc.abi0"]

@Test func goStackGrowthRegisterInputsAreNotSourceFormalsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: x8ScratchImages[0]) else { return }
    try await withStableDependencies {
        for name in x8GoStackGrowthNames {
            for mode in [(false, false), (true, false), (false, true), (true, true)] {
                for seeded in [false, true] {
                    let table = GoFunctionTable(entries: [(0x2000, name)])
                    let body = try x8EmptyArityCaller("missing", tail: mode.0, indirect: mode.1,
                        calleeName: name, goFunctions: table, seedValue: seeded)
                    let call = try #require(body.instructions.first { $0.controlFlow == .call || $0.controlFlow == .branch })
                    #expect(call.callArguments == nil, Comment(rawValue: body.renderStructured()))
                    #expect(body.renderPseudo().contains(name + "()"), Comment(rawValue: body.renderPseudo()))
                }
            }
        }
        // A spelling is not a Go runtime contract. Neither another Go entry,
        // an interior address nor a near-miss runtime name proves zero formals.
        let controls: [(GoFunctionTable?, String)] = [
            (nil, "runtime.morestack_noctxt"),
            (GoFunctionTable(entries: [(0x2000, "main.store9")]), "runtime.morestack_noctxt"),
            (GoFunctionTable(entries: [(0x2004, "runtime.morestack_noctxt")]), "runtime.morestack_noctxt"),
            (GoFunctionTable(entries: [(0x2000, "runtime.morestack_noctxtExtra")]), "runtime.morestack_noctxtExtra")]
        for (table, name) in controls {
            let body = try x8EmptyArityCaller("missing", tail: false, calleeName: name, goFunctions: table)
            let call = try #require(body.instructions.first { $0.controlFlow == .call })
            #expect(call.callArguments == ["…"], Comment(rawValue: body.renderPseudo()))
        }
    }
}
