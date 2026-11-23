import Testing
import Foundation
import Demangling
@testable import SwiftDecompilerCore

/// A register loaded from or stored to a field of self was known to equal
/// that field until the next store to a field, but a call may write the
/// field too: `field_aliases.swift` (-O) `let old = a; bumpA(); b = old`
/// rendered `bumpA(); self.b = self.a`, the incremented a, and
/// `let old = a; bumpA(); return old` rendered `return self.a`, the same
/// text as `bumpA(); return a`, which is right only there.
@Test func aFieldAliasDoesNotSurviveACallThatMayWriteItIfPresent() async throws {
    let path = "Fixtures/Sample/libFieldAliases.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    func pseudo(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FieldAliases.Box.\(name)(") }).renderPseudo()
    }
    let stale = try pseudo("stale")
    #expect(stale.contains("self.b = ") && !stale.contains("self.b = self.a"), "\(stale)")
    // A stored argument stays the argument, which no call can change.
    let storeTwice = try pseudo("storeTwice")
    #expect(storeTwice.contains("self.b = arg0\n"), "\(storeTwice)")
    let staleReturn = try pseudo("staleReturn")
    #expect(!staleReturn.contains("return self.a"), "\(staleReturn)")
    // A load after the call is the field's current value.
    let fresh = try pseudo("fresh")
    #expect(fresh.contains("return self.a\n"), "\(fresh)")
}

/// Only a retain or an access marker leaves every field alone. A release
/// can run a deinit, which may write a field of anything it reaches, and an
/// in-image function that merely shares a runtime name proves nothing.
@Test func onlyRetainsAndAccessMarkersWriteNoFields() {
    for callee in ["swift_retain", "_swift_bridgeObjectRetain", "objc_retain", "objc_retain_x19", "swift_beginAccess",
                   "swift_endAccess"] {
        let arc = DisassembledFunction.isARCReferenceHelper(callee)
        #expect(ValueTracer.CallFacts(callee: callee, arcIdentityContract: arc).writesNoFields, "\(callee)")
        if arc {
            #expect(!ValueTracer.CallFacts(callee: callee).writesNoFields, "unproved \(callee)")
            #expect(!ValueTracer.CallFacts(callee: callee, knownArityApplies: false,
                                          arcIdentityContract: true).writesNoFields, "local \(callee)")
        }
    }
    for callee in ["swift_release", "objc_release", "swift_bridgeObjectRelease", "Box.bumpA()", "memcpy"] {
        #expect(!ValueTracer.CallFacts(callee: callee).writesNoFields, "\(callee)")
    }
    #expect(!ValueTracer.CallFacts(callee: "swift_retain", knownArityApplies: false).writesNoFields)
}

/// -Osize outlines `swift_beginAccess` into `OUTLINED_FUNCTION_3`
/// (`mov x2, #0; mov x3, #0; b swift_beginAccess`), which writes no field
/// but is no runtime call by name: `Holder.total` loads `first` before it
/// and `second` after it, and `return (self.first + self.second)` read
/// `return ?` once calls forgot field names.
@Test func anOutlinedAccessMarkerKeepsFieldNamesIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.osize.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let total = try #require(functions.first { $0.displayName.hasPrefix("Reconstruction.BoxA.Holder.total.getter") })
        .renderPseudo()
    #expect(total.contains("return (self.first + self.second)"), "\(total)")
}

/// A body writes no field when it stores only through sp and calls only
/// runtime functions that write none, or bodies that write none.
@Test func onlyABodyThatStoresNothingAndCallsNothingThatWritesKeepsFields() throws {
    let engine = try #require(CapstoneEngine())
    let stub: UInt64 = 0x2000
    let bodies: [UInt64: [UInt32]] = [
        0x1000: [0xD280_0002, 0xD280_0003, 0x1400_03FE],  // mov x2, #0; mov x3, #0; b stub
        0x3000: [0xF900_0280, 0xD65F_03C0],               // str x0, [x20]; ret
        0x4000: [0x97FF_F400, 0xD65F_03C0],               // bl 0x1000; ret
        0x5000: [0xD63F_0100, 0xD65F_03C0],               // blr x8; ret
        0x6000: [0x9400_0400, 0xD65F_03C0],               // bl 0x7000; ret
        0x7000: [0x97FF_FC00, 0xD65F_03C0],               // bl 0x6000; ret
    ]
    var summaries: [UInt64: CalleeRegisterSummary] = [:]
    for (start, words) in bodies {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: start)
        try #require(decoded.count == words.count)
        let function = DisassembledFunction(symbol: "_f\(start)", demangledName: nil, startAddress: start,
            instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .symbol)
        summaries[start] = try #require(CalleeRegisterSummary.of(function, isFunction: { bodies[$0] != nil }))
    }
    CalleeRegisterSummary.closeOverFieldWrites(&summaries) { $0 == stub ? "swift_beginAccess" : nil }
    #expect(summaries[0x1000]?.writesNoFields == true)
    #expect(summaries[0x4000]?.writesNoFields == true)
    // A store through another register, an indirect call and a cycle prove nothing.
    for start: UInt64 in [0x3000, 0x5000, 0x6000, 0x7000] {
        #expect(summaries[start]?.writesNoFields == false, "\(String(start, radix: 16))")
    }
}

/// The toolchain's TriviaPiece copy only branches or tail-calls a proven
/// libswiftCore retain. Trivia.appending keeps its pieces pointer in x23
/// across that copy before querying uniqueness. The early body-summary pass
/// must carry the same provider proof as the later instruction analysis.
private enum ARCFieldAliasPipeline: String {
    case filtered, wholeFile, array, streaming, selectedFunctions
}

private func checkProvenOutlinedARCFieldAlias(_ pipeline: ARCFieldAliasPipeline) async throws {
    let locate = Process()
    locate.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    locate.arguments = ["--find", "swiftc"]
    let output = Pipe()
    locate.standardOutput = output
    try locate.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    locate.waitUntilExit()
    try #require(locate.terminationStatus == 0)
    let compiler = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let path = URL(fileURLWithPath: compiler).deletingLastPathComponent()
        .appendingPathComponent("../lib/swift/host/libSwiftSyntax.dylib").standardizedFileURL.path
    guard FileManager.default.fileExists(atPath: path) else { return }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        // Locate the ordinary function through symbol metadata. No analysis
        // route is used as setup for another route's proof.
        func targetAddress() throws -> UInt64 {
            var addresses = Set<UInt64>()
            for symbol in image.symbols where symbol.name.contains("6TriviaV9appending") {
                guard let address = UInt64(exactly: symbol.offset), address > 0 else { continue }
                var name = symbol.name
                if name.hasPrefix("_$") { name.removeFirst() }
                guard let node = try? demangleAsNode(name) else { continue }
                let printed = node.print(using: .default)
                let parts = printed.components(separatedBy: ".Trivia.appending(")
                guard parts.count == 2, !parts[0].contains(" "),
                      printed.contains(".TriviaPiece)") else { continue }
                addresses.insert(address)
            }
            try #require(addresses.count == 1, "Expected one ordinary TriviaPiece overload, found \(addresses.count)")
            return try #require(addresses.first)
        }
        let address = try targetAddress()
        func target(in functions: [DisassembledFunction]) throws -> DisassembledFunction {
            try #require(functions.first {
                $0.startAddress == address && $0.displayName.contains(".Trivia.appending(")
                    && $0.displayName.contains(".TriviaPiece)")
            })
        }
        let function: DisassembledFunction
        switch pipeline {
        case .filtered:
            function = try target(in: await Disassembler().disassemble(path: path, functionFilter: "Trivia.appending"))
        case .wholeFile:
            function = try target(in: await Disassembler().disassemble(path: path))
        case .array:
            function = try target(in: await Disassembler().disassemble(machO: image))
        case .streaming:
            let functions: [DisassembledFunction?] = await Disassembler().disassembleStreaming(machO: image) {
                $0.startAddress == address ? $0 : nil
            }
            function = try target(in: functions.compactMap { $0 })
        case .selectedFunctions:
            let functions = await Disassembler().analyzeEachFunction(at: [address], in: image, transform: { $0 })
            function = try target(in: Array(functions.values))
        }
        let retain = try #require(function.instructions.first {
            DisassembledFunction.calleeName(of: $0) == "swift_bridgeObjectRetain"
        })
        #expect(retain.facts.arcIdentityContract, "\(pipeline.rawValue): actual runtime import must be proved")
        let text = function.renderStructured()
        #expect(text.contains("isKnownUniquelyReferenced(self.pieces)"),
                Comment(rawValue: "\(pipeline.rawValue):\n\(text)"))
    }
}

@Test func provenOutlinedARCCopiesKeepFieldAliasesInFilteredPipelineIfHostSyntaxAvailable() async throws {
    try await checkProvenOutlinedARCFieldAlias(.filtered)
}
@Test func provenOutlinedARCCopiesKeepFieldAliasesInWholeFilePipelineIfHostSyntaxAvailable() async throws {
    try await checkProvenOutlinedARCFieldAlias(.wholeFile)
}
@Test func provenOutlinedARCCopiesKeepFieldAliasesInArrayPipelineIfHostSyntaxAvailable() async throws {
    try await checkProvenOutlinedARCFieldAlias(.array)
}
@Test func provenOutlinedARCCopiesKeepFieldAliasesInStreamingPipelineIfHostSyntaxAvailable() async throws {
    try await checkProvenOutlinedARCFieldAlias(.streaming)
}
@Test func provenOutlinedARCCopiesKeepFieldAliasesInSelectedFunctionsPipelineIfHostSyntaxAvailable() async throws {
    try await checkProvenOutlinedARCFieldAlias(.selectedFunctions)
}

/// The early closure must receive proof for the exact external target. A
/// local field-writing body and an unresolved name keep their own effects.
@Test func outlinedARCRetainsOnlyPreserveFieldsWithAnExactProvider() throws {
    let engine = try #require(CapstoneEngine())
    let helper: UInt64 = 0x1000, stub: UInt64 = 0x2000
    func summaries(localStub: Bool = false) throws -> [UInt64: CalleeRegisterSummary] {
        var bodies: [UInt64: [UInt32]] = [
            helper: [0xA9BF_7BFD, 0x9400_03FF, 0xA8C1_7BFD, 0xD65F_03C0],
        ]
        if localStub { bodies[stub] = [0xF900_0280, 0xD65F_03C0] }
        var result: [UInt64: CalleeRegisterSummary] = [:]
        for (start, words) in bodies {
            let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
            let decoded = engine.disassemble(Data(bytes), address: start)
            try #require(decoded.count == words.count)
            let function = DisassembledFunction(symbol: "_field_helper", demangledName: nil, startAddress: start,
                instructions: decoded.map {
                    Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                                branchTarget: $0.branchTarget, detail: $0.detail)
                }, source: .symbol)
            result[start] = try #require(CalleeRegisterSummary.of(function, isFunction: { bodies[$0] != nil }))
        }
        return result
    }
    let cases: [(String, String, Bool)] = [
        ("swift_retain", "/usr/lib/swift/libswiftCore.dylib", true),
        ("objc_retain", "/usr/lib/libobjc.A.dylib", true),
        ("swift_retain", "@rpath/libForeign.dylib", false),
        ("objc_retain", "@rpath/libForeign.dylib", false),
        ("swift_retain", "/usr/lib/libobjc.A.dylib", false),
        ("objc_retain", "/usr/lib/swift/libswiftCore.dylib", false),
    ]
    for (name, library, expected) in cases {
        var result = try summaries()
        let reference = RuntimeFunctionReference(rawSymbol: "_" + name, libraryName: library)
        CalleeRegisterSummary.closeOverFieldWrites(&result, arcIdentityContract: { target, callee in
            target == stub && reference.permitsARCIdentity(named: callee)
        }) { $0 == stub ? name : nil }
        #expect(result[helper]?.writesNoFields == expected, "\(name) from \(library)")
    }
    var unproved = try summaries()
    CalleeRegisterSummary.closeOverFieldWrites(&unproved) { $0 == stub ? "swift_retain" : nil }
    #expect(unproved[helper]?.writesNoFields == false)
    var unnamed = try summaries()
    CalleeRegisterSummary.closeOverFieldWrites(&unnamed, arcIdentityContract: { _, _ in true }, name: { _ in nil })
    #expect(unnamed[helper]?.writesNoFields == false)
    var local = try summaries(localStub: true)
    CalleeRegisterSummary.closeOverFieldWrites(&local, arcIdentityContract: { _, _ in true }) {
        $0 == stub ? "swift_retain" : nil
    }
    #expect(local[helper]?.writesNoFields == false)
    #expect(local[stub]?.writesNoFields == false)
}
