import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The symbol table and the loader binding are independently editable evidence.
/// A conflicting, weak or interior target must keep an opaque call. Edited
/// images are only disassembled; they are never loaded or called natively.
@Test func arcStubsRequireAgreementWithTheirActualLoaderBindingIfPresent() async throws {
    let fixtures = [("libResultIdentity.dylib", "ResultIdentity"),
                    ("libResultIdentity.Onone.dylib", "ResultIdentityOnone"),
                    ("libResultIdentity.size.dylib", "ResultIdentitySize"),
                    ("libResultIdentity.legacy.dylib", "ResultIdentityLegacy"),
                    ("libResultIdentity.Onone.legacy.dylib", "ResultIdentityOnoneLegacy"),
                    ("libResultIdentity.size.legacy.dylib", "ResultIdentitySizeLegacy")]
    let commonKinds = ["provider-mismatch", "pointer-addend", "weak-import", "weak-bind-only",
                       "weak-nlist-only", "weak-dylib", "other-symbol", "nlist-mismatch", "flat-namespace",
                       "self-ordinal", "flat-lookup", "weak-lookup", "stub-non-jump",
                       "non-twolevel", "force-flat", "weak-use-flags", "ref-to-weak-nlist", "other-identity-symbol"]
    for (file, module) in fixtures {
        let original = "Fixtures/Sample/" + file
        guard FileManager.default.fileExists(atPath: original) else { continue }
        let reference = try await withStableDependencies {
            try await Disassembler().disassemble(path: original, functionFilter: module + ".run(")
        }
        let originalRun = try #require(reference.first { $0.displayName.hasPrefix(module + ".run(") })
        let calls = originalRun.instructions.filter { DisassembledFunction.calleeName(of: $0) == "swift_bridgeObjectRetain" }
        let site = try #require(calls.count == 1 ? calls.first?.address : nil)
        let kinds = commonKinds + (file.contains(".legacy.")
            ? ["normal-after-done", "missing-binding", "lazy-helper-mismatch"] : ["import-addend"])
        for kind in kinds {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent(file).path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "Fixtures/Sample/mutate-result-identity.py",
                                 "--library", original, "--output", path, "--kind", kind]
            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
            try #require(process.terminationStatus == 0, Comment(rawValue: String(decoding: diagnostic, as: UTF8.self)))
            let image = try BinaryLoader.load(path: path)
            if kind == "weak-use-flags" {
                let dependency = image.dependencies[2]
                #expect(dependency.dylib.name == "/usr/lib/swift/libswiftCore.dylib")
                #expect(dependency.useFlags.contains(.weak_link))
            }
            if kind == "non-twolevel" {
                #expect(!image.header.flags.contains(.twolevel))
                #expect(!image.header.flags.contains(.force_flat))
            }
            if kind == "force-flat" {
                #expect(image.header.flags.contains(.twolevel))
                #expect(image.header.flags.contains(.force_flat))
            }
            if kind == "ref-to-weak-nlist" {
                let symbol = image.symbols.first { $0.name == "_swift_bridgeObjectRetain" }
                let description = try #require(symbol?.nlist.symbolDescription)
                #expect(description.libraryOrdinal == 3)
                #expect(description.contains(.ref_to_weak))
                #expect(!description.contains(.weak_ref))
            }
            let full = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
            let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
            let filtered = try await withStableDependencies {
                try await Disassembler().disassemble(path: path, functionFilter: module + ".run(")
            }
            let stream = await withStableDependencies {
                await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
            }
            let each = await withStableDependencies {
                await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
            }
            for functions in [full, array, filtered, stream, Array(each.values)] {
                let run = try #require(functions.first { $0.displayName.hasPrefix(module + ".run(") })
                let call = try #require(run.instructions.first { $0.address == site })
                #expect(!call.facts.arcIdentityContract, Comment(rawValue: module + " " + kind))
            }
        }
    }
}
