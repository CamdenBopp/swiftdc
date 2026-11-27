import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let namedABILevels = [
    ("Onone", "Fixtures/Sample/libPlainErrorABI.Onone.dylib", "Fixtures/Sample/libPlainErrorABI.Onone.stripped.dylib",
     "Fixtures/Sample/libPlainErrorSystem.Onone.dylib", "Fixtures/Sample/libPlainErrorSystem.Onone.stripped.dylib",
     "Fixtures/Sample/plain-error-abi-Onone-caller.ll", "Fixtures/Sample/plain-error-abi-Onone-oracle"),
    ("O", "Fixtures/Sample/libPlainErrorABI.O.dylib", "Fixtures/Sample/libPlainErrorABI.O.stripped.dylib",
     "Fixtures/Sample/libPlainErrorSystem.O.dylib", "Fixtures/Sample/libPlainErrorSystem.O.stripped.dylib",
     "Fixtures/Sample/plain-error-abi-O-caller.ll", "Fixtures/Sample/plain-error-abi-O-oracle"),
    ("Osize", "Fixtures/Sample/libPlainErrorABI.Osize.dylib", "Fixtures/Sample/libPlainErrorABI.Osize.stripped.dylib",
     "Fixtures/Sample/libPlainErrorSystem.Osize.dylib", "Fixtures/Sample/libPlainErrorSystem.Osize.stripped.dylib",
     "Fixtures/Sample/plain-error-abi-Osize-caller.ll", "Fixtures/Sample/plain-error-abi-Osize-oracle"),
]

private func namedABIImportProvider(_ image: MachOFile, symbol name: String = "getpid") throws -> String {
    let symbol = try #require(image.symbols.first { $0.name == "_" + name && $0.offset == 0 })
    let description = try #require(symbol.nlist.symbolDescription)
    #expect(image.header.flags.contains(.twolevel))
    #expect(!image.header.flags.contains(.force_flat))
    #expect(description.libraryOrdinalType == nil)
    let libraries = Array(image.dependencies)
    let index = Int(description.libraryOrdinal) - 1
    try #require(libraries.indices.contains(index))
    return libraries[index].dylib.name
}

private func namedABIStages(path: String, image: MachOFile, entries: Set<UInt64>, filter: String) async throws -> [[DisassembledFunction]] {
    var stages: [[DisassembledFunction]] = []
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: path)
            case 1: return await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: path, functionFilter: filter)
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

@Test func foreignNamedCImportsDoNotBorrowSDKArityAcrossAllAPIsIfPresent() async throws {
    for (level, normal, stripped, _, _, callerIR, native) in namedABILevels {
        guard FileManager.default.fileExists(atPath: normal) else { continue }
        let ir = try String(contentsOfFile: callerIR, encoding: .utf8)
        let declarations = ir.split(separator: "\n").filter { $0.hasPrefix("declare ") && $0.contains("@getpid(") }
        let declaration = try #require(declarations.first)
        #expect(declarations.count == 1)
        #expect(declaration.contains("swiftcc i64") && declaration.contains("@getpid(i64") && declaration.contains("swifterror"))
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: native)
        process.standardOutput = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: bytes, as: UTF8.self) == "PASS 114 native plain-name Swift error and system C observations\n")
        for path in [normal, stripped] {
            let image = try BinaryLoader.load(path: path)
            #expect(try namedABIImportProvider(image) == "@rpath/libPlainErrorProvider.\(level).dylib")
            // Entries come from independent export symbols, not a preliminary SUT render.
            let entries = Set(image.symbols.filter { $0.name.hasPrefix("_$s13PlainErrorABI") && $0.name.contains("CatalogProbe") }.map { UInt64($0.offset) })
            try #require(entries.count == 2)
            for functions in try await namedABIStages(path: path, image: image, entries: entries, filter: "CatalogProbe") {
                for function in functions {
                    let calls = function.instructions.filter { $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "getpid" }
                    try #require(calls.count == 1)
                    for text in [function.renderStructured(), function.renderPseudo()] {
                        let context = Comment(rawValue: path + "\n" + text)
                        #expect(text.components(separatedBy: "getpid(").count == 2, context)
                        // The raw symbol does not identify libSystem's zero-formal ABI.
                        // Unknown source placement may decline, but cannot claim no inputs.
                        #expect(!text.contains("getpid()"), context)
                    }
                }
            }
        }
    }
}

@Test func realSystemImportsRetainSDKArityAcrossAllAPIsIfPresent() async throws {
    for (_, _, _, normal, stripped, _, _) in namedABILevels {
        for path in [normal, stripped] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            #expect(try namedABIImportProvider(image) == "/usr/lib/libSystem.B.dylib")
            let entries = Set(image.symbols.filter { $0.name.hasPrefix("_$s16PlainErrorSystem") && $0.name.contains("typed") }.map { UInt64($0.offset) })
            try #require(entries.count == 1)
            for functions in try await namedABIStages(path: path, image: image, entries: entries, filter: "typedSystem") {
                let function = try #require(functions.first)
                for text in [function.renderStructured(), function.renderPseudo()] {
                    #expect(text.contains("getpid()"), Comment(rawValue: path + "\n" + text))
                }
            }
        }
    }
}

@Test func namedCPrototypeFactsRequireTheirOwnBindingEvidence() throws {
    for name in ["getpid", "sqrt", "free", "CGRectInset", "printf", "swift_deallocClassInstance"] {
        let declaration = try #require(DisassembledFunction.cPrototype(of: name))
        let foreign = ValueTracer.CallFacts(callee: name, bodyPreservesSwiftError: true,
            nonThrowingABIContract: true)
        #expect(foreign.provablyDoesNotThrow)
        #expect(foreign.cResult == nil, Comment(rawValue: name))
        #expect(!foreign.passesNoStackArguments, Comment(rawValue: name))
        #expect(foreign.passedRegisters.contains(.x(0)), Comment(rawValue: name))
        let bound = ValueTracer.CallFacts(callee: name, namedABIContract: true)
        #expect(bound.cResult == ValueTracer.CallFacts.result(of: declaration), Comment(rawValue: name))
        #expect(DisassembledFunction.cPrototype(of: name, namedABIContract: false) == nil)
        #expect(DisassembledFunction.cPrototype(of: name, namedABIContract: true) == declaration)
    }
}

@Test func namedABIContractCacheDoesNotDonateAPrototypeFromAnotherBinding() {
    for order in [[true, false], [false, true]] {
        let cache = ValueTracer.CallFactsCache()
        for binding in order {
            let facts = cache.facts(for: "getpid", bodyPreservesSwiftError: true,
                nonThrowingABIContract: true, namedABIContract: binding)
            #expect(facts.provablyDoesNotThrow)
            #expect((facts.cResult != nil) == binding)
            #expect(facts.passedRegisters.contains(.x(0)) == !binding)
            #expect(facts.passesNoStackArguments == binding)
        }
    }
}

@Test func namedABIContractInstructionCopiesKeepDeclarationEvidence() {
    var facts = Instruction.Facts()
    facts.bodyPreservesSwiftError = true
    facts.nonThrowingABIContract = true
    let foreign = Instruction(address: 0x1000, text: "bl 0x2000", controlFlow: .call,
        branchTarget: 0x2000, callee: .kept("getpid"), facts: facts)
    #expect(!DisassembledFunction.hasNamedABIContract(foreign))
    #expect(ValueTracer.CallFacts(foreign).cResult == nil)
    facts.namedABIContract = true
    let bound = Instruction(address: foreign.address, text: foreign.text, controlFlow: foreign.controlFlow,
        branchTarget: foreign.branchTarget, callee: .kept(foreign.callee), facts: facts)
    #expect(DisassembledFunction.hasNamedABIContract(bound))
    #expect(ValueTracer.CallFacts(bound).cResult != nil)
    #expect(!ValueTracer.CallFacts(bound).passedRegisters.contains(.x(0)))
}

@Test func namedABIBindingDoesNotReplaceARCIdentityEvidence() {
    let foreign = ValueTracer.CallFacts(callee: "objc_retain", namedABIContract: true)
    #expect(!foreign.namedABIContract)
    #expect(foreign.cResult == nil)
    #expect(!foreign.returnsArgument)
    let arc = ValueTracer.CallFacts(callee: "objc_retain", arcIdentityContract: true)
    #expect(arc.namedABIContract)
    #expect(arc.cResult != nil)
    #expect(arc.returnsArgument)
    #expect(arc.passedRegisters == [.x(0)])
}

@Test func languageAritiesRemainIndependentOfLibraryBindings() {
    for name in ["_ZSt9terminatev", "lazy protocol witness table accessor for M.T : M.P in M",
                 "M.value.unsafeMutableAddressor : Swift.Int"] {
        #expect(DisassembledFunction.knownCArity(of: name, namedABIContract: false) == 0)
    }
    #expect(DisassembledFunction.knownCArity(of: "destroy value witness for M.T", namedABIContract: false) == 2)
    #expect(DisassembledFunction.knownCArity(of: "getpid", namedABIContract: false) == nil)
    #expect(DisassembledFunction.knownCArity(of: "getpid", namedABIContract: true) == 0)
    #expect(DisassembledFunction.knownCArity(of: "_ZN3Foo3barEv", namedABIContract: false) == nil)
}

@Test func fallbackWordResultChecksRequireTheRuntimeBinding() throws {
    let engine = try #require(CapstoneEngine())
    // No tracer condition: the text fallback reads a saved call result's w view.
    let words: [UInt32] = [0x94000040, 0xaa0003fa, 0x7100075f, 0x54000061,
                           0x52800020, 0xd65f03c0, 0x52800040, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    for binding in [false, true] {
        let instructions = decoded.enumerated().map { index, decoded -> Instruction in
            let insn = Disassembler.instruction(decoded: decoded)
            guard index == 0 else { return insn }
            var facts = insn.facts
            facts.bodyPreservesSwiftError = true
            facts.nonThrowingABIContract = true
            facts.namedABIContract = binding
            return Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                branchTarget: insn.branchTarget, detail: insn.detail,
                callee: .kept("swift_getEnumCaseMultiPayload"), facts: facts)
        }
        let function = DisassembledFunction(symbol: "_namedABIWordResult", demangledName: nil,
            startAddress: 0x1000, instructions: instructions, source: .symbol)
        let text = function.renderStructured()
        #expect(text.contains(binding ? "if (swift_getEnumCaseMultiPayload() != 1)" : "if (w26 != 1)"),
                Comment(rawValue: text))
    }
}

private struct NamedABIMatrixInput {
    let level, client, strippedClient, system, strippedSystem, provider, providerIR, clientIR, systemIR, native: String
}

private let namedABIMatrix: [NamedABIMatrixInput] = [
    .init(level: "Onone",
          client: "Fixtures/Sample/libNamedABIClient.Onone.dylib",
          strippedClient: "Fixtures/Sample/libNamedABIClient.Onone.stripped.dylib",
          system: "Fixtures/Sample/libNamedABISystem.Onone.dylib",
          strippedSystem: "Fixtures/Sample/libNamedABISystem.Onone.stripped.dylib",
          provider: "Fixtures/Sample/libNamedABIProvider.Onone.dylib",
          providerIR: "Fixtures/Sample/named-abi-Onone-provider.ll",
          clientIR: "Fixtures/Sample/named-abi-Onone-client.ll",
          systemIR: "Fixtures/Sample/named-abi-Onone-system.ll",
          native: "Fixtures/Sample/named-abi-Onone-oracle"),
    .init(level: "O",
          client: "Fixtures/Sample/libNamedABIClient.O.dylib",
          strippedClient: "Fixtures/Sample/libNamedABIClient.O.stripped.dylib",
          system: "Fixtures/Sample/libNamedABISystem.O.dylib",
          strippedSystem: "Fixtures/Sample/libNamedABISystem.O.stripped.dylib",
          provider: "Fixtures/Sample/libNamedABIProvider.O.dylib",
          providerIR: "Fixtures/Sample/named-abi-O-provider.ll",
          clientIR: "Fixtures/Sample/named-abi-O-client.ll",
          systemIR: "Fixtures/Sample/named-abi-O-system.ll",
          native: "Fixtures/Sample/named-abi-O-oracle"),
    .init(level: "Osize",
          client: "Fixtures/Sample/libNamedABIClient.Osize.dylib",
          strippedClient: "Fixtures/Sample/libNamedABIClient.Osize.stripped.dylib",
          system: "Fixtures/Sample/libNamedABISystem.Osize.dylib",
          strippedSystem: "Fixtures/Sample/libNamedABISystem.Osize.stripped.dylib",
          provider: "Fixtures/Sample/libNamedABIProvider.Osize.dylib",
          providerIR: "Fixtures/Sample/named-abi-Osize-provider.ll",
          clientIR: "Fixtures/Sample/named-abi-Osize-client.ll",
          systemIR: "Fixtures/Sample/named-abi-Osize-system.ll",
          native: "Fixtures/Sample/named-abi-Osize-oracle"),
]

@Test func namedABIMatrixMatchesNativeAndIndependentDeclarationsIfPresent() throws {
    for input in namedABIMatrix {
        guard FileManager.default.fileExists(atPath: input.client) else { continue }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: input.native)
        process.standardOutput = pipe
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: bytes, as: UTF8.self) == "PASS 86 native named-ABI observations\n")
        let provider = try String(contentsOfFile: input.providerIR, encoding: .utf8)
        let client = try String(contentsOfFile: input.clientIR, encoding: .utf8)
        let system = try String(contentsOfFile: input.systemIR, encoding: .utf8)
        for (name, result, first) in [("getpid", "double", "double"), ("sqrt", "i64", "i64"),
                                      ("free", "i64", "i64"), ("CGRectInset", "i64", "i64"),
                                      ("printf", "i64", "double")] {
            let declarations = client.split(separator: "\n").filter { $0.hasPrefix("declare ") && $0.contains("@" + name + "(") }
            let declaration = try #require(declarations.first)
            #expect(declarations.count == 1)
            #expect(declaration.contains("swiftcc " + result + " @" + name + "(" + first))
            #expect(declaration.contains("swifterror"))
            let definitions = provider.split(separator: "\n").filter { $0.hasPrefix("define ") && $0.contains("@" + name + "(") }
            let definition = try #require(definitions.first)
            #expect(definitions.count == 1)
            #expect(definition.contains("swiftcc " + result + " @" + name + "(" + first))
            #expect(definition.contains("swifterror"))
        }
        for name in ["getpid", "sqrt", "free", "CGRectInset", "snprintf"] {
            #expect(system.contains("@" + name + "("), Comment(rawValue: input.systemIR + " " + name))
        }
    }
}

@Test func foreignNamedABIResultsAndArgumentsDeclineAcrossAllAPIsIfPresent() async throws {
    let directNames = ["foreignPIDDirect", "foreignSqrtDirect", "foreignFreeDirect", "foreignRectDirect", "foreignFormatDirect"]
    let sdkNames = Set(["getpid", "sqrt", "free", "CGRectInset", "printf"])
    let indirectNames = Set(["pid", "sqrt", "free", "rect", "format"].map { "_named_foreign_" + $0 + "_indirect_entry" })
    for input in namedABIMatrix {
        for path in [input.client, input.strippedClient] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            for name in sdkNames.sorted() {
                #expect(try namedABIImportProvider(image, symbol: name) == "@rpath/libNamedABIProvider.\(input.level).dylib")
            }
            let symbols = image.symbols.filter { symbol in
                indirectNames.contains(symbol.name)
                    || (symbol.name.hasPrefix("_$s14NamedABIClient") && directNames.contains { symbol.name.contains($0) })
            }
            try #require(symbols.count == 10)
            let entries = Set(symbols.map { UInt64($0.offset) })
            try #require(entries.count == 10)
            for functions in try await namedABIStages(path: path, image: image, entries: entries, filter: "foreign") {
                for function in functions {
                    let calls = function.instructions.filter { insn in
                        (insn.controlFlow == .call || insn.controlFlow == .branch)
                            && DisassembledFunction.calleeName(of: insn).map(sdkNames.contains) == true
                    }
                    let call = try #require(calls.first)
                    try #require(calls.count == 1)
                    let name = try #require(DisassembledFunction.calleeName(of: call))
                    #expect(!call.facts.namedABIContract)
                    #expect(!DisassembledFunction.hasNamedABIContract(call))
                    #expect(ValueTracer.CallFacts(call).cResult == nil)
                    for text in [function.renderStructured(), function.renderPseudo()] {
                        let context = Comment(rawValue: path + "\n" + text)
                        #expect(text.components(separatedBy: name + "(").count == 2, context)
                        #expect(text.contains(name + "(…)"), context)
                    }
                }
            }
        }
    }
}

@Test func realNamedABIResultsAndLayoutsSurviveAcrossAllAPIsIfPresent() async throws {
    let expected: [String: Set<String>] = [
        "_named_real_pid": ["getpid"], "_named_real_sqrt": ["sqrt"],
        "_named_real_free": ["malloc", "free"], "_named_real_rect": ["CGRectInset"],
        "_named_real_format": ["snprintf"], "_named_real_sqrt_indirect": ["sqrt"],
        "_named_real_pid_indirect": ["getpid"],
    ]
    for input in namedABIMatrix {
        for path in [input.system, input.strippedSystem] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            for name in ["getpid", "sqrt", "free", "malloc", "snprintf"] {
                #expect(try namedABIImportProvider(image, symbol: name) == "/usr/lib/libSystem.B.dylib")
            }
            #expect(try namedABIImportProvider(image, symbol: "CGRectInset").hasSuffix("/CoreGraphics"))
            let entries = Set(image.symbols.filter { expected[$0.name] != nil }.map { UInt64($0.offset) })
            try #require(entries.count == expected.count)
            for functions in try await namedABIStages(path: path, image: image, entries: entries, filter: "named_real") {
                for function in functions {
                    let names = try #require(expected[function.symbol])
                    for name in names.sorted() {
                        let calls = function.instructions.filter { insn in
                            (insn.controlFlow == .call || insn.controlFlow == .branch)
                                && DisassembledFunction.calleeName(of: insn) == name
                        }
                        let call = try #require(calls.first)
                        try #require(calls.count == 1)
                        let context = Comment(rawValue: path + " " + function.symbol + " " + name)
                        #expect(call.facts.namedABIContract, context)
                        #expect(DisassembledFunction.hasNamedABIContract(call), context)
                        let declaration = try #require(DisassembledFunction.cPrototype(of: name))
                        #expect(ValueTracer.CallFacts(call).cResult == ValueTracer.CallFacts.result(of: declaration), context)
                        let count = name == "snprintf" ? 5 : name == "CGRectInset" ? 3 : name == "getpid" ? 0 : 1
                        #expect((call.callArguments ?? []).count == count, context)
                        if count == 0 {
                            #expect(function.renderPseudo().contains("getpid()"), context)
                        }
                    }
                }
            }
        }
    }
}

@Test func namedABISummaryArityRequiresTheActualReference() {
    let target: UInt64 = 0x2000
    let disassembler = Disassembler()
    for inImage in [false, true] {
        for (raw, provider, expected) in [
            ("_getpid", "/usr/lib/libSystem.B.dylib", Optional(0)),
            ("_getpid", "@rpath/libNamedABIProvider.O.dylib", nil),
            ("_getppid", "/usr/lib/libSystem.B.dylib", nil),
            ("_getpid", "/usr/lib/libobjc.A.dylib", nil),
        ] {
            let reference = RuntimeFunctionReference(rawSymbol: raw, libraryName: provider)
            #expect(disassembler.knownArity(ofCallTarget: target, names: [target: "getpid"],
                cacheSymbols: nil, arcFunctions: [:], abiFunctions: [target: reference],
                isFunction: { _ in inImage }) == expected)
        }
        #expect(disassembler.knownArity(ofCallTarget: target, names: [target: "getpid"],
            cacheSymbols: nil, arcFunctions: [:], isFunction: { _ in inImage }) == nil)
        #expect(disassembler.knownArity(ofCallTarget: target,
            names: [target: "destroy value witness for M.T"], cacheSymbols: nil,
            arcFunctions: [:], isFunction: { _ in inImage }) == 2)
    }
}

@Test func namedABIFunctionFactsPreserveBindingsThroughCacheAndReplay() {
    for useCache in [false, true] {
        let cache: ValueTracer.CallFactsCache? = useCache ? .init() : nil
        for inImage in [false, true] {
            for bound in [true, false, true] {
                var facts = Instruction.Facts()
                facts.namedABIContract = bound
                facts.nonThrowingABIContract = true
                facts.bodyPreservesSwiftError = true
                let call = Instruction(address: 0x1000, text: "bl 0x2000", controlFlow: .call,
                    branchTarget: 0x2000, callee: .kept("getpid"), facts: facts)
                let function = DisassembledFunction(symbol: "_namedFacts", demangledName: nil,
                    startAddress: 0x1000, instructions: [call], source: .symbol)
                let replay = ValueTracer.FunctionFacts(function, cache: cache,
                    inImageTargets: inImage ? [0x2000] : [])
                let recorded = replay.call(call)
                #expect(recorded.namedABIContract == bound)
                #expect((recorded.cResult != nil) == bound)
                #expect(recorded.passedRegisters.contains(.x(0)) == !bound)
                #expect(recorded.passesNoStackArguments == bound)
                #expect(recorded.provablyDoesNotThrow)
            }
        }
    }
}

@Test func namedMemoryHelpersCannotCopyOrFillBySpellingAlone() throws {
    let engine = try #require(CapstoneEngine())
    for name in ["memcpy", "memmove", "memset"] {
        // sub sp,#16; mov x9,#42; str x9,[sp]; mov x0,x8;
        // mov x1,sp (or #42 for memset); mov x2,#8; bl; add sp,#16; ret.
        let words: [UInt32] = [0xd10043ff, 0xd2800549, 0xf90003e9, 0xaa0803e0,
            name == "memset" ? 0xd2800541 : 0x910003e1,
            0xd2800102, 0x94000800, 0x910043ff, 0xd65f03c0]
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        for bound in [false, true] {
            let instructions = decoded.map { item in
                var facts = Instruction.Facts()
                facts.namedABIContract = bound && item.controlFlow == .call
                facts.bodyPreservesSwiftError = item.controlFlow == .call
                return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                    branchTarget: item.branchTarget, detail: item.detail,
                    callee: .kept(item.controlFlow == .call ? name : nil), facts: facts)
            }
            let function = DisassembledFunction(symbol: "_namedMemory", demangledName: nil,
                startAddress: 0x1000, instructions: instructions, source: .symbol)
            let result = ValueTracer().analyze(function, entry: nil)
            let address = try #require(instructions.last?.address)
            let exit = try #require(result.exitIndirectResults[address])
            if bound {
                let value: UInt64 = name == "memset" ? 0x2a2a2a2a2a2a2a2a : 42
                #expect(!exit.poisoned)
                #expect(exit.stores == [0: IndirectResultExit.Store(bytes: 8, value: .immediate(value))])
            } else {
                #expect(exit.poisoned)
                #expect(exit.stores.isEmpty)
            }
        }
    }
}

@Test func namedCResultBanksAreAppliedOnlyToBoundCalls() throws {
    let engine = try #require(CapstoneEngine())
    let words: [UInt32] = [0x94000800, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    for name in ["getpid", "sqrt", "free", "CGRectInset", "printf"] {
        for bound in [false, true] {
            let instructions = decoded.map { item in
                var facts = Instruction.Facts()
                facts.namedABIContract = bound && item.controlFlow == .call
                return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                    branchTarget: item.branchTarget, detail: item.detail,
                    callee: .kept(item.controlFlow == .call ? name : nil), facts: facts)
            }
            let function = DisassembledFunction(symbol: "_namedResult", demangledName: nil,
                startAddress: 0x1000, instructions: instructions, source: .symbol)
            let result = ValueTracer().analyze(function, entry: nil)
            let address = try #require(instructions.last?.address)
            let expectedGP: AbstractValue? = !bound || name == "getpid" || name == "printf" ? .callResult(0x1000) : nil
            // An unbound call keeps opaque machine results in both banks;
            // it supplies neither a declared bank exclusion nor scalar width.
            let expectedFP: AbstractValue? = !bound ? .callResult(0x1000) : name == "sqrt"
                ? .unary(.floatResult(bits: 64, upperZero: true), .callResult(0x1000)) : nil
            #expect(result.exitValues[address] == expectedGP, Comment(rawValue: name + " bound=\(bound)"))
            #expect(result.exitFloatValues[address] == expectedFP, Comment(rawValue: name + " bound=\(bound)"))
        }
    }
}

@Test func namedScalarTailResultsRequireTheMatchingBoundDeclaration() {
    for name in ["getpid", "sqrt", "free", "CGRectInset", "printf"] {
        for bound in [false, true] {
            var facts = Instruction.Facts()
            facts.namedABIContract = bound
            facts.nonThrowingABIContract = true
            facts.bodyPreservesSwiftError = true
            let branch = Instruction(address: 0x1000, text: "b 0x2000", controlFlow: .branch,
                branchTarget: 0x2000, callee: .kept(name), facts: facts)
            let function = DisassembledFunction(symbol: "_tail", demangledName: "M.forward() -> Swift.Int",
                startAddress: 0x1000, instructions: [branch], source: .symbol)
            let sites = Disassembler.scalarTailReturnSites(in: function)
            #expect(sites == (bound && (name == "getpid" || name == "printf") ? [0x1000] : []))
        }
    }
    var arc = Instruction.Facts()
    arc.namedABIContract = true
    let foreign = Instruction(address: 0x1000, text: "bl 0x2000", controlFlow: .call,
        branchTarget: 0x2000, callee: .kept("objc_retain"), facts: arc)
    #expect(!DisassembledFunction.hasNamedABIContract(foreign))
    arc.namedABIContract = false
    arc.arcIdentityContract = true
    let bound = Instruction(address: 0x1000, text: "bl 0x2000", controlFlow: .call,
        branchTarget: 0x2000, callee: .kept("objc_retain"), facts: arc)
    #expect(DisassembledFunction.hasNamedABIContract(bound))
}

@Test func lateNamedBindingRetracesEvenWhenTheNoErrorFactWasAlreadyPresent() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("named-late-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: file.path)
        let reference = RuntimeFunctionReference(rawSymbol: "_sqrt", libraryName: "/usr/lib/libSystem.B.dylib")
        #expect(reference.permitsNamedABI(named: "sqrt"))
        let resolver = Disassembler.ReferenceResolver(names: [0x3000: "sqrt"], stringRanges: [], machO: image,
            demangleSymbol: { _ in nil }, nonThrowingABIFunctions: [0x3000: reference])
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [],
            objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
            selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(), enumCaseIndex: EnumCaseIndex(),
            payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
            classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
        // adr x16,0x3000; blr x16; fmov x0,d0; ret. An existing no-error
        // fact does not name the callee or establish its FP result width.
        let words: [UInt32] = [0x10010010, 0xd63f0200, 0x9e660000, 0xd65f03c0]
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let engine = try #require(CapstoneEngine())
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let instructions = decoded.map { item in
            var facts = Instruction.Facts()
            facts.nonThrowingABIContract = item.controlFlow == .call
            return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                branchTarget: item.branchTarget, detail: item.detail, callee: .kept(nil), facts: facts)
        }
        let input = DisassembledFunction(symbol: "_lateNamedBinding", demangledName: "M.bits() -> Swift.UInt64",
            startAddress: 0x1000, instructions: instructions, source: .symbol)
        let function = Disassembler().analyzeFunction(input, context: context)
        let call = try #require(function.instructions.first { $0.controlFlow == .call })
        #expect(call.facts.nonThrowingABIContract)
        #expect(call.facts.namedABIContract)
        #expect(DisassembledFunction.calleeName(of: call) == "sqrt")
        for text in [function.renderStructured(), function.renderPseudo()] {
            let context = Comment(rawValue: text)
            #expect(text.contains("sqrt(?)"), context)
            #expect(text.contains("bitPattern"), context)
            #expect(!text.contains("return ?"), context)
        }
    }
}

@Test func fixedRuntimeAritiesNeedExactProvidersWithoutBorrowingErrorOrResultFacts() {
    for (name, count) in [("objc_alloc", 1), ("objc_alloc_init", 1), ("objc_opt_new", 1),
                           ("objc_storeStrong", 2), ("objc_autoreleasePoolPush", 0)] {
        let system = RuntimeFunctionReference(rawSymbol: "_" + name, libraryName: "/usr/lib/libobjc.A.dylib")
        let foreign = RuntimeFunctionReference(rawSymbol: "_" + name, libraryName: "@rpath/libForeignObjCNames.dylib")
        #expect(system.permitsNamedABI(named: name))
        #expect(!system.permitsNamedABI(named: name + "_other"))
        #expect(!foreign.permitsNamedABI(named: name))
        #expect(DisassembledFunction.knownCArity(of: name, namedABIContract: system.permitsNamedABI(named: name)) == count)
        #expect(DisassembledFunction.knownCArity(of: name, namedABIContract: foreign.permitsNamedABI(named: name)) == nil)
        let facts = ValueTracer.CallFacts(callee: name, namedABIContract: true)
        #expect(facts.passedRegisters == (0..<count).map { .x($0) })
        #expect(!facts.provablyDoesNotThrow)
    }
}

@Test func compilerObjCRuntimeBindingsKeepTheirAritiesAcrossAllAPIsIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCFactoryReturn.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let expected = Set(["+[SDFactory k0]", "+[SDFactory k1:]", "+[SDFactory k2]", "+[SDFactory k3]", "+[SDFactory k4]"])
    let entries = Set(image.symbols.filter { expected.contains($0.name) }.map { UInt64($0.offset) })
    try #require(entries.count == 5)
    let counts = ["objc_alloc": 1, "objc_alloc_init": 1, "objc_opt_new": 1]
    for functions in try await namedABIStages(path: path, image: image, entries: entries, filter: "SDFactory") {
        var checked = 0
        for function in functions {
            for call in function.instructions where call.controlFlow == .call {
                guard let name = DisassembledFunction.calleeName(of: call), let count = counts[name] else { continue }
                #expect(call.facts.namedABIContract)
                #expect((call.callArguments ?? []).count == count)
                #expect(ValueTracer.CallFacts(call).passedRegisters == (0..<count).map { .x($0) })
                checked += 1
            }
        }
        #expect(checked == 5)
    }
}

@Test func dynamicLookupSDKNamesCannotDonatePrototypesAcrossAllAPIsIfPresent() async throws {
    let path = "Fixtures/Sample/libCPrototypes.unbound.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    for (entry, callee) in [("_insetVertex", "CGRectInset"), ("_fillNull", "CGContextFillRect"),
                             ("_offsetConstant", "CGRectOffset"), ("_drawNull", "CGContextDrawImage")] {
        let symbol = try #require(image.symbols.first { $0.name == "_" + callee && $0.offset == 0 })
        let description = try #require(symbol.nlist.symbolDescription)
        #expect(description.libraryOrdinalType != nil)
        let entrySymbol = try #require(image.symbols.first { $0.name == entry && $0.offset != 0 })
        let entries: Set<UInt64> = [UInt64(entrySymbol.offset)]
        for functions in try await namedABIStages(path: path, image: image, entries: entries, filter: entry) {
            let function = try #require(functions.first)
            let calls = function.instructions.filter { DisassembledFunction.calleeName(of: $0) == callee }
            let call = try #require(calls.first)
            #expect(calls.count == 1)
            #expect(!call.facts.namedABIContract)
            #expect(ValueTracer.CallFacts(call).cResult == nil)
            for text in [function.renderStructured(), function.renderPseudo()] {
                #expect(text.contains(callee + "(…)"), Comment(rawValue: text))
            }
        }
    }
}

@Test func fixedArityProviderSeedsComeFromExactCaseLabels() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("named-provider-seeds-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let declarations = directory.appendingPathComponent("declarations.swift")
    try "getpid i\nmemset i iii\nswift_getAtKeyPath i i\n".write(to: declarations, atomically: true, encoding: .utf8)
    let manual = directory.appendingPathComponent("Pseudo.swift")
    try """
        // An unrelated string is no declaration: "outsideCase".
            static func knownCArity(of callee: String) -> Int? {
                switch callee {
                case "objc_alloc", // "commentOnly"
                     "objc_alloc_init":
                    return 1
                default:
                    if callee.hasPrefix("unboundedPrefix") { return 7 }
                    return nil
                }
            }
        """.write(to: manual, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-c", """
        import importlib.util, json, pathlib, sys
        spec = importlib.util.spec_from_file_location('providers', 'Tools/generate-nonthrowing-abi-providers.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        print(json.dumps(sorted(module.declarations([pathlib.Path(p) for p in sys.argv[1:]]))))
        """, declarations.path, manual.path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
    let names = Set(try JSONDecoder().decode([String].self, from: bytes))
    #expect(names.contains("objc_alloc"))
    #expect(names.contains("objc_alloc_init"))
    #expect(!names.contains("commentOnly"))
    #expect(!names.contains("outsideCase"))
    #expect(!names.contains("unboundedPrefix"))
}

@Test func dynamicLookupSwiftIntrinsicNamesCannotDonateArityAcrossAllAPIsIfPresent() async throws {
    let path = "Fixtures/Sample/libKeyPathIntrinsicsAsm.unbound.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let name = "swift_setAtReferenceWritableKeyPath"
    let symbol = try #require(image.symbols.first { $0.name == "_" + name && $0.offset == 0 })
    #expect(try #require(symbol.nlist.symbolDescription).libraryOrdinalType != nil)
    let entry = try #require(image.symbols.first { $0.name == "_setr" && $0.offset != 0 })
    let entries: Set<UInt64> = [UInt64(entry.offset)]
    for functions in try await namedABIStages(path: path, image: image, entries: entries, filter: "setr") {
        let function = try #require(functions.first)
        let calls = function.instructions.filter { $0.controlFlow == .call }
        let call = try #require(calls.first)
        #expect(calls.count == 1)
        #expect(DisassembledFunction.calleeName(of: call) == name)
        #expect(!call.facts.namedABIContract)
        #expect(ValueTracer.CallFacts(call).cResult == nil)
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(text.contains(name + "(…)"), Comment(rawValue: text))
        }
    }
}

@Test func namedDirectResultConventionsRequireBindingAndExcludeMessageDispatch() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("named-result-convention-\(UUID().uuidString).o")
    let words: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: file.path)
        for (name, provider, direct) in [
            ("malloc", "/usr/lib/libSystem.B.dylib", true),
            ("swift_retain", "/usr/lib/swift/libswiftCore.dylib", true),
            ("objc_retain", "/usr/lib/libobjc.A.dylib", true),
            ("objc_msgSend", "/usr/lib/libobjc.A.dylib", false),
            ("swift_getAtKeyPath", "/usr/lib/swift/libswiftCore.dylib", false),
        ] {
            for bound in [false, true] {
                let reference = RuntimeFunctionReference(rawSymbol: "_" + name,
                    libraryName: bound ? provider : "@rpath/libForeignResultABI.dylib")
                let resolver = Disassembler.ReferenceResolver(names: [0x3000: name], stringRanges: [], machO: image,
                    demangleSymbol: { _ in nil }, arcFunctions: [0x3000: reference],
                    nonThrowingABIFunctions: [0x3000: reference])
                var facts = Instruction.Facts()
                facts.bodyPreservesSwiftError = true
                facts.nonThrowingABIContract = true
                // A weaker named bit cannot replace the ARC provider proof.
                facts.namedABIContract = name == "objc_retain" && !bound
                let call = Instruction(address: 0x1000, text: "bl 0x3000", controlFlow: .call,
                    branchTarget: 0x3000, callee: .kept(name), facts: facts)
                let function = DisassembledFunction(symbol: "_caller", demangledName: nil,
                    startAddress: 0x1000, instructions: [call], source: .symbol)
                let conventions = Disassembler.calleeResultConventions(in: function, indirectResultUses: [:],
                    resolver: resolver, fieldMaps: [:], classTypeIndex: ClassTypeIndex(), registerSummaries: [:],
                    swiftTargets: [], asyncIndex: .empty)
                #expect(conventions[0x1000] == (bound && direct ? .direct : nil),
                    Comment(rawValue: name + " bound=\(bound)"))
            }
        }
    }
}

private let namedBufferMatrix: [NamedABIMatrixInput] = [
    .init(level: "Onone",
          client: "Fixtures/Sample/libNamedBufferClient.Onone.dylib",
          strippedClient: "Fixtures/Sample/libNamedBufferClient.Onone.stripped.dylib",
          system: "Fixtures/Sample/libNamedBufferSystem.Onone.dylib",
          strippedSystem: "Fixtures/Sample/libNamedBufferSystem.Onone.stripped.dylib",
          provider: "Fixtures/Sample/libNamedBufferProvider.Onone.dylib",
          providerIR: "Fixtures/Sample/named-buffer-Onone-provider.ll",
          clientIR: "Fixtures/Sample/named-buffer-Onone-client.ll",
          systemIR: "Fixtures/Sample/named-buffer-Onone-system.ll",
          native: "Fixtures/Sample/named-buffer-Onone-oracle"),
    .init(level: "O",
          client: "Fixtures/Sample/libNamedBufferClient.O.dylib",
          strippedClient: "Fixtures/Sample/libNamedBufferClient.O.stripped.dylib",
          system: "Fixtures/Sample/libNamedBufferSystem.O.dylib",
          strippedSystem: "Fixtures/Sample/libNamedBufferSystem.O.stripped.dylib",
          provider: "Fixtures/Sample/libNamedBufferProvider.O.dylib",
          providerIR: "Fixtures/Sample/named-buffer-O-provider.ll",
          clientIR: "Fixtures/Sample/named-buffer-O-client.ll",
          systemIR: "Fixtures/Sample/named-buffer-O-system.ll",
          native: "Fixtures/Sample/named-buffer-O-oracle"),
    .init(level: "Osize",
          client: "Fixtures/Sample/libNamedBufferClient.Osize.dylib",
          strippedClient: "Fixtures/Sample/libNamedBufferClient.Osize.stripped.dylib",
          system: "Fixtures/Sample/libNamedBufferSystem.Osize.dylib",
          strippedSystem: "Fixtures/Sample/libNamedBufferSystem.Osize.stripped.dylib",
          provider: "Fixtures/Sample/libNamedBufferProvider.Osize.dylib",
          providerIR: "Fixtures/Sample/named-buffer-Osize-provider.ll",
          clientIR: "Fixtures/Sample/named-buffer-Osize-client.ll",
          systemIR: "Fixtures/Sample/named-buffer-Osize-system.ll",
          native: "Fixtures/Sample/named-buffer-Osize-oracle"),
]

@Test func namedResultBufferNativeOraclesAndLoweredDeclarationsIfPresent() throws {
    for input in namedBufferMatrix {
        guard FileManager.default.fileExists(atPath: input.client) else { continue }
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: input.native)
        process.standardOutput = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: bytes, as: UTF8.self) == "PASS 24 native named result-buffer observations\n")
        let provider = try String(contentsOfFile: input.providerIR, encoding: .utf8)
        let definitions = provider.split(separator: "\n").filter { $0.hasPrefix("define ") && $0.contains("@named_buffer_allocate(") }
        let definition = try #require(definitions.first)
        #expect(definitions.count == 1)
        #expect(definition.contains("swiftcc void") && definition.contains("sret(%T14BufferProvider4FiveV)") && definition.contains("i64"))
        for (path, module) in [(input.clientIR, "BufferClient"), (input.systemIR, "BufferSystem")] {
            let ir = try String(contentsOfFile: path, encoding: .utf8)
            for stem in ["7forward", "8indirect"] {
                let name = "$s12" + module + stem + "yAA4FiveVs5Int64VF"
                let declarations = ir.split(separator: "\n").filter { $0.hasPrefix("declare ") && $0.contains("@\"" + name + "\"(") }
                let declaration = try #require(declarations.first)
                #expect(declarations.count == 1)
                #expect(declaration.contains("swiftcc void") && declaration.contains("sret(%T12" + module + "4FiveV)") && declaration.contains("i64"))
            }
        }
    }
}

@Test func namedResultBuffersDeclineForeignABIAndKeepSDKContentsAcrossAllAPIsIfPresent() async throws {
    for input in namedBufferMatrix {
        for (path, module, bound) in [(input.client, "BufferClient", false), (input.strippedClient, "BufferClient", false),
                                       (input.system, "BufferSystem", true), (input.strippedSystem, "BufferSystem", true)] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            #expect(try namedABIImportProvider(image, symbol: "malloc") == (bound ? "/usr/lib/libSystem.B.dylib" : "@rpath/libNamedBufferProvider.\(input.level).dylib"))
            let symbols = Set(["7forward", "8indirect"].map { "_$s12" + module + $0 + "yAA4FiveVs5Int64VF" })
            let entries = Set(image.symbols.filter { symbols.contains($0.name) }.map { UInt64($0.offset) })
            try #require(entries.count == 2)
            for functions in try await namedABIStages(path: path, image: image, entries: entries, filter: module) {
                for function in functions {
                    let calls = function.instructions.filter { $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "malloc" }
                    let call = try #require(calls.first)
                    #expect(calls.count == 1)
                    #expect(call.facts.namedABIContract == bound)
                    for text in [function.renderStructured(), function.renderPseudo()] {
                        let context = Comment(rawValue: path + "\n" + text)
                        #expect(text.components(separatedBy: "malloc(").count == 2, context)
                        if bound {
                            #expect(text.contains("return BufferSystem.Five(a: 1, b: 2, c: 3, d: 4, e: 5)"), context)
                        } else {
                            #expect(text.contains("malloc(…)"), context)
                            #expect(!text.contains("return BufferClient.Five("), context)
                        }
                    }
                }
            }
        }
    }
}

@Test func aLateStackProbeBindingStillRetracesWithoutAnEarlierSlotModel() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("named-probe-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: file.path)
        let probe = RuntimeFunctionReference(rawSymbol: "___chkstk_darwin", libraryName: "/usr/lib/libSystem.B.dylib")
        #expect(probe.permitsNamedABI(named: "__chkstk_darwin"))
        let resolver = Disassembler.ReferenceResolver(names: [0x3000: "__chkstk_darwin"], stringRanges: [],
            machO: image, demangleSymbol: { _ in nil }, nonThrowingABIFunctions: [0x3000: probe])
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [],
            objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
            selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(), enumCaseIndex: EnumCaseIndex(),
            payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
            classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
        // mov x1,#40; mov x9,#16; adr x16,0x3000; blr x16; mov x0,x1; ret.
        // This is not an ADRP/LDR slot recognized before the first trace.
        // The valid probe preserves x1; an opaque call initially loses it.
        let words: [UInt32] = [0xd2800501, 0xd2800209, 0x1000ffd0, 0xd63f0200, 0xaa0103e0, 0xd65f03c0]
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let engine = try #require(CapstoneEngine())
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let instructions = decoded.map { item in
            Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                branchTarget: item.branchTarget, detail: item.detail, callee: .kept(nil))
        }
        let input = DisassembledFunction(symbol: "_lateNamedProbe", demangledName: "M.lateProbe() -> Swift.Int",
            startAddress: 0x1000, instructions: instructions, source: .symbol)
        let function = Disassembler().analyzeFunction(input, context: context)
        let call = try #require(function.instructions.first { $0.controlFlow == .call })
        #expect(call.facts.namedABIContract)
        #expect(!call.facts.nonThrowingABIContract)
        #expect(!call.facts.bodyPreservesSwiftError)
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(text.contains("return 40"), Comment(rawValue: text))
        }
    }
}

/// A runtime entry point that returns nothing leaves no result in x0. A
/// call site says which function it reaches only through its binding, and
/// `swift_willThrow` has no row in the provider table, so its binding is
/// never proven. x0 after a call under one of these names is therefore
/// claimed by nothing in either state: the library's function left no
/// result there, and a function that only shares the name returns a value
/// nothing here proves. Requiring the binding for the discard would name a
/// result for every unproven `swift_willThrow`.
@Test func aVoidRuntimeNameClaimsNoResultWithOrWithoutItsBinding() {
    for name in ValueTracer.voidRuntimeCalls.sorted() {
        for spelling in [name, "_" + name] {
            #expect(ValueTracer.CallFacts(callee: spelling).returnsVoidByName, Comment(rawValue: spelling))
            #expect(ValueTracer.CallFacts(callee: spelling, namedABIContract: true).returnsVoidByName, Comment(rawValue: spelling))
            // The facts built for a call into this image's own function.
            #expect(ValueTracer.CallFacts(callee: spelling, knownArityApplies: false).returnsVoidByName, Comment(rawValue: spelling))
        }
        for binding in [[true, false], [false, true]] {
            let cache = ValueTracer.CallFactsCache()
            for bound in binding {
                #expect(cache.facts(for: name, namedABIContract: bound).returnsVoidByName, Comment(rawValue: "\(name) bound=\(bound)"))
            }
        }
    }
    #expect(ValueTracer.voidRuntimeCalls == ["swift_willThrow", "swift_willThrowTypedImpl", "swift_job_run"])
    // The exact names, and nothing longer or shorter.
    for name in ["swift_willThrowLookalike", "swift_job_runner", "swift_job_run_on_task_executor", "swift_willThro",
                 "plain_result"] {
        #expect(!ValueTracer.CallFacts(callee: name).returnsVoidByName, Comment(rawValue: name))
        #expect(!ValueTracer.CallFacts(callee: name, namedABIContract: true).returnsVoidByName, Comment(rawValue: name))
    }
}

/// The same through the tracer: `bl <callee>; ret`. x0 and v0 at the
/// return are no value after a void runtime name, bound or not, and the
/// call's opaque result after any other name without a declaration.
@Test func theTracerNamesNoResultAfterAVoidRuntimeNameInEitherBinding() throws {
    let engine = try #require(CapstoneEngine())
    // bl +0x2000; ret
    let words: [UInt32] = [0x94000800, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    func exits(_ name: String, bound: Bool) throws -> (AbstractValue?, AbstractValue?) {
        let instructions = decoded.map { item in
            var facts = Instruction.Facts()
            facts.namedABIContract = bound && item.controlFlow == .call
            return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                branchTarget: item.branchTarget, detail: item.detail,
                callee: .kept(item.controlFlow == .call ? name : nil), facts: facts)
        }
        let function = DisassembledFunction(symbol: "_voidName", demangledName: nil,
            startAddress: 0x1000, instructions: instructions, source: .symbol)
        let result = ValueTracer().analyze(function, entry: nil)
        let address = try #require(instructions.last?.address)
        return (result.exitValues[address], result.exitFloatValues[address])
    }
    for name in ValueTracer.voidRuntimeCalls.sorted() {
        for bound in [false, true] {
            let (gp, fp) = try exits(name, bound: bound)
            #expect(gp == nil, Comment(rawValue: "\(name) bound=\(bound)"))
            #expect(fp == nil, Comment(rawValue: "\(name) bound=\(bound)"))
        }
    }
    // The controls: a name with a void name as its prefix, and one no
    // table knows, keep the call's opaque result in both banks.
    for name in ["swift_willThrowLookalike", "swift_job_runner", "plain_result"] {
        let (gp, fp) = try exits(name, bound: false)
        #expect(gp == .callResult(0x1000), Comment(rawValue: name))
        #expect(fp == .callResult(0x1000), Comment(rawValue: name))
    }
}
