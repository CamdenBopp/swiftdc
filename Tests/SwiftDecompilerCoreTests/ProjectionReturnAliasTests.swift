import Foundation
import Testing
@_spi(Internals) import SwiftInspection
@testable import SwiftDecompilerCore

private let returnedProjectionPaths = [
    "Fixtures/Sample/libProjectionReturnAlias.dylib",
    "Fixtures/Sample/libProjectionReturnAlias.stripped.dylib",
]

private let returnedProjectionNames = (1...2).flatMap { shape in
    (0...2).flatMap { boxed in
        (0...6).map { "projectionAliasS\(shape)B\(boxed)M\($0)" }
    }
}

private let returnedProjectionCallers = returnedProjectionNames + [
    "projectionAliasUnrelatedFrameWord", "projectionAliasTwoProducers", "projectionAliasIndirectResult",
    "projectionAliasLogicalResultWrites", "projectionAliasLogicalResultIgnored", "projectionAliasTupleResultWrites",
]

private func returnedProjectionStages(_ path: String) async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    let entries = Set(image.symbols.filter {
        returnedProjectionCallers.contains(String($0.name.dropFirst()))
    }.map { UInt64($0.offset) })
    try #require(entries.count == 48)
    var stages: [[DisassembledFunction]] = []
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: path)
            case 1: return try await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: path, functionFilter: "projectionAlias")
            case 3:
                let values: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                    machO: image, transform: { entries.contains($0.startAddress) ? $0 : nil })
                return values.compactMap { $0 }
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

private func returnedProjectionProcess(_ path: String, arguments: [String] = []) throws -> (Int32, String, String) {
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

@Test func projectionReturnedAliasNativeControlsIfPresent() throws {
    for path in [
        "Fixtures/Sample/projection-return-alias-O0-oracle",
        "Fixtures/Sample/projection-return-alias-O2-oracle",
        "Fixtures/Sample/projection-return-alias-Os-oracle",
    ] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let (exit, output, error) = try returnedProjectionProcess(URL(fileURLWithPath: path).path)
        #expect(exit == 0, Comment(rawValue: path + "\n" + error))
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines.count == 49, Comment(rawValue: output))
        for name in returnedProjectionNames {
            let expected = name.hasSuffix("M0") || name.hasSuffix("M5") ? 8 : 42
            #expect(lines.contains("\(name) expected=\(expected) actual=\(expected)"), Comment(rawValue: output))
        }
        #expect(lines.contains("projectionAliasUnrelatedFrameWord expected=165 actual=165"), Comment(rawValue: output))
        #expect(lines.contains("projectionAliasTwoProducers expected=49 actual=49"), Comment(rawValue: output))
        #expect(lines.contains("projectionAliasIndirectResult expected=42 actual=42"), Comment(rawValue: output))
        #expect(lines.contains("projectionAliasLogicalResultWrites expected=42 actual=42"), Comment(rawValue: output))
        #expect(lines.contains("projectionAliasLogicalResultIgnored expected=8 actual=8"), Comment(rawValue: output))
        #expect(lines.contains("projectionAliasTupleResultWrites expected=42 actual=42"), Comment(rawValue: output))
        #expect(lines.last == "PASS 48 returned-projection-alias observations")
    }
    var priorStarts: [String]?
    for path in returnedProjectionPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let (exit, symbols, error) = try returnedProjectionProcess("/usr/bin/xcrun", arguments: ["nm", "-m", "-arch", "arm64", path])
        #expect(exit == 0, Comment(rawValue: error))
        let imports = symbols.split(separator: "\n").filter { $0.contains("_getpid (from libSystem)") }
        #expect(imports.count == 1)
        #expect(imports.first?.contains("(undefined) external") == true)
        #expect(imports.first?.contains("weak") == false)
        for raw in ["_$s13ProjectionABI8identityyS2iF", "_$s13ProjectionABI9carryPairySv_SitSv_SitF"] {
            let defined = symbols.split(separator: "\n").filter { $0.hasSuffix(" " + raw) }
            #expect(defined.count == 1 && defined[0].contains("(__TEXT,__text) external"))
        }
        let (rawExit, raw, rawError) = try returnedProjectionProcess("/usr/bin/xcrun", arguments: [
            "llvm-objdump", "--macho", "--disassemble", path,
        ])
        #expect(rawExit == 0, Comment(rawValue: rawError))
        #expect(raw.range(of: #"mov\s+w8, #0x29"#, options: .regularExpression) != nil)
        #expect(raw.range(of: #"str\s+w8, \[x0\]"#, options: .regularExpression) != nil)
        #expect(raw.range(of: #"ldr\s+w0, \[sp, #0x50\]"#, options: .regularExpression) != nil)
        let (startsExit, text, startsError) = try returnedProjectionProcess("/usr/bin/xcrun", arguments: [
            "llvm-objdump", "--macho", "--function-starts", path,
        ])
        #expect(startsExit == 0, Comment(rawValue: startsError))
        let starts = text.split(separator: "\n").map(String.init).filter {
            $0.range(of: #"^[0-9a-f]{16}$"#, options: .regularExpression) != nil
        }
        #expect(starts.count == 56)
        if let priorStarts { #expect(starts == priorStarts) }
        priorStarts = starts
    }
}

@Test func projectionReturnedAliasesDoNotKeepStaleFrameValuesAcrossAllAPIsIfPresent() async throws {
    for path in returnedProjectionPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for functions in try await returnedProjectionStages(path) {
            for function in functions where returnedProjectionNames.contains(String(function.symbol.dropFirst()))
                && !function.symbol.hasSuffix("M0")
                && !function.symbol.hasSuffix("M5") {
                let helper = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0)?.contains("project_boxed_opaque_existential") == true
                })
                #expect(helper.facts.bodyProjectsBoxedExistential, Comment(rawValue: function.render()))
                if function.symbol.contains("B2") {
                    // The saved word separates the box header from its payload.
                    // Container escape reach alone must not rescue this case.
                    #expect(ValueTracer.frameLayout(function.instructions).saveSlots.contains(-56))
                }
                let consumer = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "projectionAliasConsumeWord"
                })
                #expect(consumer.callArguments == ["?"] || consumer.callArguments == ["41"], Comment(rawValue: function.render()))
                for text in [function.renderPseudo(), function.renderStructured()] {
                    let context = Comment(rawValue: path + "\n" + text)
                    #expect(text.contains("projectionAliasConsumeWord(?)") || text.contains("projectionAliasConsumeWord(41)"), context)
                    #expect(!text.contains("projectionAliasConsumeWord(7)"), context)
                    #expect(text.components(separatedBy: "projectionAliasConsumeWord(").count == 2, context)
                    if function.symbol.hasSuffix("M1") || function.symbol.hasSuffix("M6") {
                        #expect(text.contains("mem32[") && text.contains("= 41"), context)
                    } else {
                        #expect(text.components(separatedBy: "projectionAliasMutate(").count == 2, context)
                    }
                }
            }
        }
    }
}

@Test func ignoredProjectionResultsKeepUnescapedFrameValuesAcrossAllAPIsIfPresent() async throws {
    for path in returnedProjectionPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for functions in try await returnedProjectionStages(path) {
            for function in functions where function.symbol.hasSuffix("M0") == true || function.symbol.hasSuffix("M5") == true {
                let helper = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0)?.contains("project_boxed_opaque_existential") == true
                })
                #expect(helper.facts.bodyProjectsBoxedExistential)
                let consumer = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "projectionAliasConsumeWord"
                })
                #expect(consumer.callArguments == ["7"], Comment(rawValue: function.render()))
                if function.symbol.hasSuffix("M5") == true {
                    let unrelated = try #require(function.instructions.first {
                        $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "getpid"
                    })
                    #expect(unrelated.facts.namedABIContract)
                }
                for text in [function.renderPseudo(), function.renderStructured()] {
                    #expect(text.contains("projectionAliasConsumeWord(7)"), Comment(rawValue: text))
                }
            }
        }
    }
}

@Test func projectionReturnedAliasWritesPreserveAnUnrelatedFrameWordAcrossAllAPIsIfPresent() async throws {
    for path in returnedProjectionPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for functions in try await returnedProjectionStages(path) {
            let function = try #require(functions.first { $0.symbol == "_projectionAliasUnrelatedFrameWord" })
            let consumer = try #require(function.instructions.first {
                $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "projectionAliasConsumePair"
            })
            #expect(consumer.callArguments == ["?", "123"] || consumer.callArguments == ["41", "123"], Comment(rawValue: function.render()))
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("projectionAliasConsumePair(?, 123)") || text.contains("projectionAliasConsumePair(41, 123)"), Comment(rawValue: text))
            }
        }
    }
}

@Test func projectionReturnedOriginsStayWithTheirOwnProducerAcrossAllAPIsIfPresent() async throws {
    for path in returnedProjectionPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for functions in try await returnedProjectionStages(path) {
            let function = try #require(functions.first { $0.symbol == "_projectionAliasTwoProducers" })
            let helpers = function.instructions.filter {
                $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0)?.contains("project_boxed_opaque_existential") == true
            }
            #expect(helpers.count == 2 && helpers.allSatisfy { $0.facts.bodyProjectsBoxedExistential })
            let consumer = try #require(function.instructions.first {
                $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "projectionAliasConsumePair"
            })
            #expect(consumer.callArguments == ["7", "?"] || consumer.callArguments == ["7", "41"], Comment(rawValue: function.render()))
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("projectionAliasConsumePair(7, ?)") || text.contains("projectionAliasConsumePair(7, 41)"), Comment(rawValue: text))
            }
        }
    }
}

@Test func projectionReturnedOriginsSurviveLateIndirectResolutionAcrossAllAPIsIfPresent() async throws {
    for path in returnedProjectionPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for functions in try await returnedProjectionStages(path) {
            let function = try #require(functions.first { $0.symbol == "_projectionAliasIndirectResult" })
            let helper = try #require(function.instructions.first { $0.text.hasPrefix("blr") })
            #expect(helper.facts.bodyProjectsBoxedExistential, Comment(rawValue: function.render()))
            let consumer = try #require(function.instructions.first {
                $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "projectionAliasConsumeWord"
            })
            #expect(consumer.callArguments == ["?"] || consumer.callArguments == ["41"], Comment(rawValue: function.render()))
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("projectionAliasConsumeWord(?)") || text.contains("projectionAliasConsumeWord(41)"), Comment(rawValue: text))
            }
        }
    }
}

@Test func projectionReturnedOriginsSurviveLogicalResultBoundariesAcrossAllAPIsIfPresent() async throws {
    let cases = ["projectionAliasLogicalResultWrites", "projectionAliasLogicalResultIgnored", "projectionAliasTupleResultWrites"]
    for path in returnedProjectionPaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        for functions in try await returnedProjectionStages(path) {
            for name in cases {
                let function = try #require(functions.first { $0.symbol == "_" + name })
                let raw = name.contains("Tuple") ? "_$s13ProjectionABI9carryPairySv_SitSv_SitF"
                    : "_$s13ProjectionABI8identityyS2iF"
                let target = UInt64(try #require(image.symbols.first { $0.name == raw }).offset)
                // Presentation names can differ in indexed subset analysis.
                // The exported entry fixes the physical result boundary.
                let logical = try #require(function.instructions.first {
                    $0.controlFlow == .call && $0.branchTarget == target
                }, Comment(rawValue: path + "\n" + function.render()))
                #expect(!logical.facts.bodyProjectsBoxedExistential)
                #expect(!logical.facts.namedABIContract)
                let consumer = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0) == "projectionAliasConsumeWord"
                })
                let ignored = name.hasSuffix("Ignored")
                #expect(ignored ? consumer.callArguments == ["7"]
                    : consumer.callArguments == ["?"] || consumer.callArguments == ["41"], Comment(rawValue: function.render()))
                for text in [function.renderPseudo(), function.renderStructured()] {
                    #expect(ignored ? text.contains("projectionAliasConsumeWord(7)")
                        : text.contains("projectionAliasConsumeWord(?)") || text.contains("projectionAliasConsumeWord(41)"), Comment(rawValue: text))
                }
            }
        }
    }
}

@Test func projectionOriginJoinsRetainEveryPossibleFrameWrite() throws {
    let site: UInt64 = 0x1000
    var near = ValueTracer.State(dictionaryLiteral: (.x(0), .callResult(site)))
    near.keepProjectedOrigin(.atOrAbove(-16), at: site)
    var far = ValueTracer.State(dictionaryLiteral: (.x(0), .callResult(site)))
    far.keepProjectedOrigin(.atOrAbove(-48), at: site)
    let absent = ValueTracer.State(dictionaryLiteral: (.x(0), .callResult(site)))
    for states in [[near, far], [far, near], [far, absent], [absent, far]] {
        let joined = ValueTracer.meet(states)
        #expect(joined[.x(0)] == .callResult(site))
        let writes = try #require(joined.projectedOrigin(at: site)).writeEffect
        #expect(writes.mayInvalidate(FrameMemoryExtent(start: -48, bytes: 8)))
        #expect(writes.mayInvalidate(FrameMemoryExtent(start: -16, bytes: 8)))
        #expect(!writes.mayInvalidate(FrameMemoryExtent(start: -80, bytes: 8)))
        #expect(joined[.frameEscapedAll] == nil) // Latent provenance is not capture.
    }
    var whole = absent
    whole.keepProjectedOrigin(.whole, at: site)
    let joined = ValueTracer.meet([near, whole])
    #expect(try #require(joined.projectedOrigin(at: site)).writeEffect.mayInvalidate(
        FrameMemoryExtent(start: -1024, bytes: 8)))
}

@Test func projectionOriginPresenceCountsAndDoesNotNormalizeToAnUnknownRegister() {
    let empty = ValueTracer.State()
    var whole = ValueTracer.State()
    whole.keepProjectedOrigin(.whole, at: 0x1000)
    #expect(!whole.isEmpty && whole.count > empty.count)
    #expect(!ValueTracer.sameFacts(empty, whole))
    #expect(!ValueTracer.sameFacts(whole, empty))
    #expect(ValueTracer.sameFacts(empty, ValueTracer.State(dictionaryLiteral: (.x(0), .unknown))))
    whole.removeAll()
    #expect(whole == empty && whole.isEmpty)
}

@Test func projectionOriginsKeepOpaqueProducerIdentityAndWidenUnboundedUses() throws {
    let first = AbstractValue.callResult(0x1000), second = AbstractValue.callResult(0x2000)
    var state = ValueTracer.State(dictionaryLiteral: (.x(0), first))
    state.keepProjectedOrigin(.atOrAbove(-32), at: 0x1000)
    state.keepProjectedOrigin(.atOrAbove(-96), at: 0x2000)
    #expect(state[.x(0)] == first)
    #expect(!ValueTracer.containsFrame(first)) // MAY metadata supplies no exact frame value.
    #expect(ValueTracer.projectedOrigin(of: .callResult(0x3000), in: state) == nil)
    #expect(ValueTracer.projectedOrigin(of: .callResultHigh(0x1000), in: state) == nil)
    #expect(ValueTracer.projectedOrigin(of: first, in: ValueTracer.State()) == nil)
    let select = AbstractValue.select(condition: .unknown, whenTrue: first, whenFalse: second)
    let selected = try #require(ValueTracer.projectedOrigin(of: select, in: state)).writeEffect
    #expect(selected.mayInvalidate(FrameMemoryExtent(start: -96, bytes: 8)))
    #expect(!selected.mayInvalidate(FrameMemoryExtent(start: -128, bytes: 8)))
    #expect(ValueTracer.projectedOrigin(of: .select(condition: first, whenTrue: .immediate(0), whenFalse: .immediate(1)), in: state) == nil)
    for value in [AbstractValue.binary(.add, first, .immediate(4)), .unary(.bitPattern(bits: 64), first), .loadedFrom(first, offset: 0)] {
        #expect(try #require(ValueTracer.projectedOrigin(of: value, in: state)).writeEffect.mayInvalidate(
            FrameMemoryExtent(start: -1024, bytes: 8)))
    }
    let packed = try #require(ValueTracer.projectedOrigin(of: .aggregate([first, second]), in: state)).writeEffect
    #expect(packed.mayInvalidate(FrameMemoryExtent(start: -96, bytes: 8)))
}

@Test func projectionOriginsLostFromValuesStillEscapeButMetadataAloneDoesNot() {
    let site: UInt64 = 0x1000
    let places: [ValueTracer.Location] = [.x(19), .stack(-32), .contextSlot(16), .result(offset: 0, bytes: 8)]
    for place in places {
        var pointer = ValueTracer.State(dictionaryLiteral: (place, .callResult(site)))
        pointer.keepProjectedOrigin(.atOrAbove(-48), at: site)
        let other = ValueTracer.State(dictionaryLiteral: (place, .immediate(0)))
        for states in [[pointer, other], [other, pointer]] {
            #expect(ValueTracer.meet(states)[.frameEscapedAll] != nil)
        }
    }
    var copyOnly = ValueTracer.State(dictionaryLiteral: (.outgoing(-32), .callResult(site)))
    copyOnly.keepProjectedOrigin(.atOrAbove(-48), at: site)
    let missingCopy = ValueTracer.State()
    #expect(ValueTracer.meet([copyOnly, missingCopy])[.frameEscapedAll] == nil)
}
