import Foundation
import Testing
import Demangling
@_spi(Internals) import SwiftInspection
@testable import SwiftDecompilerCore

private let swiftNarrowImages = [
    (module: "SwiftArgumentBoundary", level: "Onone", path: "Fixtures/Sample/libSwiftArgumentBoundary.Onone.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentBoundary.Onone-oracle"),
    (module: "SwiftArgumentBoundary", level: "O", path: "Fixtures/Sample/libSwiftArgumentBoundary.O.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentBoundary.O-oracle"),
    (module: "SwiftArgumentBoundary", level: "Osize", path: "Fixtures/Sample/libSwiftArgumentBoundary.Osize.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentBoundary.Osize-oracle"),
    (module: "SwiftArgumentRoles", level: "Onone", path: "Fixtures/Sample/libSwiftArgumentRoles.Onone.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentRoles.Onone-oracle"),
    (module: "SwiftArgumentRoles", level: "O", path: "Fixtures/Sample/libSwiftArgumentRoles.O.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentRoles.O-oracle"),
    (module: "SwiftArgumentRoles", level: "Osize", path: "Fixtures/Sample/libSwiftArgumentRoles.Osize.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentRoles.Osize-oracle"),
    (module: "SwiftArgumentOpaque", level: "Onone", path: "Fixtures/Sample/libSwiftArgumentOpaque.Onone.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentOpaque.Onone-oracle"),
    (module: "SwiftArgumentOpaque", level: "O", path: "Fixtures/Sample/libSwiftArgumentOpaque.O.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentOpaque.O-oracle"),
    (module: "SwiftArgumentOpaque", level: "Osize", path: "Fixtures/Sample/libSwiftArgumentOpaque.Osize.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftArgumentOpaque.Osize-oracle"),
]

/// Select by independently demangled nlist entries, require every selected
/// start, and give analyzeEachFunction all starts so outlined helpers retain
/// their complete context. An empty API result cannot satisfy these checks.
private func swiftNarrowStages(path: String, module: String, names: [String]) async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    var entries: [String: UInt64] = [:]
    for symbol in image.symbols where symbol.offset != 0 && symbol.name.hasPrefix("_$s") {
        let name = try await demangleAsNode(String(symbol.name.dropFirst())).print(using: .default)
        for selected in names where name.hasPrefix(module + "." + selected + "(") {
            try #require(entries[selected] == nil)
            entries[selected] = UInt64(symbol.offset)
        }
    }
    try #require(entries.count == names.count)
    let selectedEntries = entries
    let addresses = Set(entries.values)
    let starts = Set(Disassembler().functionStarts(of: image))
    try #require(addresses.count == names.count && addresses.isSubset(of: starts))
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
            default: return Array(await Disassembler().analyzeEachFunction(at: starts, in: image, transform: { $0 }).values)
            }
        }
        let selected = functions.filter { addresses.contains($0.startAddress) }
        try #require(selected.count == names.count && Set(selected.map(\.startAddress)) == addresses)
        stages.append(try names.map { name in try #require(selected.first { $0.startAddress == selectedEntries[name] }) })
    }
    return stages
}

private func swiftNarrowView(_ atom: String, bits: Int, signed: Bool) -> String {
    if signed { return "((\(atom) << \(64 - bits)) >>ˢ \(64 - bits))" }
    let mask = bits == 8 ? "255" : bits == 16 ? "0xffff" : "0xffffffff"
    return "(\(atom) & \(mask))"
}

private func swiftNarrowCall(_ function: DisassembledFunction, consumer: String) throws -> Instruction {
    let sites = function.instructions.filter { $0.callee?.contains(consumer) == true && ($0.controlFlow == .call || $0.controlFlow == .branch) }
    try #require(sites.count == 1)
    return try #require(sites.first)
}

@Test(arguments: ["Onone", "O", "Osize"])
func swiftNarrowRegisterArgumentsUseTheFormalValueAcrossAllAPIsIfPresent(level: String) async throws {
    let image = try #require(swiftNarrowImages.first { $0.module == "SwiftArgumentBoundary" && $0.level == level })
    guard FileManager.default.fileExists(atPath: image.path) else { return }
    let specs = [8, 16, 32].flatMap { bits in
        [true, false].flatMap { signed in
            ["BitPattern", "Truncation", "Same", "NonTail", "CallResult"].map { shape in
                (stem: (signed ? "signed" : "unsigned") + "\(bits)" + shape, bits: bits, signed: signed, shape: shape)
            }
        }
    }
    for (stage, functions) in try await swiftNarrowStages(path: image.path, module: image.module, names: specs.map { $0.stem + "Caller" }).enumerated() {
        for (spec, function) in zip(specs, functions) {
            let site = try swiftNarrowCall(function, consumer: spec.stem + "Consumer(")
            let atom = spec.shape == "CallResult" ? image.module + "." + spec.stem + "Maker(arg0)" : "arg0"
            let expected = spec.shape == "Same" ? atom : swiftNarrowView(atom, bits: spec.bits, signed: spec.signed)
            #expect(site.callArguments == [expected], Comment(rawValue: image.path + " API \(stage)\n" + function.renderStructured()))
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains(spec.stem + "Consumer(" + expected + ")"), Comment(rawValue: text))
                if spec.shape == "CallResult" { #expect(text.components(separatedBy: spec.stem + "Maker(").count == 2) }
            }
        }
    }
}

@Test(arguments: ["Onone", "O", "Osize"])
func swiftNarrowArgumentRolesPreserveAddressesReceiversAndFPBanksIfPresent(level: String) async throws {
    let image = try #require(swiftNarrowImages.first { $0.module == "SwiftArgumentRoles" && $0.level == level })
    guard FileManager.default.fileExists(atPath: image.path) else { return }
    let specs = [8, 16, 32].flatMap { bits in
        [true, false].flatMap { signed in
            ["Stack", "Inout", "Setter", "Mixed"].map { role in
                (stem: (signed ? "signed" : "unsigned") + "\(bits)", bits: bits, signed: signed, role: role)
            }
        }
    }
    let names = specs.map { $0.stem + $0.role + "Caller" } + ["floatBitsInt32Caller", "floatBitsUInt8Caller"]
    for (stage, functions) in try await swiftNarrowStages(path: image.path, module: image.module, names: names).enumerated() {
        for (spec, function) in zip(specs, functions) {
            let consumer: String
            if spec.role == "Setter" { consumer = (spec.signed ? "Signed" : "Unsigned") + "\(spec.bits)Box.value.setter" }
            else { consumer = spec.stem + spec.role + (spec.role == "Inout" ? "Bump(" : "Consumer(") }
            let site = try swiftNarrowCall(function, consumer: consumer)
            let args = try #require(site.callArguments)
            let context = Comment(rawValue: image.path + " API \(stage)\n" + function.renderStructured())
            switch spec.role {
            case "Inout":
                #expect(args.count == 1 && args[0].hasPrefix("local_"), context)
                #expect(!args[0].contains("&") && !args[0].contains("<<"), context)
                // Existing memory-effect decline remains honest; no value seed.
                #expect(function.renderStructured().contains("return ?"), context)
            case "Stack":
                if level == "Osize", stage == 4 {
                    // This API already loses the outlined helper's physical
                    // inputs. A formal type must not invent their placement.
                    #expect(args == ["OUTLINED_FUNCTION_0(?, arg1)"] + Array(repeating: "?", count: 8), context)
                } else {
                    let prefix = ["arg1"] + (1..<8).map { "(arg1 + \($0))" }
                    #expect(args == prefix + [swiftNarrowView("arg0", bits: spec.bits, signed: spec.signed)], context)
                }
            case "Mixed":
                #expect(args == ["arg1", swiftNarrowView("arg0", bits: spec.bits, signed: spec.signed)], context)
            default:
                #expect(site.callSelf == "arg0", context)
                #expect(args == [swiftNarrowView("arg1", bits: spec.bits, signed: spec.signed)], context)
            }
        }
        for (name, function) in zip(["Int32", "UInt8"], functions.suffix(2)) {
            let site = try swiftNarrowCall(function, consumer: "floatBits" + name + "Consumer(")
            // Onone still lacks the getter receiver. Do not invent arg0 there.
            let atom = level == "Onone" ? "Swift.Float.bitPattern.getter()" : "arg0.bitPattern"
            let expected = swiftNarrowView(atom, bits: name == "Int32" ? 32 : 8, signed: name == "Int32")
            #expect(site.callArguments == [expected], Comment(rawValue: image.path + " API \(stage)\n" + function.renderStructured()))
        }
    }
}

@Test(arguments: ["Onone", "O", "Osize"])
func swiftNarrowUnknownProducerWidthsDeclineBeforeUseCollectionIfPresent(level: String) async throws {
    let image = try #require(swiftNarrowImages.first { $0.module == "SwiftArgumentOpaque" && $0.level == level })
    guard FileManager.default.fileExists(atPath: image.path) else { return }
    let stems = [8, 16, 32].flatMap { bits in ["signed", "unsigned"].map { $0 + "\(bits)Opaque" } }
    for (stage, functions) in try await swiftNarrowStages(path: image.path, module: image.module, names: stems.map { $0 + "Caller" }).enumerated() {
        for (stem, function) in zip(stems, functions) {
            let site = try swiftNarrowCall(function, consumer: stem + "Consumer(")
            let producer = try swiftNarrowCall(function, consumer: "argument_opaque_word")
            let context = Comment(rawValue: image.path + " API \(stage)\n" + function.renderStructured())
            #expect(site.callArguments == ["?"], context)
            #expect(!producer.resultConsumed, context)
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.components(separatedBy: "argument_opaque_word(").count == 2, context)
                let produced = text.range(of: "argument_opaque_word(")
                let consumed = text.range(of: stem + "Consumer(?)")
                #expect(produced != nil && consumed != nil, context)
                if let produced, let consumed { #expect(produced.lowerBound < consumed.lowerBound, context) }
            }
        }
    }
}

@Test func swiftNarrowArgumentNativeValuesAndProviderEffectsAgreeWithTheSourceIfPresent() throws {
    for image in swiftNarrowImages {
        guard FileManager.default.fileExists(atPath: image.oracle) else { continue }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: image.oracle)
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: image.oracle + "\n" + output))
        let summary: String
        switch image.module {
        case "SwiftArgumentBoundary": summary = "PASS native Swift argument views: 2427 observations"
        case "SwiftArgumentRoles": summary = "PASS native argument roles: 1740 observations"
        default: summary = "PASS native opaque argument producer: 48 observations"
        }
        #expect(output.split(separator: "\n").last == Substring(summary), Comment(rawValue: image.oracle))
    }
}

@Test func swiftNarrowOpaqueProviderIsOutsideTheAnalyzedImageIfPresent() throws {
    let providers = ["Fixtures/Sample/libArgumentOpaqueProvider.Onone.dylib",
                     "Fixtures/Sample/libArgumentOpaqueProvider.O.dylib",
                     "Fixtures/Sample/libArgumentOpaqueProvider.Osize.dylib"]
    for (fixture, provider) in zip(swiftNarrowImages.filter { $0.module == "SwiftArgumentOpaque" }, providers) {
        guard FileManager.default.fileExists(atPath: fixture.path), FileManager.default.fileExists(atPath: provider) else { continue }
        let image = try BinaryLoader.load(path: fixture.path)
        let symbol = try #require(image.symbols.first { $0.name == "_argument_opaque_word" })
        #expect(symbol.offset == 0)
        let description = try #require(symbol.nlist.symbolDescription)
        #expect(description.libraryOrdinalType == nil)
        let dependencies = Array(image.dependencies), index = Int(description.libraryOrdinal) - 1
        try #require(dependencies.indices.contains(index))
        #expect(dependencies[index].dylib.name == "@rpath/" + URL(fileURLWithPath: provider).lastPathComponent)
        let implementation = try BinaryLoader.load(path: provider)
        #expect(implementation.symbols.contains { $0.name == "_argument_opaque_word" && $0.offset != 0 })
    }
}
