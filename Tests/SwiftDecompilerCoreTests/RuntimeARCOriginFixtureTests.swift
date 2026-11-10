import Foundation
import Testing
@testable import SwiftDecompilerCore

private let arcOriginFixtureCases: [(path: String, name: String, local: Bool)] = [
    ("Fixtures/Sample/libArcOriginLocal.Onone.dylib", "arcOriginLocalProbe", true),
    ("Fixtures/Sample/libArcOriginLocal.O.dylib", "arcOriginLocalProbe", true),
    ("Fixtures/Sample/libArcOriginLocal.Osize.dylib", "arcOriginLocalProbe", true),
    ("Fixtures/Sample/libArcOriginImport.Onone.dylib", "arcOriginImportProbe", false),
    ("Fixtures/Sample/libArcOriginImport.O.dylib", "arcOriginImportProbe", false),
    ("Fixtures/Sample/libArcOriginImport.Osize.dylib", "arcOriginImportProbe", false),
]

/// Every false provider lives only in its own child, after the generated ABI
/// proof and the linked two-level origin have been checked before dlopen.
@Test func localAndForeignARCTwinsHaveIndependentScalarNativeOraclesIfPresent() throws {
    for item in arcOriginFixtureCases where FileManager.default.fileExists(atPath: item.path) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "Fixtures/Sample/native-arc-origin.py", "--library", item.path]
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
        #expect(result["actual"] as? Int == 116)
        #expect(result["passed"] as? Bool == true)
    }
}

@Test func localAndForeignARCTwinsKeepOpaqueCallsInEveryPipelineIfPresent() async throws {
    for item in arcOriginFixtureCases where FileManager.default.fileExists(atPath: item.path) {
        let image = try BinaryLoader.load(path: item.path)
        let full = try await withStableDependencies { try await Disassembler().disassemble(path: item.path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: item.path, functionFilter: item.name)
        }
        let stream = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [full, array, filtered, stream, Array(each.values)] {
            let function = try #require(functions.first { $0.displayName.contains("." + item.name + "(") })
            let calls = function.instructions.filter {
                DisassembledFunction.calleeName(of: $0) == "swift_nonatomic_retain"
            }
            let call = try #require(calls.count == 1 ? calls.first : nil)
            #expect(!call.facts.arcIdentityContract)
            if item.local {
                #expect(call.callArguments?.count == 2)
                #expect(call.callArguments?.last == "arg1")
            } else {
                #expect(call.callArguments == ["…"])
            }
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(!text.contains("return arg0"), Comment(rawValue: text))
                #expect(text.components(separatedBy: "swift_nonatomic_retain(").count == 2, Comment(rawValue: text))
            }
        }
    }
}

/// The scalar provider's native result116 depends on both arguments. Its
/// runtime-looking name is no unary ABI evidence. The genuine bridge retain
/// has the compiler-verified one-pointer ABI exercised by the object controls.
@Test func sharedArityPolicyUsesTheActualImportedRuntimeProviderIfPresent() async throws {
    var cases: [(path: String, callee: String, expected: Int?)] = arcOriginFixtureCases
        .filter { !$0.local }.map { ($0.path, "swift_nonatomic_retain", nil) }
    cases += [
        ("Fixtures/Sample/libResultIdentity.Onone.dylib", "swift_bridgeObjectRetain", 1),
        ("Fixtures/Sample/libResultIdentity.dylib", "swift_bridgeObjectRetain", 1),
        ("Fixtures/Sample/libResultIdentity.size.dylib", "swift_bridgeObjectRetain", 1),
    ]
    for item in cases where FileManager.default.fileExists(atPath: item.path) {
        let image = try BinaryLoader.load(path: item.path)
        let disassembler = Disassembler()
        let functions = try await withStableDependencies { try await disassembler.disassemble(path: item.path) }
        let candidate = functions.lazy.flatMap(\.instructions).first {
            DisassembledFunction.calleeName(of: $0) == item.callee && $0.branchTarget != nil
        }
        let call = try #require(candidate)
        let target = try #require(call.branchTarget)
        let imported = image.symbols.first { $0.name == "_" + item.callee }
        let symbol = try #require(imported)
        let description = try #require(symbol.nlist.symbolDescription)
        let ordinal = Int(description.libraryOrdinal)
        try #require(ordinal > 0 && ordinal <= image.dependencies.count)
        let reference = RuntimeFunctionReference(rawSymbol: symbol.name,
            libraryName: image.dependencies[ordinal - 1].dylib.name)
        let starts = Set(disassembler.functionStarts(of: image))
        try #require(!starts.contains(target))
        let actual = disassembler.knownArity(ofCallTarget: target, names: [target: item.callee],
            cacheSymbols: nil, arcFunctions: [target: reference], isFunction: { starts.contains($0) })
        #expect(actual == item.expected, Comment(rawValue: item.path))
    }
}
