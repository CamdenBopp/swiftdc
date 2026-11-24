import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

@Test func nonThrowingABIRequiresTheExactSDKProviderAndSymbol() {
    for (name, provider) in [
        ("getpid", "/usr/lib/libSystem.B.dylib"),
        ("getpid", "/usr/lib/system/libsystem_kernel.dylib"),
        ("memset", "/usr/lib/system/libsystem_c.dylib"),
        ("CFGetTypeID", "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"),
        ("swift_getAtKeyPath", "@rpath/libswiftCore.dylib"),
        ("objc_msgSend", "/usr/lib/libobjc.A.dylib"),
    ] {
        #expect(RuntimeFunctionReference(rawSymbol: "_" + name, libraryName: provider).permitsNonThrowingABI(named: name))
    }
    for (raw, name, provider) in [
        ("_getpid", "getpid", "@rpath/libPlainErrorProvider.dylib"),
        ("_getpid", "getpid", "/usr/lib/libobjc.A.dylib"),
        ("_getpid", "getpid", "/System/Library/Frameworks/Counter.framework/Counter"),
        ("_getpid", "getpid", "/usr/lib/../lib/libSystem.B.dylib"),
        ("_getpid", "getpid", "/usr/lib/libNotInTheSDK.dylib"),
        ("_getpid", "getppid", "/usr/lib/libSystem.B.dylib"),
        ("__getpid", "getpid", "/usr/lib/libSystem.B.dylib"),
        ("_plain_error_raise", "plain_error_raise", "/usr/lib/libSystem.B.dylib"),
        ("_swift_getAtKeyPath", "swift_getAtKeyPath", "/usr/lib/libobjc.A.dylib"),
    ] {
        #expect(!RuntimeFunctionReference(rawSymbol: raw, libraryName: provider).permitsNonThrowingABI(named: name))
    }
}

private func nonThrowingContractBody(_ words: [UInt32], trusted: Bool, name: String = "getpid") throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let data = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(data, address: 0x1000)
    try #require(decoded.count == words.count)
    let instructions = decoded.map { item in
        var facts = Instruction.Facts()
        if item.controlFlow == .call { facts.nonThrowingABIContract = trusted }
        return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
            branchTarget: item.branchTarget, detail: item.detail,
            callee: .kept(item.controlFlow == .call ? name : nil), facts: facts)
    }
    return DisassembledFunction(symbol: "_no_error_contract", demangledName: nil, startAddress: 0x1000,
                                instructions: instructions, source: .address)
}

@Test func nonThrowingCallCacheKeepsABIProvenanceInBothOrders() throws {
    // mov x21,#0; bl getpid; mov x0,x21; ret
    let words: [UInt32] = [0xd2800015, 0x940003ff, 0xaa1503e0, 0xd65f03c0]
    for inImage in [false, true] {
        for trustedFirst in [false, true] {
            let cache = ValueTracer.CallFactsCache()
            for trusted in [trustedFirst, !trustedFirst, trustedFirst, !trustedFirst] {
                let function = try nonThrowingContractBody(words, trusted: trusted)
                var tracer = ValueTracer()
                tracer.callFactsCache = cache
                if inImage { tracer.inImageCallTargets = [0x2000] }
                let result = tracer.analyze(function).exitValues[0x100c]
                #expect(result == (trusted ? .immediate(0) : nil))
                #expect(ValueTracer.CallFacts(function.instructions[1]).provablyDoesNotThrow == trusted)
                #expect(ValueTracer.provablyDoesNotThrow(function.instructions[1]) == trusted)
            }
        }
    }
    #expect(!ValueTracer.provablyDoesNotThrow("plain_error_raise"))
    let unsupported = try nonThrowingContractBody(words, trusted: true, name: "plain_error_raise")
    #expect(!ValueTracer.provablyDoesNotThrow(unsupported.instructions[1]))
    #expect(!ValueTracer.CallFacts(unsupported.instructions[1]).provablyDoesNotThrow)
}

@Test func nonThrowingABISeparatelyGuardsTheConditionWalkback() throws {
    // A nonzero local in x21 is not the high-level armed-error shorthand.
    // mov x19,#7; mov x21,x19; bl getpid; cbz x21,success; ...
    let words: [UInt32] = [0xd28000f3, 0xaa1303f5, 0x940003fe, 0xb4000075,
                           0xd2800020, 0xd65f03c0, 0xd2800040, 0xd65f03c0]
    for trusted in [false, true] {
        let function = try nonThrowingContractBody(words, trusted: trusted)
        let text = function.renderStructured()
        #expect(text.contains("if (x21 == 0)") == !trusted, Comment(rawValue: text))
        if !trusted { #expect(!text.contains("(7 == 0)"), Comment(rawValue: text)) }
    }
}

@Test func nonThrowingABISeparatelyGuardsNoErrorPoints() throws {
    // mov x21,#0; bl getpid; mov x0,#13; ret
    let words: [UInt32] = [0xd2800015, 0x940003ff, 0xd28001a0, 0xd65f03c0]
    for trusted in [false, true] {
        let function = try nonThrowingContractBody(words, trusted: trusted)
        let points = SwiftErrorExitProof.noErrorPoints(blocks: function.basicBlocks(), entry: 0x1000,
            key: "x21", entryIsNoError: true, callPreserves: { ValueTracer.provablyDoesNotThrow($0) })
        #expect(points.contains(0x1004))
        #expect(points.contains(0x100c) == trusted)
    }
}

@Test func nonThrowingCacheExportsRejectWrongProvidersFlagsAndAddressesIfPresent() throws {
    let path = "Fixtures/Sample/libResultIdentity.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    var symbol = try #require(image.exportedSymbols.first { $0.name == "_result_identity_make" })
    symbol.name = "_getpid"
    symbol.offset = 32
    symbol.flags = ExportSymbolFlags(rawValue: 0)
    func table(_ symbol: ExportedSymbol, provider: String = "/usr/lib/libSystem.B.dylib",
               base: UInt64 = 0x1000, text: Range<UInt64> = 0x1000..<0x2000) -> [UInt64: Set<String>] {
        CacheSymbolResolver.nonThrowingABIExports([symbol], imagePath: provider, base: base, text: text)
    }
    #expect(table(symbol)[0x1020] == Set(["getpid"]))
    #expect(table(symbol, provider: "@rpath/libPlainErrorProvider.dylib").isEmpty)
    #expect(table(symbol, provider: "/usr/lib/libobjc.A.dylib").isEmpty)
    for flags in [Int32(1), 2, ExportSymbolFlags.weak_definition.rawValue, ExportSymbolFlags.reexport.rawValue,
                  ExportSymbolFlags.stub_and_resolver.rawValue, ExportSymbolFlags.static_resolver.rawValue,
                  ExportSymbolFlags.function_variant.rawValue, 0x4000_0000] {
        var changed = symbol
        changed.flags = ExportSymbolFlags(rawValue: flags)
        #expect(table(changed).isEmpty)
    }
    for offset: Int? in [nil, -1, 0x2000, Int.max] {
        var changed = symbol
        changed.offset = offset
        #expect(table(changed).isEmpty)
    }
    #expect(table(symbol, base: UInt64.max - 15, text: 0..<64).isEmpty)
    var wrongName = symbol
    wrongName.name = "_plain_error_raise"
    #expect(table(wrongName).isEmpty)
}

@Test func SDKProviderGenerationRejectsWeakTLSAndWrongTargetReexports() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sdk = root.appendingPathComponent("SDK")
    let libraries = sdk.appendingPathComponent("usr/lib")
    try FileManager.default.createDirectory(at: libraries, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "{\"Version\":\"test\"}".write(to: sdk.appendingPathComponent("SDKSettings.json"), atomically: true, encoding: .utf8)
    let documents = [
        "libSystem.B.tbd": """
        --- !tapi-tbd
        tbd-version: 4
        targets: [ arm64e-macos, x86_64-macos ]
        install-name: '/usr/lib/libSystem.B.dylib'
        reexported-libraries:
          - targets: [ arm64e-macos ]
            libraries: [ '/usr/lib/libOwned.dylib' ]
          - targets: [ x86_64-macos ]
            libraries: [ '/usr/lib/libOther.dylib' ]
        exports:
          - targets: [ arm64e-macos ]
            weak-symbols: [ _memset ]
            thread-local-symbols: [ _memcpy ]
        ...
        """,
        "libOwned.tbd": """
        --- !tapi-tbd
        tbd-version: 4
        targets: [ arm64e-macos ]
        install-name: '/usr/lib/libOwned.dylib'
        exports:
          - targets: [ arm64e-macos ]
            symbols: [ _getpid ]
        ...
        """,
        "libOther.tbd": """
        --- !tapi-tbd
        tbd-version: 4
        targets: [ arm64e-macos ]
        install-name: '/usr/lib/libOther.dylib'
        exports:
          - targets: [ arm64e-macos ]
            symbols: [ _malloc ]
        ...
        """,
    ]
    for (name, text) in documents {
        try (text + "\n").write(to: libraries.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let output = root.appendingPathComponent("generated.swift")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "Tools/generate-nonthrowing-abi-providers.py", "--sdk", sdk.path, "--output", output.path]
    let diagnostics = Pipe()
    process.standardOutput = diagnostics
    process.standardError = diagnostics
    try process.run()
    process.waitUntilExit()
    let diagnostic = String(decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    try #require(process.terminationStatus == 0, Comment(rawValue: diagnostic))
    let source = try String(contentsOf: output, encoding: .utf8)
    // Sorted providers: Other=0, Owned=1, System=2. Only Owned's
    // arm64 reexport donates getpid to System; malloc stays in Other.
    #expect(source.contains("\ngetpid 1,2\n"))
    #expect(source.contains("\nmalloc 0\n"))
    #expect(!source.contains("\nmemset "))
    #expect(!source.contains("\nmemcpy "))
}

/// The loader-evidence mutator edits only temporary images. The canonical
/// fixture and its native ABI receipt remain unchanged and executable.
@Test func nonThrowingImportsRejectBrokenLoaderEvidenceAcrossAllAPIsIfPresent() async throws {
    for (file, module) in [("libResultIdentity.dylib", "ResultIdentity"),
                           ("libResultIdentity.legacy.dylib", "ResultIdentityLegacy")] {
        let original = "Fixtures/Sample/" + file
        guard FileManager.default.fileExists(atPath: original) else { continue }
        let image = try BinaryLoader.load(path: original)
        let originalFunctions = try await withStableDependencies {
            try await Disassembler().disassemble(path: original, functionFilter: module + ".run(")
        }
        let originalRun = try #require(originalFunctions.first { $0.displayName.hasPrefix(module + ".run(") })
        let originalCall = try #require(originalRun.instructions.first {
            DisassembledFunction.calleeName(of: $0) == "swift_bridgeObjectRetain"
        })
        #expect(originalCall.facts.nonThrowingABIContract)
        let entry = originalRun.startAddress
        let kinds = ["provider-mismatch", "pointer-addend", "weak-import", "weak-bind-only", "weak-nlist-only",
                     "weak-dylib", "other-symbol", "nlist-mismatch", "flat-namespace", "self-ordinal", "flat-lookup",
                     "weak-lookup", "stub-non-jump", "non-twolevel", "force-flat", "weak-use-flags", "ref-to-weak-nlist",
                     "other-identity-symbol"] + (file.contains(".legacy.")
                     ? ["normal-after-done", "missing-binding", "lazy-helper-mismatch"] : ["import-addend"])
        for kind in kinds {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent(file).path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "Fixtures/Sample/mutate-result-identity.py", "--library", original,
                                 "--output", path, "--kind", kind]
            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            let diagnostic = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            try #require(process.terminationStatus == 0, Comment(rawValue: diagnostic))
            let changed = try BinaryLoader.load(path: path)
            for stage in 0..<5 {
                let functions: [DisassembledFunction] = try await withStableDependencies {
                    switch stage {
                    case 0: return try await Disassembler().disassemble(path: path)
                    case 1: return await Disassembler().disassemble(machO: changed)
                    case 2: return try await Disassembler().disassemble(path: path, functionFilter: module + ".run(")
                    case 3:
                        let selected: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                            machO: changed, transform: { $0.startAddress == entry ? $0 : nil })
                        return selected.compactMap { $0 }
                    default:
                        let selected = await Disassembler().analyzeEachFunction(at: [entry], in: changed, transform: { $0 })
                        return Array(selected.values)
                    }
                }
                let function = try #require(functions.first { $0.startAddress == entry })
                let call = try #require(function.instructions.first { $0.address == originalCall.address })
                #expect(!call.facts.nonThrowingABIContract, Comment(rawValue: file + " " + kind + " stage \(stage)"))
            }
        }
        // The original image remains readable after all temporary mutations.
        #expect(image.header.flags.contains(.twolevel))
    }
}

@Test func nonThrowingCacheContractsUseRealExportsAndIslandsIfAvailable() async throws {
    func report(_ status: String, direct: Int = 0, islands: Int = 0) throws {
        guard let path = ProcessInfo.processInfo.environment["SWIFTDC_NONTHROW_CACHE_REPORT"] else { return }
        let data = try JSONSerialization.data(withJSONObject: ["status": status, "direct_exports": direct,
                                                               "islands": islands], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }
    let kernel: MachOFile
    do { kernel = try BinaryLoader.loadFromDyldCache(cachePath: nil, selector: .path("/usr/lib/system/libsystem_kernel.dylib")) }
    catch { try report("unavailable"); return }
    let full = try #require(kernel.fullCache)
    let resolver = try #require(CacheSymbolResolver(machO: kernel))
    let text = try #require(kernel.loadCommands.infos(of: LoadCommand.segment64).first { $0.segmentName == "__TEXT" })
    let exported = try #require(kernel.exportedSymbols.first { $0.name == "_getpid" })
    let offset = try #require(exported.offset)
    try #require(offset >= 0 && exported.flags.rawValue == 0)
    let address = UInt64(text.vmaddr) + UInt64(offset)
    #expect(resolver.nonThrowingABIContract(forCallTarget: address, named: "getpid"))
    #expect(!resolver.nonThrowingABIContract(forCallTarget: address + 1, named: "getpid"))
    #expect(!resolver.nonThrowingABIContract(forCallTarget: address, named: "memset"))
    let consumer = try #require(full.machOFiles().first {
        $0.imagePath == "/System/Library/Frameworks/UserNotifications.framework/Versions/A/UserNotifications"
    })
    let disassembler = Disassembler()
    let boundaries = disassembler.functionStarts(of: consumer).sorted()
    var seen = Set<UInt64>()
    var sites = 0
    for start in boundaries.prefix(256) {
        let instructions = await withStableDependencies {
            disassembler.decodeFunction(at: start, boundaries: boundaries, in: consumer)
        }
        for instruction in instructions where instruction.controlFlow == .call || instruction.controlFlow == .branch {
            guard let target = instruction.branchTarget, !seen.contains(target),
                  let raw = resolver.name(forCallTarget: target) else { continue }
            let name = raw.hasPrefix("_") ? String(raw.dropFirst()) : raw
            guard DisassembledFunction.isARCReferenceHelper(name) else { continue }
            seen.insert(target)
            #expect(resolver.nonThrowingABIContract(forCallTarget: target, named: name))
            #expect(!resolver.nonThrowingABIContract(forCallTarget: target, named: "plain_error_raise"))
            sites += 1
        }
        if sites >= 12 { break }
    }
    #expect(sites > 0)
    try report("observed", direct: 1, islands: sites)
}

private func swiftErrorBodyFunction(_ words: [UInt32], at start: UInt64) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let data = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let instructions = engine.disassemble(data, address: start).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    try #require(instructions.count == words.count)
    return DisassembledFunction(symbol: "_body_error_proof", demangledName: nil,
        startAddress: start, instructions: instructions, source: .address)
}

private func swiftErrorBodySummary(_ words: [UInt32], at start: UInt64,
                                   functions: Set<UInt64> = []) throws -> CalleeRegisterSummary {
    let function = try swiftErrorBodyFunction(words, at: start)
    return try #require(CalleeRegisterSummary.of(function, isFunction: functions.contains))
}

private func swiftErrorBodyCall(at start: UInt64, to target: UInt64) -> [UInt32] {
    // Preserve LR around a real BL; the return below reaches the caller.
    [0xa9bf7bfd, 0x94000000 | (UInt32(truncatingIfNeeded: Int64(bitPattern: target &- (start + 4)) >> 2) & 0x03ffffff),
     0xa8c17bfd, 0xd65f03c0]
}

@Test func swiftErrorBodyProofRequiresEveryActualTransfer() throws {
    let starts: Set<UInt64> = [0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000, 0x7000, 0xa000, 0xb000]
    var summaries: [UInt64: CalleeRegisterSummary] = [:]
    summaries[0x2000] = try swiftErrorBodySummary([0xd65f03c0], at: 0x2000)
    for (start, target) in [(0x1000, 0x2000), (0x4000, 0x9000), (0x5000, 0x4000),
                            (0x7000, 0x6000), (0xa000, 0xb000), (0xb000, 0xa000)] as [(UInt64, UInt64)] {
        summaries[start] = try swiftErrorBodySummary(swiftErrorBodyCall(at: start, to: target), at: start, functions: starts)
    }
    summaries[0x6000] = try swiftErrorBodySummary([0xd2800035, 0xd65f03c0], at: 0x6000) // mov x21,#1; ret
    // A non-stack store discards outgoingCalls for the memory consumer.
    // It must still retain the independent unresolved BLR decline.
    summaries[0x3000] = try swiftErrorBodySummary([0xa9bf7bfd, 0xf9000001, 0xd63f0040, 0xa8c17bfd, 0xd65f03c0], at: 0x3000)
    #expect(summaries[0x3000]?.storesOnlyToStack == false)
    #expect(summaries[0x3000]?.outgoingCalls.isEmpty == true)
    #expect(summaries[0x3000]?.hasUnresolvedSwiftErrorCall == true)
    for trustedExternal in [false, true] {
        var copy = summaries
        let facts = CalleeRegisterFacts.finish(&copy, externalPreservesSwiftError: { trustedExternal && $0 == 0x9000 }).facts
        #expect(copy.isEmpty)
        for start: UInt64 in [0x1000, 0x2000, 0xa000, 0xb000] { #expect(facts[start]?.bodyPreservesSwiftError == true) }
        for start: UInt64 in [0x3000, 0x6000, 0x7000] { #expect(facts[start]?.bodyPreservesSwiftError == false) }
        for start: UInt64 in [0x4000, 0x5000] { #expect(facts[start]?.bodyPreservesSwiftError == trustedExternal) }
    }
    // A dictionary key is not evidence of an undecoded entry prefix.
    var shifted: [UInt64: CalleeRegisterSummary] = [0x2004: try #require(summaries[0x2000])]
    #expect(CalleeRegisterFacts.finish(&shifted).facts[0x2004]?.bodyPreservesSwiftError == false)
    var fallback: [UInt64: CalleeRegisterSummary] = [0x2000: try #require(summaries[0x2000]).claimingNothing()]
    #expect(CalleeRegisterFacts.finish(&fallback).facts[0x2000]?.bodyPreservesSwiftError == false)
}

@Test func swiftErrorBodyDeclineSurvivesReadClosureAndPackedForwarderFlags() throws {
    let start: UInt64 = 0x1000, target: UInt64 = 0x2000
    let leaf = try swiftErrorBodySummary([0x91000400, 0xd65f03c0], at: target) // add x0,x0,#1; ret
    for unresolved in [false, true] {
        var caller = try swiftErrorBodySummary(swiftErrorBodyCall(at: start, to: target), at: start, functions: [start, target])
        caller.hasUnresolvedSwiftErrorCall = unresolved
        // The three facts occupy independent bits in the packed shape byte.
        caller.pureTailTarget = target
        #expect(caller.pureTailTarget == target && caller.hasUnresolvedSwiftErrorCall == unresolved)
        caller.pureTailTarget = nil
        caller.framedCallTarget = target
        #expect(caller.framedCallTarget == target && caller.hasUnresolvedSwiftErrorCall == unresolved)
        caller.framedCallTarget = nil
        #expect(!caller.argumentReads.contains(0))
        var summaries: [UInt64: CalleeRegisterSummary] = [start: caller, target: leaf]
        CalleeRegisterSummary.closeOverReads(&summaries)
        #expect(summaries[start]?.argumentReads.contains(0) == true)
        #expect(summaries[start]?.hasUnresolvedSwiftErrorCall == unresolved)
        #expect(CalleeRegisterFacts.finish(&summaries).facts[start]?.bodyPreservesSwiftError == !unresolved)
    }
}

@Test func swiftErrorBodyCallFactsKeepTheirOwnProvenanceInBothCacheOrders() throws {
    // The same plain spelling denotes two bodies. No SDK/ARC identity exists.
    let words: [UInt32] = [0xd2800015, 0x940003ff, 0xaa1503e0, 0xd65f03c0]
    for name in ["body_error_leaf", "M.never() throws -> Swift.Int"] {
        for inImage in [false, true] {
            for trustedFirst in [false, true] {
                let cache = ValueTracer.CallFactsCache()
                for trusted in [trustedFirst, !trustedFirst, trustedFirst, !trustedFirst] {
                    let raw = try nonThrowingContractBody(words, trusted: false, name: name)
                    let instructions = raw.instructions.map { instruction in
                        var facts = instruction.facts
                        if instruction.controlFlow == .call { facts.bodyPreservesSwiftError = trusted }
                        return Instruction(address: instruction.address, text: instruction.text,
                            controlFlow: instruction.controlFlow, branchTarget: instruction.branchTarget,
                            detail: instruction.detail, callee: .kept(instruction.callee), facts: facts)
                    }
                    let function = DisassembledFunction(symbol: raw.symbol, demangledName: nil,
                        startAddress: raw.startAddress, instructions: instructions, source: .address)
                    var tracer = ValueTracer()
                    tracer.callFactsCache = cache
                    if inImage { tracer.inImageCallTargets = [0x2000] }
                    let result = tracer.analyze(function).exitValues[0x100c]
                    if trusted { #expect(result == .immediate(0)) }
                    else if name == "body_error_leaf" { #expect(result == nil) }
                    else { #expect(result != .immediate(0)) }
                    #expect(ValueTracer.CallFacts(instructions[1]).provablyDoesNotThrow == trusted)
                    #expect(ValueTracer.provablyDoesNotThrow(instructions[1]) == trusted)
                }
            }
        }
    }
}

@Test func swiftErrorLocalBodyControlsStayNormalAcrossAllAPIsIfPresent() async throws {
    let path = "Fixtures/Sample/libErrorExitControls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let disassembler = Disassembler()
    let symbols = image.symbols
    let raw = "_$s9ExitProof14preservingCallyS2iKF"
    let start = try #require(symbols.first { $0.name == raw }?.offset)
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await disassembler.disassemble(path: path)
            case 1: return await disassembler.disassemble(machO: image)
            case 2: return try await disassembler.disassemble(path: path, functionFilter: "ExitProof.preservingCall(")
            case 3:
                let selected: [DisassembledFunction?] = await disassembler.disassembleStreaming(machO: image,
                    transform: { $0.startAddress == UInt64(start) ? $0 : nil })
                return selected.compactMap { $0 }
            default:
                return Array(await disassembler.analyzeEachFunction(at: [UInt64(start)], in: image, transform: { $0 }).values)
            }
        }
        let function = try #require(functions.first { $0.startAddress == UInt64(start) })
        let call = try #require(function.instructions.first { $0.controlFlow == .call })
        #expect(call.facts.bodyPreservesSwiftError)
        #expect(!call.facts.nonThrowingABIContract)
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(text.contains("return 13"), Comment(rawValue: text))
            #expect(!text.contains("machine_return()"), Comment(rawValue: text))
        }
    }
}

@Test func swiftErrorBodyDeclineSurvivesPreservationRebuilds() throws {
    let function = try swiftErrorBodyFunction([0xa9bf7bfd, 0xf9000001, 0xd63f0040, 0xa8c17bfd, 0xd65f03c0], at: 0x1000)
    let original = try #require(CalleeRegisterSummary.of(function))
    #expect(original.outgoingCalls.isEmpty && original.hasUnresolvedSwiftErrorCall)
    for reuse in [false, true] {
        let rebuilt = try #require(CalleeRegisterSummary.recomputingPreservation(function,
            retainingReadsFrom: original, reusingPreservation: reuse,
            rebuildingEntryRoles: false, calleeEffects: { _ in CalleeEffect() }))
        #expect(rebuilt.hasUnresolvedSwiftErrorCall)
        var summaries: [UInt64: CalleeRegisterSummary] = [0x1000: rebuilt]
        #expect(CalleeRegisterFacts.finish(&summaries).facts[0x1000]?.bodyPreservesSwiftError == false)
    }
}

@Test func swiftErrorBodyProofDeclinesInteriorCallsAndUnknownConstructors() throws {
    // The BL jumps into its own decoded span, without a declared callee entry.
    let start: UInt64 = 0x1000
    let interior = try swiftErrorBodySummary(swiftErrorBodyCall(at: start, to: start + 8), at: start)
    #expect(interior.callees.isEmpty && interior.hasUnresolvedSwiftErrorCall)
    var summaries: [UInt64: CalleeRegisterSummary] = [start: interior]
    #expect(CalleeRegisterFacts.finish(&summaries).facts[start]?.bodyPreservesSwiftError == false)
    // An explicitly supplied entry and empty clobber set are insufficient
    // without the body's complete outgoing-transfer evidence.
    var unknown: [UInt64: CalleeRegisterSummary] = [start: CalleeRegisterSummary(
        argumentReads: [], clobberedCalleeSaved: [], inputProofEntry: start, hasProvenReturnTargets: true)]
    #expect(CalleeRegisterFacts.finish(&unknown).facts[start]?.bodyPreservesSwiftError == false)
}

@Test func swiftErrorBodyDeclineSurvivesCallClosureReanalysis() throws {
    let start: UInt64 = 0x1000, target: UInt64 = 0x2000
    let leaf = try swiftErrorBodyFunction([0xd2800033, 0xd65f03c0], at: target) // mov x19,#1; ret
    let caller = try swiftErrorBodyFunction([0xa9bf7bfd, 0xf9000001, 0x940003fe, 0xd63f0040,
                                            0xa8c17bfd, 0xd65f03c0], at: start)
    let functions: [UInt64: DisassembledFunction] = [start: caller, target: leaf]
    let starts = Set(functions.keys)
    var summaries = try functions.mapValues { try #require(CalleeRegisterSummary.of($0, isFunction: starts.contains)) }
    #expect(summaries[start]?.hasUnresolvedSwiftErrorCall == true)
    #expect(summaries[start]?.clobberedCalleeSaved.contains("x19") == false)
    CalleeRegisterSummary.closeOverCalls(&summaries, rebuildingEntryRoles: false) { address, effects, reads, reuse in
        guard let function = functions[address] else { return nil }
        return CalleeRegisterSummary.recomputingPreservation(function, retainingReadsFrom: reads,
            reusingPreservation: reuse, rebuildingEntryRoles: false,
            calleeEffects: effects, isFunction: starts.contains)
    }
    #expect(summaries[start]?.clobberedCalleeSaved.contains("x19") == true)
    #expect(summaries[start]?.hasUnresolvedSwiftErrorCall == true)
    #expect(CalleeRegisterFacts.finish(&summaries).facts[start]?.bodyPreservesSwiftError == false)
}

@Test func swiftErrorBodyPointersRequireImmutableStorageIfPresent() throws {
    let path = "Fixtures/Sample/libPlainErrorSystem.O.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    func address(_ name: String) throws -> UInt64 {
        UInt64(try #require(image.symbols.first { $0.name == name }).offset)
    }
    let entry = try address("_system_error_body_leaf")
    let slot = try address("_system_error_body_slot")
    let root = try address("_system_error_body_root")
    var summaries: [UInt64: CalleeRegisterSummary] = [entry: try swiftErrorBodySummary([0xd65f03c0], at: entry)]
    let facts = CalleeRegisterFacts.finish(&summaries).facts
    let resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: image,
        demangleSymbol: { _ in nil }).withSwiftErrorBodyProofs(facts)
    #expect(resolver.fixedFunctionTarget(for: .loaded(slot)) == entry)
    #expect(resolver.fixedFunctionTarget(for: .loaded(root)) == slot)
    #expect(resolver.bodyPreservesSwiftError(for: .loaded(slot)))
    #expect(resolver.bodyPreservesSwiftError(for: .loadedThrough(slot: root, offset: 0)))
    #expect(resolver.bodyPreservesSwiftError(for: .address(entry)))
    #expect(resolver.bodyPreservesSwiftError(for: .immediate(entry)))
    #expect(!resolver.bodyPreservesSwiftError(for: .unknown))
    #expect(!resolver.bodyPreservesSwiftError(for: .loadedThrough(slot: root, offset: -1)))
    // Remove either storage proof independently. These temporary images
    // are disassembled only; the executable native fixture stays intact.
    for segment in ["__DATA_CONST", "__AUTH_CONST"] {
        var data = try Data(contentsOf: URL(fileURLWithPath: path))
        func u32(_ offset: Int) -> UInt32 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) } }
        func put(_ value: UInt32, at offset: Int) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
        }
        func name(_ offset: Int) -> String { String(decoding: data[offset..<(offset + 16)].prefix { $0 != 0 }, as: UTF8.self) }
        let renamed = Array("__MUTABLE".utf8) + [UInt8](repeating: 0, count: 7)
        var command = 32, changed = 0
        for _ in 0..<u32(16) {
            let size = Int(u32(command + 4))
            try #require(size >= 8 && command + size <= data.count)
            if u32(command) == 0x19 && name(command + 8) == segment { // LC_SEGMENT_64
                data.replaceSubrange((command + 8)..<(command + 24), with: renamed)
                put(u32(command + 68) & ~0x10, at: command + 68) // SG_READ_ONLY
                for index in 0..<Int(u32(command + 64)) {
                    let section = command + 72 + index * 80
                    data.replaceSubrange((section + 16)..<(section + 32), with: renamed)
                }
                changed += 1
            }
            command += size
        }
        try #require(changed == 1)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("mutable-body-pointer.dylib")
        try data.write(to: output)
        let mutable = try BinaryLoader.load(path: output.path)
        let modified = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: mutable,
            demangleSymbol: { _ in nil }).withSwiftErrorBodyProofs(facts)
        #expect(modified.holdsFixedPointer(at: slot) == (segment != "__DATA_CONST"))
        #expect(modified.holdsFixedPointer(at: root) == (segment != "__AUTH_CONST"))
        #expect(modified.bodyPreservesSwiftError(for: .loaded(slot)) == (segment != "__DATA_CONST"))
        #expect(modified.fixedFunctionTarget(for: .loadedThrough(slot: root, offset: 0)) == nil)
        #expect(!modified.bodyPreservesSwiftError(for: .loadedThrough(slot: root, offset: 0)))
        if segment == "__DATA_CONST" {
            #expect(modified.fixedFunctionTarget(for: .loaded(slot)) == nil)
        }
    }
}

@Test func returnOriginsFollowCopiesSpillsAndMustJoins() throws {
    for (words, wanted) in [
        ([0xd65f03c0], true),                                      // ret LR
        ([0xd65f0000], false),                                     // ret x0
        ([0xaa1e03f0, 0xd65f0200], true),                           // copy LR; ret x16
        ([0x1000003e, 0xd65f03c0], false),                         // replace LR; ret
        ([0xa9bf7bfd, 0xf94007f0, 0xa8c17bfd, 0xd65f0200], true),  // spill/reload LR into x16
        ([0xa9bf7bfd, 0xf90007e0, 0xa8c17bfd, 0xd65f03c0], false), // overwrite LR's save
        ([0xb4000060, 0xaa1e03f0, 0x14000002, 0xaa0003f0, 0xd65f0200], false), // disagree at join
        ([0xb4000060, 0xaa1e03f0, 0x14000002, 0xaa1e03f0, 0xd65f0200], true),  // same origin
        ([0xd65f03c0, 0xd65f0000], true),                           // orphan RET x0 is unreachable
        ([0xd503233f, 0xd50323bf, 0xd65f03c0], true),              // PACIASP; AUTIASP; ret
        ([0xd503237f, 0xd50323ff, 0xd65f03c0], true),              // PACIBSP; AUTIBSP; ret
        ([0xd503233f, 0xd65f0bff], true),                          // PACIASP; RETAA
        ([0xd503237f, 0xd65f0fff], true),                          // PACIBSP; RETAB
        ([0xd50320ff, 0xd65f03c0], true),                          // XPACLRI; ret
        ([0xaa0003fe, 0xd503233f, 0xd50323bf, 0xd65f03c0], false),  // Auth does not restore a replaced LR.
    ] as [([UInt32], Bool)] {
        let function = try swiftErrorBodyFunction(words, at: 0x1000)
        let proof = Preservation.ReturnAddressProof()
        let exits = Preservation.exitValues(blocks: function.basicBlocks(), entry: function.startAddress,
            addresses: Set(function.instructions.map(\.address)), returnAddressProof: proof)
        #expect(exits != nil && proof.acceptsExits == wanted)
    }
}

@Test func returnOriginsUseDirectMustClobbersEvenWithoutEntryRoleReplayIfPresent() throws {
    let path = "Fixtures/Sample/libPlainErrorSystem.O.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let disassembler = Disassembler()
    let boundaries = disassembler.functionStarts(of: image).sorted()
    let starts = Set(boundaries)
    for (callerName, calleeName, wanted) in [
        ("_system_error_return_register_dispatch", "_system_error_return_register_callee", false),
        ("_system_error_return_register_good_dispatch", "_system_error_return_register_keep", true),
    ] {
        func function(_ name: String) throws -> DisassembledFunction {
            let entry = UInt64(try #require(image.symbols.first { $0.name == name }).offset)
            let instructions = disassembler.decodeFunction(at: entry, boundaries: boundaries, in: image)
            return DisassembledFunction(symbol: name, demangledName: nil,
                startAddress: entry, instructions: instructions, source: .address)
        }
        let caller = try function(callerName), callee = try function(calleeName)
        let bodies = [caller.startAddress: caller, callee.startAddress: callee]
        var summaries = try bodies.mapValues { try #require(CalleeRegisterSummary.of($0, isFunction: starts.contains)) }
        #expect(summaries[caller.startAddress]?.hasProvenReturnTargets == true)
        #expect(summaries[caller.startAddress]?.needsReturnPreservation == true)
        #expect(summaries[callee.startAddress]?.clobberedCalleeSaved.contains("x19") == !wanted)
        #expect(summaries[callee.startAddress]?.definitelyClobbered.contains("x19") == false)
        CalleeRegisterSummary.closeOverCalls(&summaries, rebuildingEntryRoles: false) { address, effects, reads, reuse in
            guard let body = bodies[address] else { return nil }
            return CalleeRegisterSummary.recomputingPreservation(body, retainingReadsFrom: reads,
                reusingPreservation: reuse, rebuildingEntryRoles: false,
                calleeEffects: effects, isFunction: starts.contains)
        }
        #expect(summaries[caller.startAddress]?.hasProvenReturnTargets == wanted)
        #expect(CalleeRegisterFacts.finish(&summaries).facts[caller.startAddress]?.bodyPreservesSwiftError == wanted)
    }
}

@Test func unprovedReturnContextsAndOpenFallthroughsCannotDonateBodyFacts() throws {
    var unknown: [UInt64: CalleeRegisterSummary] = [0x1000: CalleeRegisterSummary(
        argumentReads: [], clobberedCalleeSaved: [], inputProofEntry: 0x1000, hasUnresolvedSwiftErrorCall: false)]
    #expect(CalleeRegisterFacts.finish(&unknown).facts[0x1000]?.bodyPreservesSwiftError == false)
    for (words, wanted) in [([0xd503201f], false), ([0x14000000], true)] as [([UInt32], Bool)] {
        // A NOP at the end of the decoded span falls into unmodelled code;
        // a closed self-loop has no unmodelled outgoing path.
        var summaries: [UInt64: CalleeRegisterSummary] = [0x1000: try swiftErrorBodySummary(words, at: 0x1000)]
        #expect(CalleeRegisterFacts.finish(&summaries).facts[0x1000]?.bodyPreservesSwiftError == wanted)
    }
}

@Test func bodyErrorProofsCloseStrictPreservationAcrossIntermediateHelpersIfPresent() throws {
    let path = "Fixtures/Sample/libPlainErrorSystem.O.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let disassembler = Disassembler()
    let boundaries = disassembler.functionStarts(of: image).sorted()
    let starts = Set(boundaries)
    func function(_ name: String) throws -> DisassembledFunction {
        let entry = UInt64(try #require(image.symbols.first { $0.name == name }).offset)
        return DisassembledFunction(symbol: name, demangledName: nil, startAddress: entry,
            instructions: disassembler.decodeFunction(at: entry, boundaries: boundaries, in: image), source: .address)
    }
    let root = try function("_system_error_return_deep_dispatch")
    let middle = try function("_system_error_return_deep_middle")
    let leaf = try function("_system_error_return_register_callee")
    let bodies = Dictionary(uniqueKeysWithValues: [root, middle, leaf].map { ($0.startAddress, $0) })
    var summaries = try bodies.mapValues { try #require(CalleeRegisterSummary.of($0, isFunction: starts.contains)) }
    CalleeRegisterSummary.closeOverCalls(&summaries, rebuildingEntryRoles: false) { address, effects, reads, reuse in
        guard let body = bodies[address] else { return nil }
        return CalleeRegisterSummary.recomputingPreservation(body, retainingReadsFrom: reads,
            reusingPreservation: reuse, rebuildingEntryRoles: false,
            calleeEffects: effects, isFunction: starts.contains)
    }
    // The ordinary carried MAY policy intentionally omits this stored x19
    // clobber, so the middle summary cannot supply a positive survival proof.
    #expect(summaries[leaf.startAddress]?.clobberedCalleeSaved.contains("x19") == true)
    #expect(summaries[leaf.startAddress]?.definitelyClobbered.contains("x19") == false)
    #expect(summaries[middle.startAddress]?.clobberedCalleeSaved.contains("x19") == false)
    #expect(summaries[root.startAddress]?.hasProvenReturnTargets == true)
    var withoutBodies = summaries
    #expect(CalleeRegisterFacts.finish(&withoutBodies).facts[root.startAddress]?.bodyPreservesSwiftError == false)
    let facts = CalleeRegisterFacts.finish(&summaries, body: { bodies[$0] }).facts
    #expect(facts[root.startAddress]?.bodyPreservesSwiftError == false)
    #expect(facts[middle.startAddress]?.bodyPreservesSwiftError == true)
    #expect(facts[leaf.startAddress]?.bodyPreservesSwiftError == true)
}

@Test func swiftErrorBodyOnlyFactsDoNotProjectArgumentOrResultContracts() throws {
    let root: UInt64 = 0x1000, extra: UInt64 = 0x2000
    let leaf = try swiftErrorBodySummary([0x91000400, 0xd65f03c0], at: root)
    var words = swiftErrorBodyCall(at: extra, to: root)
    words.insert(0x91000400, at: 2) // Read the call's x0 result.
    let caller = try swiftErrorBodySummary(words, at: extra, functions: [root, extra])
    let initial = [root: leaf, extra: caller]
    #expect(CalleeRegisterSummary.resultEvidence(initial).contains(root))
    var summaries = initial
    let finished = CalleeRegisterFacts.finish(&summaries, projecting: [root])
    #expect(finished.facts[extra]?.bodyPreservesSwiftError == true)
    #expect(finished.registerFacts[extra] == nil)
    #expect(finished.registerFacts[root]?.resultEvidence == false)
    #expect(finished.registerFacts[root]?.provenArgumentReads.contains(0) == true)
    #expect(summaries.isEmpty)
}

@Test func strictBodyReturnProofsFollowFrameAliasesThroughAllActualCallInputsIfPresent() throws {
    let path = "Fixtures/Sample/libPlainErrorSystem.O.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let disassembler = Disassembler()
    let boundaries = disassembler.functionStarts(of: image).sorted()
    let starts = Set(boundaries)
    func function(_ name: String) throws -> DisassembledFunction {
        let start = UInt64(try #require(image.symbols.first { $0.name == name }).offset)
        return DisassembledFunction(symbol: name, demangledName: nil, startAddress: start,
            instructions: disassembler.decodeFunction(at: start, boundaries: boundaries, in: image), source: .address)
    }
    for (kind, writerName, declaredArity) in [("fp", "_system_error_return_fp_alias_write", nil),
                                              ("gp", "__os_log_impl", 6)] as [(String, String, Int?)] {
        let prefix = "_system_error_return_" + kind + "_alias_"
        let leaf = try function(prefix + "leaf"), writer = try function(writerName)
        let middle = try function(prefix + "middle"), control = try function(prefix + "control")
        let bodies = Dictionary(uniqueKeysWithValues: [leaf, writer, middle, control].map { ($0.startAddress, $0) })
        let arity: (UInt64) -> Int? = { $0 == writer.startAddress ? declaredArity : nil }
        var summaries = try bodies.mapValues { try #require(CalleeRegisterSummary.of($0,
            calleeArity: arity, isFunction: starts.contains)) }
        CalleeRegisterSummary.closeOverReads(&summaries)
        CalleeRegisterSummary.closeOverCalls(&summaries, rebuildingEntryRoles: false) { address, effects, reads, reuse in
            guard let body = bodies[address] else { return nil }
            return CalleeRegisterSummary.recomputingPreservation(body, retainingReadsFrom: reads,
                reusingPreservation: reuse, rebuildingEntryRoles: false,
                calleeEffects: effects, calleeArity: arity, isFunction: starts.contains)
        }
        #expect(summaries[leaf.startAddress]?.clobberedCalleeSaved.contains("x19") == true)
        // The leaf stores x19 and never loads it back, so the clobber
        // carries; carried, it is an unknown value and no frame address,
        // and the strict closure below is what finds the alias.
        #expect(summaries[leaf.startAddress]?.definitelyClobbered.contains("x19") == true)
        #expect(summaries[middle.startAddress]?.hasProvenReturnTargets == true)
        if kind == "fp" {
            #expect((summaries[writer.startAddress]?.mayReadFloatArguments ?? 0) & 1 != 0)
            #expect((summaries[writer.startAddress]?.mayReadRegisters ?? 0) & 1 == 0)
        } else {
            #expect(DisassembledFunction.knownCArity(of: "_os_log_impl") == declaredArity)
            #expect((summaries[writer.startAddress]?.mayReadRegisters ?? 0) & (1 << 9) != 0)
        }
        let facts = CalleeRegisterFacts.finish(&summaries, body: { bodies[$0] }, calleeArity: arity).facts
        #expect(facts[middle.startAddress]?.bodyPreservesSwiftError == false, Comment(rawValue: kind))
        #expect(facts[control.startAddress]?.bodyPreservesSwiftError == false, Comment(rawValue: kind))
        #expect(facts[leaf.startAddress]?.bodyPreservesSwiftError == true)
        #expect(facts[writer.startAddress]?.bodyPreservesSwiftError == true)
    }
}

@Test func strictBodyReturnProofsDoNotTreatAFormalCountAsAnFPInputBound() throws {
    let entry: UInt64 = 0x1000, target: UInt64 = 0x3000
    let call = swiftErrorBodyCall(at: entry + 8, to: target)[1]
    let body = try swiftErrorBodyFunction([
        0xa9bf7bfd, 0x910003f3, 0x9e670260, call, 0xa8c17bfd, 0xd65f03c0,
    ], at: entry) // Save LR; mov x19,sp; fmov d0,x19; call; reload LR; ret.
    let arity: (UInt64) -> Int? = { $0 == target ? 1 : nil }
    let summary = try #require(CalleeRegisterSummary.of(body, calleeArity: arity))
    #expect(summary.hasProvenReturnTargets)
    #expect(summary.clobberedCalleeSaved.contains("x19"))
    var summaries = [entry: summary]
    // One source formal can be a Double containing pointer bits. A callee
    // preserving x21 can still overwrite this caller's saved LR through d0;
    // a parameter count supplies no integer-only register-bank proof.
    let facts = CalleeRegisterFacts.finish(&summaries,
        externalPreservesSwiftError: { $0 == target }, body: { $0 == entry ? body : nil }, calleeArity: arity).facts
    #expect(facts[entry]?.bodyPreservesSwiftError == false)
}
