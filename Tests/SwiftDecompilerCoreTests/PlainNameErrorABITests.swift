import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private struct PlainErrorLevel: Sendable {
    let name: String
    let caller: String
    let strippedCaller: String
    let system: String
    let strippedSystem: String
    let provider: String
    let native: String
    let callerIR: String
    let providerIR: String
}

private let plainErrorLevels = [
    PlainErrorLevel(name: "Onone",
        caller: "Fixtures/Sample/libPlainErrorABI.Onone.dylib",
        strippedCaller: "Fixtures/Sample/libPlainErrorABI.Onone.stripped.dylib",
        system: "Fixtures/Sample/libPlainErrorSystem.Onone.dylib",
        strippedSystem: "Fixtures/Sample/libPlainErrorSystem.Onone.stripped.dylib",
        provider: "Fixtures/Sample/libPlainErrorProvider.Onone.dylib",
        native: "Fixtures/Sample/plain-error-abi-Onone-oracle",
        callerIR: "Fixtures/Sample/plain-error-abi-Onone-caller.ll",
        providerIR: "Fixtures/Sample/plain-error-abi-Onone-provider.ll"),
    PlainErrorLevel(name: "O",
        caller: "Fixtures/Sample/libPlainErrorABI.O.dylib",
        strippedCaller: "Fixtures/Sample/libPlainErrorABI.O.stripped.dylib",
        system: "Fixtures/Sample/libPlainErrorSystem.O.dylib",
        strippedSystem: "Fixtures/Sample/libPlainErrorSystem.O.stripped.dylib",
        provider: "Fixtures/Sample/libPlainErrorProvider.O.dylib",
        native: "Fixtures/Sample/plain-error-abi-O-oracle",
        callerIR: "Fixtures/Sample/plain-error-abi-O-caller.ll",
        providerIR: "Fixtures/Sample/plain-error-abi-O-provider.ll"),
    PlainErrorLevel(name: "Osize",
        caller: "Fixtures/Sample/libPlainErrorABI.Osize.dylib",
        strippedCaller: "Fixtures/Sample/libPlainErrorABI.Osize.stripped.dylib",
        system: "Fixtures/Sample/libPlainErrorSystem.Osize.dylib",
        strippedSystem: "Fixtures/Sample/libPlainErrorSystem.Osize.stripped.dylib",
        provider: "Fixtures/Sample/libPlainErrorProvider.Osize.dylib",
        native: "Fixtures/Sample/plain-error-abi-Osize-oracle",
        callerIR: "Fixtures/Sample/plain-error-abi-Osize-caller.ll",
        providerIR: "Fixtures/Sample/plain-error-abi-Osize-provider.ll"),
]

private func requirePlainErrorImport(_ symbol: String, provider: String, image: MachOFile) throws {
    let imported = try #require(image.symbols.first { $0.name == symbol && $0.offset == 0 })
    let description = try #require(imported.nlist.symbolDescription)
    #expect(image.header.flags.contains(.twolevel))
    #expect(!image.header.flags.contains(.force_flat))
    #expect(description.libraryOrdinalType == nil)
    let libraries = Array(image.dependencies)
    let index = Int(description.libraryOrdinal) - 1
    try #require(libraries.indices.contains(index))
    #expect(libraries[index].dylib.name == provider)
}

/// Exact caller entries come from independent Mach-O symbols, including in
/// locally stripped images. No preliminary SUT render chooses the entries.
private func plainErrorStages(
    path: String, image: MachOFile, entry: UInt64, filter: String
) async throws -> [[DisassembledFunction]] {
    var stages: [[DisassembledFunction]] = []
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: path)
            case 1: return await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: path, functionFilter: filter)
            case 3:
                let selected: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                    machO: image, transform: { $0.startAddress == entry ? $0 : nil })
                return selected.compactMap { $0 }
            default:
                let selected = await Disassembler().analyzeEachFunction(at: [entry], in: image, transform: { $0 })
                return Array(selected.values)
            }
        }
        stages.append(functions)
    }
    return stages
}

private func requirePlainErrorPaths(symbol: String, imported: String) async throws {
    for level in plainErrorLevels {
        for path in [level.caller, level.strippedCaller] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            try requirePlainErrorImport(imported, provider: "@rpath/libPlainErrorProvider.\(level.name).dylib", image: image)
            let entry = UInt64(try #require(image.symbols.first { $0.name == symbol }).offset)
            for functions in try await plainErrorStages(path: path, image: image, entry: entry, filter: "catch") {
                let function = try #require(functions.first { $0.startAddress == entry })
                let structured = function.renderStructured()
                #expect(structured.contains("error != nil") || structured.contains("error == nil"),
                        Comment(rawValue: path + "\n" + structured))
                for text in [structured, function.renderPseudo()] {
                    let context = Comment(rawValue: path + "\n" + text)
                    #expect(!text.contains("(0 == 0)") && !text.contains("(0 != 0)"), context)
                    #expect(!text.contains("swift_errorRelease(0)"), context)
                }
            }
        }
    }
}

@Test func plainNamedSwiftImportsKeepTheirErrorPathsAcrossAllAPIsIfPresent() async throws {
    // The mangler substitutes Plain from the module name in catchPlainProbe.
    try await requirePlainErrorPaths(symbol: "_$s13PlainErrorABI05catchA5ProbeyS2iF", imported: "_plain_error_raise")
}

@Test func catalogNamedSwiftImportsKeepTheirErrorPathsAcrossAllAPIsIfPresent() async throws {
    try await requirePlainErrorPaths(symbol: "_$s13PlainErrorABI17catchCatalogProbeyS2iF", imported: "_getpid")
}

@Test func systemCImportsKeepTheirNonThrowingControlAcrossAllAPIsIfPresent() async throws {
    for level in plainErrorLevels {
        for path in [level.system, level.strippedSystem] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            try requirePlainErrorImport("_getpid", provider: "/usr/lib/libSystem.B.dylib", image: image)
            for symbol in ["_system_error_arm", "_system_error_indirect_arm"] {
                let entry = UInt64(try #require(image.symbols.first { $0.name == symbol }).offset)
                for functions in try await plainErrorStages(path: path, image: image, entry: entry, filter: "system_error") {
                    let function = try #require(functions.first { $0.startAddress == entry })
                    let exit = try #require(function.instructions.last { $0.controlFlow == .return })
                    #expect(ValueTracer().analyze(function).exitValues[exit.address] == .immediate(1))
                    for text in [function.renderStructured(), function.renderPseudo()] {
                        // Without callers, an unnamed body's source result
                        // type can be unknown while physical x0 still proves one.
                        #expect(text.contains("return 1") || text.contains("return // x0 = 1"),
                                Comment(rawValue: path + "\n" + text))
                    }
                }
            }
        }
    }
}

private func requireUnprovedForwarderExits(symbol: String) async throws {
    for level in plainErrorLevels {
        for path in [level.caller, level.strippedCaller] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            let entry = UInt64(try #require(image.symbols.first { $0.name == symbol }).offset)
            for functions in try await plainErrorStages(path: path, image: image, entry: entry, filter: "forward") {
                let function = try #require(functions.first { $0.startAddress == entry })
                for text in [function.renderStructured(), function.renderPseudo()] {
                    // Onone also has a guarded normal return; its error edge
                    // still cannot be labelled a normal source return.
                    #expect(text.contains("machine_return()"), Comment(rawValue: path + "\n" + text))
                }
            }
        }
    }
}

@Test func plainNamedSwiftForwardersDoNotProveNormalErrorExitsIfPresent() async throws {
    try await requireUnprovedForwarderExits(symbol: "_$s13PlainErrorABI07forwardA5ProbeyS2iKF")
}

@Test func catalogNamedSwiftForwardersDoNotProveNormalErrorExitsIfPresent() async throws {
    try await requireUnprovedForwarderExits(symbol: "_$s13PlainErrorABI19forwardCatalogProbeyS2iKF")
}

@Test func systemCImportsStillProveNormalSwiftExitsIfPresent() async throws {
    for level in plainErrorLevels {
        for path in [level.system, level.strippedSystem] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            let entry = UInt64(try #require(image.symbols.first { $0.name == "_$s16PlainErrorSystem05typedC5ProbeSiyKF" }).offset)
            for functions in try await plainErrorStages(path: path, image: image, entry: entry, filter: "typedSystem") {
                let function = try #require(functions.first { $0.startAddress == entry })
                for text in [function.renderStructured(), function.renderPseudo()] {
                    #expect(text.contains("return ") && !text.contains("machine_return()"),
                            Comment(rawValue: path + "\n" + text))
                }
            }
        }
    }
}

@Test func nativePlainNamedErrorsAndSystemCControlsAgreeAtAllLevelsIfPresent() throws {
    for level in plainErrorLevels {
        guard FileManager.default.fileExists(atPath: level.native) else { continue }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: level.native)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, Comment(rawValue: text))
        #expect(text.contains("PASS 114 native plain-name Swift error and system C observations"), Comment(rawValue: text))
        let providerIR = try String(contentsOfFile: level.providerIR, encoding: .utf8)
        let callerIR = try String(contentsOfFile: level.callerIR, encoding: .utf8)
        for symbol in ["@plain_error_raise(", "@getpid("] {
            let definitions = providerIR.split(separator: "\n").filter { $0.hasPrefix("define ") && $0.contains(symbol) }
            let declarations = callerIR.split(separator: "\n").filter { $0.hasPrefix("declare ") && $0.contains(symbol) }
            let calls = callerIR.split(separator: "\n").filter { $0.contains("call swiftcc") && $0.contains(symbol) }
            #expect(definitions.count == 1 && declarations.count == 1 && calls.count == 2)
            for line in definitions + declarations + calls {
                #expect(line.contains("swiftcc") && line.contains("swifterror"), Comment(rawValue: String(line)))
            }
        }
        #expect(FileManager.default.fileExists(atPath: level.provider))
    }
}

@Test func localBodyErrorControlsKeepDirectAndIndirectProofsAcrossAllAPIsIfPresent() async throws {
    for level in plainErrorLevels {
        for path in [level.system, level.strippedSystem] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            for symbol in ["_system_error_body_direct_arm", "_system_error_body_indirect_arm"] {
                let entry = UInt64(try #require(image.symbols.first { $0.name == symbol }).offset)
                for functions in try await plainErrorStages(path: path, image: image, entry: entry, filter: String(symbol.dropFirst())) {
                    let function = try #require(functions.first { $0.startAddress == entry })
                    let call = try #require(function.instructions.first { $0.controlFlow == .call })
                    #expect(call.facts.bodyPreservesSwiftError)
                    #expect(!call.facts.nonThrowingABIContract)
                    let exit = try #require(function.instructions.last { $0.controlFlow == .return })
                    #expect(ValueTracer().analyze(function).exitValues[exit.address] == .immediate(1))
                    for text in [function.renderStructured(), function.renderPseudo()] {
                        #expect(text.contains("return 1") || text.contains("return // x0 = 1"), Comment(rawValue: text))
                    }
                }
            }
        }
    }
}

@Test func returnTransfersDoNotDonateBodyErrorProofsAcrossAllAPIsIfPresent() async throws {
    for level in plainErrorLevels {
        for path in [level.system, level.strippedSystem] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            for (symbol, preserves) in [
                ("_system_error_return_control", false),
                ("_system_error_return_lr_control", false),
                ("_system_error_return_register_control", false),
                ("_system_error_return_fallthrough_control", false),
                ("_system_error_return_deep_control", false),
                ("_system_error_return_fp_alias_control", false),
                ("_system_error_return_gp_alias_control", false),
                ("_system_error_return_alias_control", true),
                ("_system_error_return_register_good_control", true),
                ("_system_error_return_auth_control", true),
            ] {
                let entry = UInt64(try #require(image.symbols.first { $0.name == symbol }).offset)
                for functions in try await plainErrorStages(path: path, image: image, entry: entry, filter: String(symbol.dropFirst())) {
                    let function = try #require(functions.first { $0.startAddress == entry })
                    let call = try #require(function.instructions.first { $0.controlFlow == .call })
                    #expect(call.facts.bodyPreservesSwiftError == preserves, Comment(rawValue: path + " " + symbol))
                    #expect(!call.facts.nonThrowingABIContract)
                    let exit = try #require(function.instructions.last { $0.controlFlow == .return })
                    let result = ValueTracer().analyze(function).exitValues[exit.address]
                    if preserves { #expect(result == .immediate(1), Comment(rawValue: path + " " + symbol)) }
                    else { #expect(result != .immediate(1), Comment(rawValue: path + " " + symbol)) }
                    for text in [function.renderStructured(), function.renderPseudo()] {
                        let constant = text.contains("return 1") || text.contains("return // x0 = 1")
                        #expect(constant == preserves, Comment(rawValue: path + " " + symbol + "\n" + text))
                    }
                }
            }
        }
    }
}

@Test func strictBodyErrorProofsRetainValidIntermediateHelpersAcrossAllAPIsIfPresent() async throws {
    for level in plainErrorLevels {
        for path in [level.system, level.strippedSystem] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            let entry = UInt64(try #require(image.symbols.first { $0.name == "_system_error_return_deep_dispatch" }).offset)
            for functions in try await plainErrorStages(path: path, image: image, entry: entry,
                                                       filter: "system_error_return_deep_dispatch") {
                let function = try #require(functions.first { $0.startAddress == entry })
                let call = try #require(function.instructions.first { $0.controlFlow == .call })
                // The middle helper clobbers x19 through its callee but
                // returns through its own intact LR and never changes x21.
                #expect(call.facts.bodyPreservesSwiftError, Comment(rawValue: path))
                #expect(!call.facts.nonThrowingABIContract)
            }
        }
    }
}

@Test func swiftErrorIndirectBodyProofDoesNotReplaceSelectedInputContractsIfPresent() async throws {
    let path = "Fixtures/Sample/libStaticWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let entry = UInt64(try #require(image.symbols.first { $0.name == "_callThroughWitness" }).offset)
    let stages = try await plainErrorStages(path: path, image: image, entry: entry, filter: "callThroughWitness")
    // These two APIs previously decoded the requested function and its
    // direct dependencies. The extra fixed target qualifies x21 only.
    for index in [2, 4] {
        let function = try #require(stages[index].first { $0.startAddress == entry })
        let call = try #require(function.instructions.first { $0.controlFlow == .call })
        #expect(call.facts.bodyPreservesSwiftError)
        #expect(function.renderPseudo().contains("slot5(?, ?, 0x4038)"))
    }
}
