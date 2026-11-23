import Foundation
import Testing
@_spi(Internals) import SwiftInspection
@testable import SwiftDecompilerCore

private let projectionClientPaths = [
    "Fixtures/Sample/libBoxedProjectionClient.dylib",
    "Fixtures/Sample/libBoxedProjectionClient.stripped.dylib",
]

private let projectionCallerNames = [
    "boxedProjectionForeignDirect", "boxedProjectionForeignIndirect",
    "boxedProjectionGenuineOptimized", "boxedProjectionGenuineDebug",
    "boxedProjectionGenuineIndirect", "boxedProjectionMutatingLookalike",
    "boxedProjectionMutableCall",
]

private func projectionContractStages(_ path: String) async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    let symbols = image.symbols.filter { projectionCallerNames.contains(String($0.name.dropFirst())) }
    let entries = Set(symbols.map { UInt64($0.offset) })
    try #require(entries.count == projectionCallerNames.count)
    var stages: [[DisassembledFunction]] = []
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: path)
            case 1: return try await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: path, functionFilter: "boxedProjection")
            case 3:
                let selected: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                    machO: image, transform: { entries.contains($0.startAddress) ? $0 : nil })
                return selected.compactMap { $0 }
            default:
                return Array(await Disassembler().analyzeEachFunction(at: entries, in: image, transform: { $0 }).values)
            }
        }
        let selected = functions.filter { entries.contains($0.startAddress) }.sorted { $0.startAddress < $1.startAddress }
        try #require(selected.count == entries.count)
        stages.append(selected)
    }
    return stages
}

private func projectionProcess(_ path: String, arguments: [String] = []) throws -> (Int32, String, String) {
    let process = Process(), output = Pipe(), error = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let errors = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: bytes, as: UTF8.self), String(decoding: errors, as: UTF8.self))
}

@Test func boxedProjectionNativeControlsAndImportEvidenceIfPresent() throws {
    let programs = [
        ("Fixtures/Sample/boxed-projection-O0-oracle", "PASS 7 projection-call observations\n"),
        ("Fixtures/Sample/boxed-projection-O2-oracle", "PASS 7 projection-call observations\n"),
        ("Fixtures/Sample/boxed-projection-Os-oracle", "PASS 7 projection-call observations\n"),
        ("Fixtures/Sample/boxed-projection-control-O0-oracle", "PASS 36 projection pointer and no-write observations\n"),
        ("Fixtures/Sample/boxed-projection-control-O2-oracle", "PASS 36 projection pointer and no-write observations\n"),
        ("Fixtures/Sample/boxed-projection-control-Os-oracle", "PASS 36 projection pointer and no-write observations\n"),
    ]
    for (path, expected) in programs {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let (exit, output, errors) = try projectionProcess(URL(fileURLWithPath: path).path)
        #expect(exit == 0, Comment(rawValue: path + "\n" + errors))
        #expect(output == expected, Comment(rawValue: path + "\n" + output))
    }
    guard FileManager.default.fileExists(atPath: projectionClientPaths[0]) else { return }
    let (exit, symbols, _) = try projectionProcess("/usr/bin/xcrun", arguments: ["nm", "-m", "-arch", "arm64", projectionClientPaths[0]])
    #expect(exit == 0)
    let imported = symbols.split(separator: "\n").filter {
        $0.contains("___swift_project_boxed_opaque_existential_0 (from libBoxedProjectionForeignProvider)")
    }
    #expect(imported.count == 1)
    #expect(imported.first?.contains("(undefined) external") == true)
    #expect(imported.first?.contains("weak") == false)
    let (rawExit, raw, _) = try projectionProcess("/usr/bin/xcrun", arguments: [
        "llvm-objdump", "--macho", "--disassemble", "Fixtures/Sample/libBoxedProjectionForeignProvider.dylib",
    ])
    #expect(rawExit == 0)
    #expect(raw.range(of: #"mov\s+w8, #0x29"#, options: .regularExpression) != nil, Comment(rawValue: raw))
    #expect(raw.range(of: #"str\s+w8, \[x0\]"#, options: .regularExpression) != nil, Comment(rawValue: raw))
}

@Test func unprovedBoxedProjectionNamesDoNotPreserveMemoryOrHideCallsAcrossAllAPIsIfPresent() async throws {
    let negative = ["boxedProjectionForeignDirect", "boxedProjectionForeignIndirect", "boxedProjectionMutatingLookalike"]
    for path in projectionClientPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for functions in try await projectionContractStages(path) {
            for name in negative {
                let function = try #require(functions.first { $0.symbol == "_" + name })
                let consumer = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "boxedProjectionConsumeWord"
                })
                #expect(consumer.callArguments != ["7"], Comment(rawValue: function.render()))
                let helpers = function.instructions.filter {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) != "boxedProjectionConsumeWord"
                }
                try #require(helpers.count == 1)
                let helper = try #require(helpers.first)
                #expect(!helper.facts.bodyProjectsBoxedExistential, Comment(rawValue: function.render()))
                let callee: String
                if let named = DisassembledFunction.calleeName(of: helper) {
                    callee = named
                } else {
                    // Indexed analysis need not name an unselected, stripped
                    // near-shape body. Its exact direct target remains an effect.
                    try #require(name == "boxedProjectionMutatingLookalike")
                    let target = try #require(helper.branchTarget)
                    callee = "sub_" + String(target, radix: 16)
                }
                for text in [function.renderPseudo(), function.renderStructured()] {
                    let context = Comment(rawValue: path + "\n" + text)
                    #expect(!text.contains("boxedProjectionConsumeWord(7)"), context)
                    #expect(text.components(separatedBy: callee + "(").count == 2, context)
                    if name != "boxedProjectionMutatingLookalike" {
                        #expect(text.contains(callee + "(…)"), context)
                    }
                }
            }
            let mutable = try #require(functions.first { $0.symbol == "_boxedProjectionMutableCall" })
            let mutableCall = try #require(mutable.instructions.first {
                $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) != "boxedProjectionConsumeWord"
            })
            #expect(!mutableCall.facts.bodyProjectsBoxedExistential)
            #expect(!mutable.renderPseudo().contains("boxedProjectionConsumeWord(7)"))
            #expect(!mutable.renderStructured().contains("boxedProjectionConsumeWord(7)"))
        }
    }
}

@Test func genuineBoxedProjectionBodiesPreserveMemoryAcrossAllAPIsIfPresent() async throws {
    let positive = ["boxedProjectionGenuineOptimized", "boxedProjectionGenuineDebug", "boxedProjectionGenuineIndirect"]
    for path in projectionClientPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for functions in try await projectionContractStages(path) {
            for name in positive {
                let function = try #require(functions.first { $0.symbol == "_" + name })
                let consumer = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "boxedProjectionConsumeWord"
                })
                let helper = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) != "boxedProjectionConsumeWord"
                })
                #expect(helper.facts.bodyProjectsBoxedExistential, Comment(rawValue: function.render()))
                #expect(consumer.callArguments == ["7"], Comment(rawValue: function.render()))
                for text in [function.renderPseudo(), function.renderStructured()] {
                    #expect(text.contains("boxedProjectionConsumeWord(7)"), Comment(rawValue: path + "\n" + text))
                }
            }
        }
    }
}

private func projectionTraceBody(proven: Bool) throws -> DisassembledFunction {
    // Save fp/lr; local=7; x0=&local; call helper; load local; consume; restore; ret.
    let words: [UInt32] = [
        0xa9be7bfd, 0x528000e8, 0xb90013e8, 0x910043e0, 0x940007fc,
        0xb94013e0, 0x94000bfa, 0xa8c27bfd, 0xd65f03c0,
    ]
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let engine = try #require(CapstoneEngine())
    let decoded = engine.disassemble(bytes, address: 0x1000)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_projectionTrace", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map { item in
            var facts = Instruction.Facts()
            facts.bodyProjectsBoxedExistential = item.address == 0x1010 && proven
            let callee = item.address == 0x1010 ? "__swift_project_boxed_opaque_existential_0"
                : item.address == 0x1018 ? "M.consume(Swift.Int) -> ()" : nil
            return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                branchTarget: item.branchTarget, detail: item.detail, callee: .kept(callee), facts: facts)
        }, source: .address)
}

@Test func boxedProjectionBodyProofDoesNotComeFromNamesOrOtherContracts() {
    for name in ["__swift_project_boxed_opaque_existential", "__swift_project_boxed_opaque_existential_0",
                 "__swift_project_boxed_opaque_existential_500Tm", "__swift_project_boxed_opaque_existential_forged"] {
        let unproven = ValueTracer.CallFacts(callee: name, arcIdentityContract: true,
            bodyPreservesSwiftError: true, nonThrowingABIContract: true, namedABIContract: true)
        #expect(!unproven.readsOnly)
        #expect(!unproven.writesNoFields)
        let proven = ValueTracer.CallFacts(callee: name, knownArityApplies: false, bodyProjectsBoxedExistential: true)
        #expect(proven.readsOnly)
        #expect(proven.writesNoFields)
    }
    // Body memory evidence does not turn this alias into libSystem's zero-
    // argument declaration, a C result-bank proof or an ARC identity helper.
    let alias = ValueTracer.CallFacts(callee: "getpid", bodyProjectsBoxedExistential: true)
    #expect(alias.cResult == nil)
    #expect(alias.passedRegisters.contains(.x(0)))
    #expect(alias.passedRegisters.contains(.x(8)))
    #expect(!alias.returnsArgument)
}

@Test func boxedProjectionMemoryEffectsStayIsolatedAcrossCachesAndInImageCalls() throws {
    for order in [[true, false, true], [false, true, false]] {
        for cached in [false, true] {
            for inImage in [false, true] {
                let cache = cached ? ValueTracer.CallFactsCache() : nil
                for proven in order {
                    let function = try projectionTraceBody(proven: proven)
                    var tracer = ValueTracer()
                    tracer.callFactsCache = cache
                    tracer.inImageCallTargets = inImage ? [0x3000] : []
                    let analysis = tracer.analyze(function, entry: .swiftFunction(scalarArguments: [:]))
                    let consumer = try #require(analysis.callSites[0x1018])
                    #expect((consumer.arguments.first == .immediate(7)) == proven)
                    let helper = try #require(function.instructions.first { $0.address == 0x1010 })
                    let facts = ValueTracer.FunctionFacts(function, cache: cache, inImageTargets: tracer.inImageCallTargets).call(helper)
                    #expect(facts.readsOnly == proven)
                    #expect(facts.writesNoFields == proven)
                }
            }
        }
    }
}

@Test func boxedProjectionInstructionCopiesKeepTypedEvidenceApartFromAnnotations() throws {
    let function = try projectionTraceBody(proven: true)
    let original = try #require(function.instructions.first { $0.address == 0x1010 })
    let copy = Instruction(address: original.address, text: original.text,
        annotation: "an unrelated literal contains → arbitraryName  args(41)",
        controlFlow: original.controlFlow, branchTarget: original.branchTarget, detail: original.detail,
        callee: .kept(original.callee), facts: original.facts)
    #expect(copy.facts.bodyProjectsBoxedExistential)
    #expect(ValueTracer.CallFacts(copy).readsOnly)
    let noteOnly = Instruction(address: original.address, text: original.text,
        annotation: "→ __swift_project_boxed_opaque_existential_0  bodyProjectsBoxedExistential=true",
        controlFlow: .call, branchTarget: 0x3000, callee: .kept(nil))
    #expect(!ValueTracer.CallFacts(noteOnly).readsOnly)
}

@Test func unprovedProjectionCallsRemainStatementsAndValues() throws {
    for name in ["__swift_project_boxed_opaque_existential_0",
                 "M.project_boxed_opaque_existential_user(Swift.Int) -> Swift.Int"] {
        let call = Instruction(address: 0x1000, text: "bl 0x3000", controlFlow: .call,
            branchTarget: 0x3000, callArguments: ["7"], callee: .kept(name))
        #expect(DisassembledFunction.isGenericPlumbingCallee(name)) // Candidate classification only.
        #expect(!DisassembledFunction.isGenericPlumbingCallee(call))
        let statement = try #require(DisassembledFunction.callStatement(of: call, hideRuntime: true))
        #expect(statement.contains("project_boxed_opaque_existential"))
        #expect(statement.contains("7"))
    }
}

@Test func boxedProjectionBodyDiscoveryChecksNamedAndUnnamedWholeBodiesIfPresent() async throws {
    let path = projectionClientPaths[0]
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        let disassembler = Disassembler()
        var labels: [UInt64: String] = [:]
        for symbol in image.symbols { labels[UInt64(symbol.offset)] = symbol.name }
        func address(_ suffix: String) throws -> UInt64 {
            let name = "___swift_project_boxed_opaque_existential_" + suffix
            return UInt64(try #require(image.symbols.first { $0.name == name }).offset)
        }
        let optimized = try address("1"), debug = try address("2"), lookalike = try address("3")
        let boundaries = Set(disassembler.functionStarts(of: image)).union(labels.keys).sorted()
        for named in [false, true] {
            let chosen = named ? labels : [:]
            let result = disassembler.recognizedHelpers(in: image, boundaries: boundaries, labels: chosen)
            #expect(result.boxedExistentialProjections == [optimized, debug])
            #expect(!result.boxedExistentialProjections.contains(lookalike))
            if named {
                #expect(result.names.keys.allSatisfy { labels[$0] == nil })
            } else {
                #expect(result.names[optimized] == "__swift_project_boxed_opaque_existential")
                #expect(result.names[debug] == "__swift_project_boxed_opaque_existential")
            }
        }
        let cut = boundaries + [optimized + 32]
        let partial = disassembler.recognizedHelpers(in: image, boundaries: Array(Set(cut)).sorted(), labels: labels)
        #expect(!partial.boxedExistentialProjections.contains(optimized))
        #expect(partial.boxedExistentialProjections.contains(debug))
        #expect(!partial.boxedExistentialProjections.contains(optimized + 4))
    }
}

@Test func boxedProjectionBodyEditsCannotKeepTheMemoryProofIfPresent() async throws {
    let path = projectionClientPaths[0]
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        let optimized = UInt64(try #require(image.symbols.first { $0.name == "___swift_project_boxed_opaque_existential_1" }).offset)
        let debug = UInt64(try #require(image.symbols.first { $0.name == "___swift_project_boxed_opaque_existential_2" }).offset)
        let original = try Data(contentsOf: URL(fileURLWithPath: path))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("projection-body-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let branchFileOffset = try #require(image.fileOffset(of: optimized + 8))
        let branchOffset = try #require(Int(exactly: branchFileOffset))
        var branch: UInt32 = 0
        for lane in 0..<4 {
            let byte = UInt32(original[branchOffset + lane])
            branch |= byte << (lane * 8)
        }
        // Redirect the guarded return, replace a read with a write, narrow the
        // payload pointer read, and remove the terminal return independently.
        for (index, word) in [(2, branch ^ 0x20), (3, UInt32(0xf9000009)),
                              (3, UInt32(0xb9400009)), (8, UInt32(0xd503201f))] {
            var bytes = original
            let fileOffset = try #require(image.fileOffset(of: optimized + UInt64(index * 4)))
            let offset = try #require(Int(exactly: fileOffset))
            try #require(original.count >= 4 && offset >= 0 && offset <= original.count - 4)
            bytes.replaceSubrange(offset..<(offset + 4), with: (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) })
            let file = directory.appendingPathComponent(UUID().uuidString + ".dylib")
            try bytes.write(to: file)
            let altered = try BinaryLoader.load(path: file.path)
            var labels: [UInt64: String] = [:]
            for symbol in altered.symbols { labels[UInt64(symbol.offset)] = symbol.name }
            let disassembler = Disassembler()
            let boundaries = Set(disassembler.functionStarts(of: altered)).union(labels.keys).sorted()
            let proof = disassembler.recognizedHelpers(in: altered, boundaries: boundaries, labels: labels)
            #expect(!proof.boxedExistentialProjections.contains(optimized))
            #expect(proof.boxedExistentialProjections.contains(debug))
        }
    }
}

@Test func boxedProjectionResolverRequiresAnExactEntryAndAFixedPointerIfPresent() async throws {
    let path = projectionClientPaths[0]
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        let target = UInt64(try #require(image.symbols.first { $0.name == "___swift_project_boxed_opaque_existential_1" }).offset)
        let mutable = UInt64(try #require(image.symbols.first { $0.name == "_boxedProjectionMutableSlot" }).offset)
        let constant = try #require(image.sections.first { $0.segmentName == "__DATA_CONST" && $0.sectionName == "__const" })
        #expect(constant.size == 8)
        let resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: image,
            demangleSymbol: { _ in nil }, boxedExistentialProjectionBodies: [target])
        #expect(resolver.bodyProjectsBoxedExistential(at: target))
        #expect(!resolver.bodyProjectsBoxedExistential(at: target + 4))
        #expect(resolver.bodyProjectsBoxedExistential(for: .address(target)))
        #expect(resolver.bodyProjectsBoxedExistential(for: .immediate(target)))
        #expect(resolver.bodyProjectsBoxedExistential(for: .loaded(UInt64(constant.address))))
        #expect(!resolver.bodyProjectsBoxedExistential(for: .loaded(mutable)))
        #expect(!resolver.bodyProjectsBoxedExistential(for: .argument(0)))
    }
}

@Test func lateProjectionProofChangesRetraceIndependentlyOfErrorPreservationIfPresent() async throws {
    let path = projectionClientPaths[0]
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        let target = UInt64(try #require(image.symbols.first { $0.name == "___swift_project_boxed_opaque_existential_1" }).offset)
        let fileOffset = try #require(image.fileOffset(of: target))
        let offset = try #require(Int(exactly: fileOffset))
        let original = try Data(contentsOf: URL(fileURLWithPath: path))
        try #require(original.count >= 36 && offset >= 0 && offset <= original.count - 36)
        let engine = try #require(CapstoneEngine())
        let decodedHelper = engine.disassemble(Data(original[offset..<(offset + 36)]), address: 0x3000)
        let helper = DisassembledFunction(symbol: "___swift_project_boxed_opaque_existential_1", demangledName: nil,
            startAddress: 0x3000, instructions: decodedHelper.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .symbol)
        let summary = try #require(CalleeRegisterSummary.of(helper))
        var summaries = [UInt64(0x3000): summary]
        let errorProof = CalleeRegisterFacts.finish(&summaries, body: { $0 == 0x3000 ? helper : nil }).facts
        try #require(errorProof[0x3000]?.bodyPreservesSwiftError == true)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("projection-late-\(UUID().uuidString).o")
        let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
        var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        data.append(Data(count: 1024 - data.count))
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let emptyImage = try BinaryLoader.load(path: file.path)
        for resolved in [true, false] {
            let resolver = Disassembler.ReferenceResolver(
                names: [0x3000: "__swift_project_boxed_opaque_existential_1"], stringRanges: [],
                machO: emptyImage, demangleSymbol: { _ in nil },
                boxedExistentialProjectionBodies: resolved ? [0x3000] : []).withSwiftErrorBodyProofs(errorProof)
            let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [],
                objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
                selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
                enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
                classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
            // The body/error bit is already present and remains true. Only
            // the independent projection proof changes at this indirect call.
            let words: [UInt32] = [
                0xa9be7bfd, 0x528000e8, 0xb90013e8, 0x910043e0, 0x1000ff90,
                0xd63f0200, 0xb94013e0, 0x94000bf9, 0xa8c27bfd, 0xd65f03c0,
            ]
            let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
            let instructions = engine.disassemble(bytes, address: 0x1000).map { item in
                var facts = Instruction.Facts()
                facts.bodyPreservesSwiftError = item.address == 0x1014
                facts.bodyProjectsBoxedExistential = item.address == 0x1014 && !resolved
                return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                    branchTarget: item.branchTarget, detail: item.detail,
                    callee: .kept(item.address == 0x101c ? "M.consume(Swift.Int) -> Swift.Int" : nil), facts: facts)
            }
            let input = DisassembledFunction(symbol: "_lateProjectionProof", demangledName: "M.lateProjection() -> Swift.Int",
                startAddress: 0x1000, instructions: instructions, source: .symbol)
            let function = Disassembler().analyzeFunction(input, context: context)
            let call = try #require(function.instructions.first { $0.address == 0x1014 })
            #expect(call.facts.bodyPreservesSwiftError)
            #expect(!call.facts.nonThrowingABIContract)
            #expect(!call.facts.namedABIContract)
            #expect(call.facts.bodyProjectsBoxedExistential == resolved)
            let consumer = try #require(function.instructions.first { $0.address == 0x101c })
            #expect((consumer.callArguments == ["7"]) == resolved, Comment(rawValue: function.render()))
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("M.consume(7)") == resolved, Comment(rawValue: text))
            }
        }
    }
}

@Test func anUnprovedProjectionNameStillDenotesItsResultInTextConditions() throws {
    // Save the return address, call a regular Swift Int function, branch on
    // its result, and return 1 or 2. No tracer-supplied condition is present.
    let words: [UInt32] = [
        0xa9bf7bfd, 0x940007ff, 0xb4000080, 0x52800020, 0xa8c17bfd,
        0xd65f03c0, 0x52800040, 0xa8c17bfd, 0xd65f03c0,
    ]
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let engine = try #require(CapstoneEngine())
    let decoded = engine.disassemble(bytes, address: 0x1000)
    let name = "M.project_boxed_opaque_existential_user(Swift.Int) -> Swift.Int"
    let function = DisassembledFunction(symbol: "_projectionTextCondition", demangledName: nil,
        startAddress: 0x1000, instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, callArguments: $0.controlFlow == .call ? ["arg0"] : nil,
                detail: $0.detail, callee: .kept($0.controlFlow == .call ? name : nil))
        }, source: .symbol)
    let text = function.renderStructured()
    let expression = "M.project_boxed_opaque_existential_user(arg0)"
    #expect(text.contains("if (" + expression) || text.contains("if (!" + expression), Comment(rawValue: text))
    #expect(text.components(separatedBy: "project_boxed_opaque_existential_user(").count == 2, Comment(rawValue: text))
}

@Test func anUnprovedProjectionResultIsEvaluatedOnceBeforeAnInterveningEffect() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("projection-order-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: file.path)
        let name = "M.project_boxed_opaque_existential_user() -> Swift.Int"
        let resolver = Disassembler.ReferenceResolver(names: [0x3000: name, 0x4000: "M.effect() -> ()"],
            stringRanges: [], machO: image, demangleSymbol: { _ in nil })
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [],
            objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
            selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
            enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
            classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
        // Preserve x19, save the call result there, run an effect, add the
        // saved result to itself and restore the incoming registers.
        let words: [UInt32] = [
            0xa9be7bfd, 0xf9000bf3, 0x940007fe, 0xaa0003f3, 0x94000bfc,
            0x8b130260, 0xf9400bf3, 0xa8c27bfd, 0xd65f03c0,
        ]
        let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        let engine = try #require(CapstoneEngine())
        let instructions = engine.disassemble(bytes, address: 0x1000).map { item in
            Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                branchTarget: item.branchTarget, detail: item.detail,
                callee: .kept(item.branchTarget.flatMap { resolver.names[$0] }))
        }
        let input = DisassembledFunction(symbol: "_projectionResultOrder", demangledName: "M.useProjectionName() -> Swift.Int",
            startAddress: 0x1000, instructions: instructions, source: .symbol)
        let function = Disassembler().analyzeFunction(input, context: context)
        let producer = try #require(function.instructions.first { $0.address == 0x1008 })
        #expect(producer.binding != nil, Comment(rawValue: function.render()))
        for text in [function.renderPseudo(), function.renderStructured()] {
            let context = Comment(rawValue: text)
            #expect(text.components(separatedBy: "project_boxed_opaque_existential_user(").count == 2, context)
            let before = try #require(text.range(of: "project_boxed_opaque_existential_user("))
            let after = try #require(text.range(of: "M.effect()"))
            #expect(before.lowerBound < after.lowerBound, context)
        }
    }
}
