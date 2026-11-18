import Foundation
import Testing
import Demangling
@_spi(Internals) import SwiftInspection
@testable import SwiftDecompilerCore

private let integerTailImages = [
    (level: "Onone", module: "SwiftTailResults", path: "Fixtures/Sample/libSwiftTailResults.Onone.dylib", oracle: "Fixtures/Sample/narrow-integer-return-TailResults.Onone-oracle"),
    (level: "O", module: "SwiftTailResults", path: "Fixtures/Sample/libSwiftTailResults.O.dylib", oracle: "Fixtures/Sample/narrow-integer-return-TailResults.O-oracle"),
    (level: "Osize", module: "SwiftTailResults", path: "Fixtures/Sample/libSwiftTailResults.Osize.dylib", oracle: "Fixtures/Sample/narrow-integer-return-TailResults.Osize-oracle"),
    (level: "Onone", module: "SwiftTailGetters", path: "Fixtures/Sample/libSwiftTailGetters.Onone.dylib", oracle: "Fixtures/Sample/narrow-integer-return-TailGetters.Onone-oracle"),
    (level: "O", module: "SwiftTailGetters", path: "Fixtures/Sample/libSwiftTailGetters.O.dylib", oracle: "Fixtures/Sample/narrow-integer-return-TailGetters.O-oracle"),
    (level: "Osize", module: "SwiftTailGetters", path: "Fixtures/Sample/libSwiftTailGetters.Osize.dylib", oracle: "Fixtures/Sample/narrow-integer-return-TailGetters.Osize-oracle"),
]

private struct IntegerTailSpec: Sendable {
    let function: String
    let callee: String
    let bits: Int
    let signed: Bool
}

private func integerTailSpecs(getters: Bool = false, truncating: Bool = false) -> [IntegerTailSpec] {
    let widths = truncating ? [(16, 8), (32, 16), (64, 32), (64, 8)] : [(8, 8), (16, 16), (32, 32)]
    return widths.flatMap { source, result in
        [false, true].map { signed in
            if getters {
                let type = (signed ? "Unsigned" : "Signed") + "\(source)Box"
                return IntegerTailSpec(function: type + ".view(", callee: type + ".produced.getter(", bits: result, signed: signed)
            }
            let name = (signed ? "signed" : "unsigned") + "\(result)"
                + (truncating ? "From\(source)" : "") + "Tail"
            return IntegerTailSpec(function: name + "(", callee: name + "Producer(", bits: result, signed: signed)
        }
    }
}

/// Batch all selected entries through each public pipeline. Selecting all starts
/// for analyzeEachFunction preserves complete helper context rather than testing
/// only an isolated target whose callees have been omitted.
private func integerTailStages(path: String, module: String, specs: [IntegerTailSpec]) async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    var found: [String: UInt64] = [:]
    for symbol in image.symbols where symbol.offset != 0 && symbol.name.hasPrefix("_$s") {
        let name = try await demangleAsNode(String(symbol.name.dropFirst())).print(using: .default)
        for spec in specs where name.hasPrefix(module + "." + spec.function) {
            try #require(found[spec.function] == nil)
            found[spec.function] = UInt64(symbol.offset)
        }
    }
    try #require(found.count == specs.count)
    let entries = found
    let addresses = Set(entries.values)
    let starts = Set(Disassembler().functionStarts(of: image))
    try #require(addresses.count == specs.count && addresses.isSubset(of: starts))
    var stages: [[DisassembledFunction]] = []
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: path)
            case 1: return await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: path, functionFilter: module + ".")
            case 3:
                let values: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                    machO: image, transform: { addresses.contains($0.startAddress) ? $0 : nil })
                return values.compactMap { $0 }
            default:
                return Array(await Disassembler().analyzeEachFunction(at: starts, in: image, transform: { $0 }).values)
            }
        }
        let selected = functions.filter { addresses.contains($0.startAddress) }
        try #require(Set(selected.map(\.startAddress)) == addresses && selected.count == specs.count)
        stages.append(try specs.map { spec in try #require(selected.first { $0.startAddress == entries[spec.function] }) })
    }
    return stages
}

private func expectConvertedIntegerTail(_ function: DisassembledFunction, spec: IntegerTailSpec, module: String, context: String) throws {
    let detail = Comment(rawValue: context + "\n" + function.renderStructured())
    let last = try #require(function.instructions.last)
    let value: String?
    if case .normal(let expression) = last.exit { value = expression } else { value = nil }
    #expect(value != nil && value != "?", detail)
    for text in [function.renderPseudo(), function.renderStructured()] {
        #expect(text.contains("return "), detail)
        #expect(!text.contains("return ?"), detail)
        #expect(text.components(separatedBy: module + "." + spec.callee).count == 2, detail)
        if spec.signed {
            #expect(text.contains("<< \(64 - spec.bits)") && text.contains(">>ˢ \(64 - spec.bits)"), detail)
        } else {
            let mask = spec.bits == 8 ? "255" : spec.bits == 16 ? "0xffff" : "0xffffffff"
            #expect(text.contains("& " + mask), detail)
        }
    }
}

@Test(arguments: ["Onone", "O", "Osize"])
func integerFunctionTailReturnsKeepTheirConvertedValueAcrossAllAPIsIfPresent(level: String) async throws {
    let image = try #require(integerTailImages.first { $0.module == "SwiftTailResults" && $0.level == level })
    guard FileManager.default.fileExists(atPath: image.path) else { return }
    let specs = integerTailSpecs()
    for (stage, functions) in try await integerTailStages(path: image.path, module: image.module, specs: specs).enumerated() {
        for (spec, function) in zip(specs, functions) {
            if level != "Onone" {
                #expect(function.instructions.count == 1 && function.instructions[0].controlFlow == .branch)
            }
            try expectConvertedIntegerTail(function, spec: spec, module: image.module, context: image.path + " API \(stage)")
        }
    }
}

@Test(arguments: ["Onone", "O", "Osize"])
func integerGetterTailReturnsKeepTheirConvertedValueAcrossAllAPIsIfPresent(level: String) async throws {
    let image = try #require(integerTailImages.first { $0.module == "SwiftTailGetters" && $0.level == level })
    guard FileManager.default.fileExists(atPath: image.path) else { return }
    let specs = integerTailSpecs(getters: true)
    for (stage, functions) in try await integerTailStages(path: image.path, module: image.module, specs: specs).enumerated() {
        for (spec, function) in zip(specs, functions) {
            if level != "Onone" {
                #expect(function.instructions.count == 1 && function.instructions[0].controlFlow == .branch)
            }
            try expectConvertedIntegerTail(function, spec: spec, module: image.module, context: image.path + " API \(stage)")
        }
    }
}

@Test(arguments: ["Onone", "O", "Osize"])
func integerOrdinaryCallTruncationControlsKeepTheirReturnAcrossAllAPIsIfPresent(level: String) async throws {
    let image = try #require(integerTailImages.first { $0.module == "SwiftTailResults" && $0.level == level })
    guard FileManager.default.fileExists(atPath: image.path) else { return }
    let specs = integerTailSpecs(truncating: true)
    for (stage, functions) in try await integerTailStages(path: image.path, module: image.module, specs: specs).enumerated() {
        for (spec, function) in zip(specs, functions) {
            #expect(function.instructions.last?.controlFlow == .return)
            try expectConvertedIntegerTail(function, spec: spec, module: image.module, context: image.path + " API \(stage)")
        }
    }
}

@Test func authoredIntegerTailConversionsAgreeWithTheirSourceIfPresent() throws {
    for image in integerTailImages {
        guard FileManager.default.fileExists(atPath: image.oracle) else { continue }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: image.oracle)
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: image.oracle + "\n" + output))
        let count = image.module == "SwiftTailResults" ? 714 : 568
        #expect(output.contains("PASS native tail conversions: \(count) observations"))
    }
}
