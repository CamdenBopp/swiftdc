import Foundation
import Testing
import Demangling
@_spi(Internals) import SwiftInspection
@testable import SwiftDecompilerCore

private let narrowIntegerReturnImages: [(path: String, oracle: String, bits: Int, signed: Bool)] = [
    ("Fixtures/Sample/libNarrowIntegerReturn.Int8.Onone.dylib", "Fixtures/Sample/narrow-integer-return-Int8.Onone-oracle", 8, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.Int16.Onone.dylib", "Fixtures/Sample/narrow-integer-return-Int16.Onone-oracle", 16, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.Int32.Onone.dylib", "Fixtures/Sample/narrow-integer-return-Int32.Onone-oracle", 32, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt8.Onone.dylib", "Fixtures/Sample/narrow-integer-return-UInt8.Onone-oracle", 8, false),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt16.Onone.dylib", "Fixtures/Sample/narrow-integer-return-UInt16.Onone-oracle", 16, false),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt32.Onone.dylib", "Fixtures/Sample/narrow-integer-return-UInt32.Onone-oracle", 32, false),
    ("Fixtures/Sample/libNarrowIntegerReturn.Int8.O.dylib", "Fixtures/Sample/narrow-integer-return-Int8.O-oracle", 8, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.Int16.O.dylib", "Fixtures/Sample/narrow-integer-return-Int16.O-oracle", 16, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.Int32.O.dylib", "Fixtures/Sample/narrow-integer-return-Int32.O-oracle", 32, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt8.O.dylib", "Fixtures/Sample/narrow-integer-return-UInt8.O-oracle", 8, false),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt16.O.dylib", "Fixtures/Sample/narrow-integer-return-UInt16.O-oracle", 16, false),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt32.O.dylib", "Fixtures/Sample/narrow-integer-return-UInt32.O-oracle", 32, false),
    ("Fixtures/Sample/libNarrowIntegerReturn.Int8.Osize.dylib", "Fixtures/Sample/narrow-integer-return-Int8.Osize-oracle", 8, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.Int16.Osize.dylib", "Fixtures/Sample/narrow-integer-return-Int16.Osize-oracle", 16, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.Int32.Osize.dylib", "Fixtures/Sample/narrow-integer-return-Int32.Osize-oracle", 32, true),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt8.Osize.dylib", "Fixtures/Sample/narrow-integer-return-UInt8.Osize-oracle", 8, false),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt16.Osize.dylib", "Fixtures/Sample/narrow-integer-return-UInt16.Osize-oracle", 16, false),
    ("Fixtures/Sample/libNarrowIntegerReturn.UInt32.Osize.dylib", "Fixtures/Sample/narrow-integer-return-UInt32.Osize-oracle", 32, false),
]
private let narrowIntegerReturnPathImages: [(path: String, oracle: String)] = [
    ("Fixtures/Sample/libNarrowIntegerReturnPaths.Paths.Onone.dylib", "Fixtures/Sample/narrow-integer-return-Paths.Onone-oracle"),
    ("Fixtures/Sample/libNarrowIntegerReturnPaths.Paths.O.dylib", "Fixtures/Sample/narrow-integer-return-Paths.O-oracle"),
    ("Fixtures/Sample/libNarrowIntegerReturnPaths.Paths.Osize.dylib", "Fixtures/Sample/narrow-integer-return-Paths.Osize-oracle"),
]

private func narrowIntegerReturnStages(_ path: String, prefix: String) async throws -> [DisassembledFunction] {
    let image = try BinaryLoader.load(path: path)
    var foundEntries: Set<UInt64> = []
    for symbol in image.symbols where symbol.offset != 0 && symbol.name.hasPrefix("_$s") {
        let name = try await demangleAsNode(String(symbol.name.dropFirst())).print(using: .default)
        if name.hasPrefix(prefix) { foundEntries.insert(UInt64(symbol.offset)) }
    }
    let entries = foundEntries
    try #require(entries.count == 1)
    try #require(entries.isSubset(of: Set(Disassembler().functionStarts(of: image))))
    var results: [DisassembledFunction] = []
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: path)
            case 1: return await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: path, functionFilter: "NarrowIntegerReturn")
            case 3:
                let values: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                    machO: image, transform: { entries.contains($0.startAddress) ? $0 : nil })
                return values.compactMap { $0 }
            default:
                // Include outlined helpers in this complete-context API comparison.
                return Array(await Disassembler().analyzeEachFunction(
                    at: Set(Disassembler().functionStarts(of: image)), in: image, transform: { $0 }).values)
            }
        }
        let selected = functions.filter { entries.contains($0.startAddress) }
        try #require(selected.count == 1)
        results += selected
    }
    return results
}

@Test func narrowIntegerReturnAtomsKeepTheirConversionAcrossAllAPIsIfPresent() async throws {
    for item in narrowIntegerReturnImages {
        guard FileManager.default.fileExists(atPath: item.path) else { continue }
        for function in try await narrowIntegerReturnStages(item.path, prefix: "NarrowIntegerReturn.narrow(") {
            for text in [function.renderPseudo(), function.renderStructured()] {
                let context = Comment(rawValue: item.path + "\n" + text)
                #expect(!text.contains("return arg0"), context)
                if item.signed {
                    #expect(text.contains("<< \(64 - item.bits)"), context)
                    #expect(text.contains(">>ˢ \(64 - item.bits)"), context)
                } else {
                    let mask = item.bits == 8 ? "255" : item.bits == 16 ? "0xffff" : "0xffffffff"
                    #expect(text.contains("& " + mask), context)
                }
            }
        }
    }
}

@Test func narrowIntegerSelectReturnsKeepTheirConversionAcrossAllAPIsIfPresent() async throws {
    for item in narrowIntegerReturnPathImages {
        guard FileManager.default.fileExists(atPath: item.path) else { continue }
        for function in try await narrowIntegerReturnStages(item.path, prefix: "NarrowIntegerReturnPaths.chooseNarrow(") {
            for text in [function.renderPseudo(), function.renderStructured()] {
                let context = Comment(rawValue: item.path + "\n" + text)
                #expect(text.contains(">>ˢ 56"), context)
                #expect(text.contains("arg0") && text.contains("arg1"), context)
            }
        }
    }
}

@Test func aStoredFieldCannotBypassANarrowIntegerReturnAcrossAllAPIsIfPresent() async throws {
    for item in narrowIntegerReturnPathImages {
        guard FileManager.default.fileExists(atPath: item.path) else { continue }
        for (stage, function) in (try await narrowIntegerReturnStages(item.path, prefix: "NarrowIntegerReturnPaths.NarrowBox.storeNarrow(")).enumerated() {
            for text in [function.renderPseudo(), function.renderStructured()] {
                let context = Comment(rawValue: item.path + " stage \(stage)\n" + text)
                // This API already declines the outlined helper at -Osize,
                // even with all starts requested. Preserve that exact baseline
                // result; it is not one of the wrong values this fix corrects.
                if stage == 4 && item.path.contains(".Osize.") {
                    #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == narrowOutlinedReturnDecline,
                            context)
                    continue
                }
                #expect(text.contains(">>ˢ 56"), context)
                #expect(text.contains("self.wide = arg0"), context)
                #expect(!text.contains("return self.wide"), context)
            }
        }
    }
}

@Test func narrowIntegerCallResultReturnsKeepTheirProducerAcrossAllAPIsIfPresent() async throws {
    for item in narrowIntegerReturnPathImages {
        guard FileManager.default.fileExists(atPath: item.path) else { continue }
        for function in try await narrowIntegerReturnStages(item.path, prefix: "NarrowIntegerReturnPaths.producerNarrow(") {
            for text in [function.renderPseudo(), function.renderStructured()] {
                let context = Comment(rawValue: item.path + "\n" + text)
                #expect(text.contains(">>ˢ 56"), context)
                #expect(text.components(separatedBy: "wideProducer(").count == 2, context)
            }
        }
    }
}

@Test func narrowIntegerReturnNativeControlsAtAllSwiftLevelsIfPresent() throws {
    let cases = narrowIntegerReturnImages.map { ($0.oracle, 16) }
        + narrowIntegerReturnPathImages.map { ($0.oracle, 40) }
        + narrowIntegerReturnFieldImages.map { ($0.oracle, 80) }
        + narrowIntegerReturnTailImages.map { ($0.oracle, 18) }
    for (path, count) in cases {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: path))
        let expected = count == 16 ? "PASS 16 isolated integer return observations\n"
            : count == 40 ? "PASS 40 native return-path observations\n"
            : count == 80 ? "PASS 80 native field return observations\n"
            : "PASS 18 native C atomic return observations\n"
        #expect(String(decoding: bytes, as: UTF8.self) == expected, Comment(rawValue: path))
    }
}

// The address-only analyzer does not currently inline this outlined helper.
// Pin its earlier decline separately from the corrected known return values.
@Test func aCallerOnlyNarrowReturnKeepsItsExistingOutlinedHelperDeclineIfPresent() async throws {
    let path = "Fixtures/Sample/libNarrowIntegerReturnPaths.Paths.Osize.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "storeNarrow")
    }
    let function = try #require(functions.first { $0.displayName.contains(".storeNarrow(") })
    let results = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: [function.startAddress], in: image, transform: { $0 })
    }
    let selected = try #require(results[function.startAddress])
    for text in [selected.renderPseudo(), selected.renderStructured()] {
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == narrowOutlinedReturnDecline, Comment(rawValue: text))
    }
}

private let narrowOutlinedReturnDecline = """
NarrowIntegerReturnPaths.NarrowBox.storeNarrow(Swift.Int64) -> Swift.Int8 {
    OUTLINED_FUNCTION_0(arg0)
    self.wide = …
    return ?
}
"""

private let narrowIntegerReturnFieldImages: [(path: String, oracle: String)] = [
    ("Fixtures/Sample/libNarrowIntegerReturnFields.Fields.Onone.dylib", "Fixtures/Sample/narrow-integer-return-Fields.Onone-oracle"),
    ("Fixtures/Sample/libNarrowIntegerReturnFields.Fields.O.dylib", "Fixtures/Sample/narrow-integer-return-Fields.O-oracle"),
    ("Fixtures/Sample/libNarrowIntegerReturnFields.Fields.Osize.dylib", "Fixtures/Sample/narrow-integer-return-Fields.Osize-oracle"),
]

@Test func narrowIntegerReturnsKeepTheirProvenFieldViewsAcrossAllAPIsIfPresent() async throws {
    for item in narrowIntegerReturnFieldImages {
        guard FileManager.default.fileExists(atPath: item.path) else { continue }
        for property in ["byte", "signed", "middle"] {
            let prefix = "NarrowIntegerReturnFields.FieldBox." + property + ".getter :"
            for function in try await narrowIntegerReturnStages(item.path, prefix: prefix) {
                for text in [function.renderPseudo(), function.renderStructured()] {
                    let expected = property == "byte" ? "return (self.byte & 255)"
                        : property == "signed" ? "return ((self.signed << 48) >>ˢ 48)"
                        : "return (self.middle & 0xffffffff)"
                    #expect(text.contains(expected), Comment(rawValue: item.path + "\n" + text))
                }
            }
        }
        for prefix in ["NarrowIntegerReturnFields.FieldBox.narrowedWide(", "NarrowIntegerReturnFields.WordBox.narrowed("] {
            for function in try await narrowIntegerReturnStages(item.path, prefix: prefix) {
                for text in [function.renderPseudo(), function.renderStructured()] {
                    #expect(text.contains(">>ˢ 56"), Comment(rawValue: item.path + "\n" + text))
                }
            }
        }
    }
}

private let narrowIntegerReturnTailImages: [(path: String, oracle: String)] = [
    ("Fixtures/Sample/libNarrowIntegerReturnTail.Tail.Onone.dylib", "Fixtures/Sample/narrow-integer-return-Tail.Onone-oracle"),
    ("Fixtures/Sample/libNarrowIntegerReturnTail.Tail.O.dylib", "Fixtures/Sample/narrow-integer-return-Tail.O-oracle"),
    ("Fixtures/Sample/libNarrowIntegerReturnTail.Tail.Osize.dylib", "Fixtures/Sample/narrow-integer-return-Tail.Osize-oracle"),
]

@Test func narrowIntegerCTailReturnsDeclineWithoutDroppingTheirCallAcrossAllAPIsIfPresent() async throws {
    for item in narrowIntegerReturnTailImages {
        guard FileManager.default.fileExists(atPath: item.path) else { continue }
        for function in try await narrowIntegerReturnStages(item.path, prefix: "NarrowIntegerReturnTail.unsignedAtomic(") {
            if !item.path.contains(".Onone.") {
                let tail = try #require(function.instructions.first { $0.callBeforeReturn != nil })
                let copied = Instruction(address: tail.address, text: tail.text,
                    annotation: #""call-before-return: fake_call()  return 42""#,
                    controlFlow: tail.controlFlow, branchTarget: tail.branchTarget,
                    callArguments: tail.callArguments, callSelf: tail.callSelf,
                    resultConsumed: tail.resultConsumed, sourceType: tail.sourceType, detail: tail.detail,
                    callee: .kept(tail.callee), facts: tail.facts)
                #expect(DisassembledFunction.pseudoStatement(of: copied, hideRuntime: true)
                    == DisassembledFunction.pseudoStatement(of: tail, hideRuntime: true))
                #expect(DisassembledFunction.pseudoStatement(of: copied, hideRuntime: true)?.contains("fake_call") == false)
            }
            for text in [function.renderPseudo(), function.renderStructured()] {
                let details = Comment(rawValue: item.path + "\n" + text)
                #expect(text.contains("return ?"), details)
                #expect(!text.contains("return OSAtomicAdd32("), details)
                #expect(text.components(separatedBy: "OSAtomicAdd32(").count == 2, details)
                let effect = try #require(text.range(of: "OSAtomicAdd32("))
                let returned = try #require(text.range(of: "return ?"))
                #expect(effect.lowerBound < returned.lowerBound, details)
            }
        }
    }
}

@Test func narrowIntegerCTailFixtureUsesItsActualCProviderIfPresent() throws {
    for item in narrowIntegerReturnTailImages {
        guard FileManager.default.fileExists(atPath: item.path) else { continue }
        let image = try BinaryLoader.load(path: item.path)
        #expect(image.header.flags.contains(.twolevel))
        #expect(!image.header.flags.contains(.force_flat))
        let symbol = try #require(image.symbols.first { $0.name == "_OSAtomicAdd32" && $0.offset == 0 })
        let description = try #require(symbol.nlist.symbolDescription)
        #expect(description.libraryOrdinalType == nil)
        let index = Int(description.libraryOrdinal) - 1
        let dependencies = Array(image.dependencies)
        try #require(dependencies.indices.contains(index))
        #expect(dependencies[index].dylib.name == "/usr/lib/libSystem.B.dylib")
    }
}
