import Foundation
import Testing
@testable import SwiftDecompilerCore

private let resultIdentityFixtures = [
    ("Fixtures/Sample/libResultIdentity.dylib", "ResultIdentity"),
    ("Fixtures/Sample/libResultIdentity.Onone.dylib", "ResultIdentityOnone"),
    ("Fixtures/Sample/libResultIdentity.size.dylib", "ResultIdentitySize"),
    ("Fixtures/Sample/libResultIdentity.legacy.dylib", "ResultIdentityLegacy"),
    ("Fixtures/Sample/libResultIdentity.Onone.legacy.dylib", "ResultIdentityOnoneLegacy"),
    ("Fixtures/Sample/libResultIdentity.size.legacy.dylib", "ResultIdentitySizeLegacy"),
    ("Fixtures/Sample/libResultIdentity.indirect.dylib", "ResultIdentityIndirect"),
    ("Fixtures/Sample/libResultIdentity.Onone.indirect.dylib", "ResultIdentityOnoneIndirect"),
    ("Fixtures/Sample/libResultIdentity.size.indirect.dylib", "ResultIdentitySizeIndirect"),
    ("Fixtures/Sample/libResultIdentity.legacy.indirect.dylib", "ResultIdentityLegacyIndirect"),
    ("Fixtures/Sample/libResultIdentity.Onone.legacy.indirect.dylib", "ResultIdentityOnoneLegacyIndirect"),
    ("Fixtures/Sample/libResultIdentity.size.legacy.indirect.dylib", "ResultIdentitySizeLegacyIndirect"),
]

private func availableResultIdentityFixtures() throws -> [(String, String)] {
    let available = resultIdentityFixtures.filter { FileManager.default.fileExists(atPath: $0.0) }
    if ProcessInfo.processInfo.environment["SWIFTDC_REQUIRE_FIXTURES"] == "1" {
        try #require(available.count == resultIdentityFixtures.count)
    }
    return available
}

/// The child validates the fresh compiler ABI sidecar, file hash and linked
/// runtime provider before loading any object. Each lifetime starts in a new
/// process, including the immediate-return control whose pointer is released.
@Test func runtimeResultIdentityHasANativeOracleIfPresent() throws {
    for (path, _) in try availableResultIdentityFixtures() {
        for name in ["run", "twice", "immediate"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "Fixtures/Sample/native-result-identity.py", "--library", path, "--case", name]
            var environment = ProcessInfo.processInfo.environment
            for key in ["DYLD_INSERT_LIBRARIES", "DYLD_FORCE_FLAT_NAMESPACE", "DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH",
                        "DYLD_VERSIONED_LIBRARY_PATH", "DYLD_VERSIONED_FRAMEWORK_PATH", "LD_PRELOAD"] {
                environment.removeValue(forKey: key)
            }
            process.environment = environment
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
            try #require(process.terminationStatus == 0, Comment(rawValue: String(decoding: diagnostic, as: UTF8.self)))
            let decoded = try JSONSerialization.jsonObject(with: data)
            let result = try #require(decoded as? [String: Any])
            #expect(result["value"] as? Int == 7)
            #expect(result["constructions"] as? Int == 1)
            #expect(result["destructions"] as? Int == 1)
            #expect(result["passed"] as? Bool == true)
        }
    }
}

@Test func retainedResultsAreNotReevaluatedInAnyPipelineIfPresent() async throws {
    for (path, module) in try availableResultIdentityFixtures() {
        let image = try BinaryLoader.load(path: path)
        let full = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: module + ".")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [full, array, filtered, streamed, Array(each.values)] {
            for name in ["run", "twice"] {
                let function = try #require(functions.first { $0.displayName.hasPrefix(module + "." + name + "(") })
                let retains = function.instructions.filter { DisassembledFunction.calleeName(of: $0) == "swift_bridgeObjectRetain" }
                #expect(retains.count == (name == "run" ? 1 : 2))
                let haveRuntimeProof = retains.allSatisfy { $0.facts.arcIdentityContract }
                #expect(haveRuntimeProof)
                if path.contains(".indirect.") {
                    let areIndirectCalls = retains.allSatisfy { $0.controlFlow == .call && $0.branchTarget == nil }
                    #expect(areIndirectCalls)
                }
                for text in [function.renderPseudo(), function.renderStructured()] {
                    #expect(text.components(separatedBy: "result_identity_make(").count == 2, Comment(rawValue: text))
                    #expect(text.range(of: #"result_identity_sink\(r[0-9]+\)"#, options: .regularExpression) != nil,
                            Comment(rawValue: text))
                }
            }
            let immediate = try #require(functions.first { $0.displayName.hasPrefix(module + ".immediate(") })
            for text in [immediate.renderPseudo(), immediate.renderStructured()] {
                #expect(text.contains("return result_identity_make()"), Comment(rawValue: text))
                #expect(!text.contains("let r"), Comment(rawValue: text))
            }
        }
    }
}
