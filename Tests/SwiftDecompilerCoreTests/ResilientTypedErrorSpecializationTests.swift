import Darwin
import Foundation
import Demangling
import Testing
@testable import SwiftDecompilerCore

// The real two-module fixture has @out T and @error_indirect RemoteError.
// Tt1 drops SIL index 2, so its specialized formals are (Double, Int).
private let resilientRemote = "$s12RemoteClient6remoteyxxm_xSit0A6Errors0A5ErrorOYKlFSd_Tt1g5"
private let resilientKept = "$s12RemoteClient9keepValueyxx_Sit0A6Errors0A5ErrorOYKlFSd_Tg5"
private let keptSignature = "RemoteClient.keepValue(Swift.Double, Swift.Int) throws(RemoteErrors.RemoteError) -> Swift.Double"
private let remoteTitle = "generic specialization <Swift.Double> of RemoteClient.remote<A>"

private func specializationName(_ symbol: String) throws -> String {
    try demangleAsNode(symbol.hasPrefix("_$s") ? String(symbol.dropFirst()) : symbol).print(using: .default)
}

@Test func aResilientTypedErrorDoesNotMisindexADroppedMetatype() throws {
    #expect(DisassembledFunction.specializedSignature(symbol: resilientRemote,
        printedName: try specializationName(resilientRemote)) == nil)
}

@Test func aTypedErrorWithoutDroppedArgumentsStillSubstitutes() throws {
    #expect(DisassembledFunction.specializedSignature(symbol: resilientKept,
        printedName: try specializationName(resilientKept)) == keptSignature)
}

/// Keep the baseline's two explicit unknown values or fully decline. A sole
/// arg0 (-O) or outlined helper result (-Osize) is neither source's true ABI.
@Test func resilientTypedErrorCallsDoNotGuessAfterAReaderDeclineIfPresent() async throws {
    let variants = [("Fixtures/Sample/libResilientTypedError.dylib", 12, 2),
                    ("Fixtures/Sample/libResilientTypedError.Osize.dylib", 27, 1)]
    for (binary, functionCount, directCalls) in variants {
        let path = binary
        guard FileManager.default.fileExists(atPath: path) else { return }
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        for (symbol, failure) in [("resilient_typed_error_probe", -1.0), ("resilient_typed_error_keep_probe", -2.0)] {
            let native = unsafeBitCast(try #require(dlsym(library, symbol)),
                to: (@convention(c) (Int64, Double) -> Double).self)
            for (n, value) in [(Int64(0), 1.25), (5, -2.5), (-1, 3.75), (-9, -8.5)] {
                #expect(native(n, value) == (n < 0 ? failure : value))
            }
        }
        let array = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "RemoteClient")
        }
        let streamed = try await withStableDependencies {
            let image = try BinaryLoader.load(path: path)
            return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        // Independent NM text-address and LC_FUNCTION_STARTS sets agree with
        // these whole-image counts; eight symbols name RemoteClient in each.
        try #require(array.count == functionCount)
        try #require(streamed.count == functionCount)
        try #require(filtered.count == 8)
        for (mode, functions) in [("array", array), ("filtered", filtered), ("streaming", streamed)] {
            let remote = functions.filter { $0.symbol == "_" + resilientRemote }
            let kept = functions.filter { $0.symbol == "_" + resilientKept }
            try #require(remote.count == 1, "\(binary) \(mode): dropped symbol missing")
            try #require(kept.count == 1, "\(binary) \(mode): control symbol missing")
            let target = try #require(remote.first).startAddress
            for function in remote {
                #expect(DisassembledFunction.specializedSignature(symbol: function.symbol,
                    printedName: try specializationName(function.symbol)) == nil, "\(binary) \(mode)")
            }
            for function in kept {
                #expect(DisassembledFunction.specializedSignature(symbol: function.symbol,
                    printedName: try specializationName(function.symbol)) == keptSignature, "\(binary) \(mode)")
            }
            let calls = functions.flatMap(\.instructions).filter {
                $0.branchTarget == target && ($0.controlFlow == .call || $0.controlFlow == .branch)
            }
            try #require(calls.count == (mode == "filtered" ? 1 : directCalls))
            for call in calls {
                #expect(call.callArguments == ["?", "?"] || call.callArguments == ["…"],
                        "\(binary) \(mode): \(call.annotation ?? "")")
                let statement = try #require(DisassembledFunction.pseudoStatement(of: call, hideRuntime: true))
                #expect(statement == remoteTitle + "(?, ?)" || statement == remoteTitle + "(…)",
                        "\(binary) \(mode): \(statement)")
            }
        }
    }
}

/// A valid analysis seed can know no incoming register values. The target
/// symbol is real, but a capped/unsupported body may have no summary. Lack of
/// both snapshots must still render an explicit unknown argument list.
@Test func anUnprovenTypedErrorCallWithoutATracerSiteStillDeclines() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typed-error-no-site-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withStableDependencies {
        let machO = try BinaryLoader.load(path: file.path)
        let name = try specializationName(resilientRemote)
        var resolver = Disassembler.ReferenceResolver(names: [0x3000: name], stringRanges: [],
            machO: machO, demangleSymbol: { _ in nil })
        resolver.specializationSymbols[0x3000] = "_" + resilientRemote
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [0x3000],
            objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
            selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
            enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
            classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
            asyncIndex: .empty, asyncChainSlots: [:])
        let engine = try #require(CapstoneEngine())
        // Erase the default incoming x8 result pointer too. LDR from an
        // unknown base leaves no known argument, error, self or result value.
        for words: [UInt32] in [[0xf9400128, 0x940007ff, 0xd65f03c0], [0xf9400128, 0x140007ff]] { // ldr x8,[x9]; bl/b 0x3000
            let decoded = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000)
            try #require(decoded.count == words.count)
            let instructions = decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail,
                    callee: .kept($0.controlFlow == .call || $0.controlFlow == .branch ? name : nil))
            }
            let raw = DisassembledFunction(symbol: "opaque_caller", demangledName: nil,
                startAddress: 0x1000, instructions: instructions, source: .symbol)
            let trace = ValueTracer().analyze(raw, entry: nil)
            try #require(trace.callSites.isEmpty && trace.branchSites.isEmpty)
            let analyzed = Disassembler().analyzeFunction(raw, context: context)
            let call = try #require(analyzed.instructions.first { $0.controlFlow == .call || $0.controlFlow == .branch })
            #expect(call.callArguments == ["…"], "\(call.annotation ?? "")")
            #expect(analyzed.renderPseudo().contains(remoteTitle + "(…)"))
        }
    }
}
