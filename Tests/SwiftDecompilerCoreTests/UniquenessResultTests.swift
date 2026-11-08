import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let uniquenessResultFixtures = [
    ("Fixtures/Sample/libUniquenessResult.Onone.dylib", "UniquenessResultOnone"),
    ("Fixtures/Sample/libUniquenessResult.O.dylib", "UniquenessResult"),
    ("Fixtures/Sample/libUniquenessResult.Osize.dylib", "UniquenessResultSize"),
]

@Test func uniquenessSnapshotsHaveIndependentNativeValueAndOrderOraclesIfPresent() throws {
    for (path, _) in uniquenessResultFixtures where FileManager.default.fileExists(atPath: path) {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        for (name, expected): (String, Int64) in [
            ("uniqueness_branch_oracle", 110), ("uniqueness_single_oracle", 100),
            ("uniqueness_shared_oracle", 0), ("uniqueness_immediate_oracle", 1),
        ] {
            let entry = unsafeBitCast(try #require(dlsym(library, name)), to: Entry.self)
            #expect(entry() == expected, Comment(rawValue: path + ": " + name))
        }
    }
}

@Test func aUniquenessSnapshotIsEvaluatedOnceAtItsOriginalCallInEveryPipelineIfPresent() async throws {
    for (path, module) in uniquenessResultFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: module)
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        // -Osize outlines the load and runtime tail branch. Select that
        // actual producer by its independently checked two-instruction body;
        // its existing generic binding is a control, not red proof for the
        // new runtime-predicate exception.
        func isQueryProducer(_ instruction: Instruction) -> Bool {
            guard instruction.controlFlow == .call, let name = instruction.callee else { return false }
            if name.contains("isKnownUniquelyReferenced") || DisassembledFunction.isUniquenessCheck(name) { return true }
            guard let target = instruction.branchTarget,
                  let wrapper = array.first(where: { $0.startAddress == target }),
                  wrapper.symbol.hasPrefix("_OUTLINED_FUNCTION_"), wrapper.instructions.count == 2,
                  let load = wrapper.instructions.first, let tail = wrapper.instructions.last,
                  String(load.text.filter { !$0.isWhitespace }) == "ldrx0,[x0]",
                  tail.controlFlow == .branch, let callee = tail.callee
            else { return false }
            return DisassembledFunction.isUniquenessCheck(callee)
        }
        for group in [listing, array, filtered, streamed, Array(each.values)] {
            for name in ["branchThenCapture", "captureThenConsume"] {
                let function = try #require(group.first { $0.displayName.hasPrefix(module + "." + name + "(") })
                let queries = function.instructions.filter(isQueryProducer)
                let query = try #require(queries.count == 1 ? queries.first : nil)
                let binding = try #require(query.binding)
                let capture = try #require(function.instructions.first { $0.callee?.hasPrefix(module + ".captureUniqueBox(") == true })
                let consumer = try #require(function.instructions.first { $0.callee?.hasPrefix(module + ".consumeUniqueSnapshot(") == true })
                #expect(query.address < capture.address && capture.address < consumer.address)
                let arguments = try #require(consumer.callArguments)
                #expect(arguments.count == 1)
                #expect(arguments.first?.contains(binding.name) == true)
                #expect(arguments.first?.contains("isKnownUniquelyReferenced") == false)
                for text in [function.renderPseudo(), function.renderStructured()] {
                    let definition = try #require(text.range(of: binding.statement))
                    let mutation = try #require(text.range(of: module + ".captureUniqueBox("))
                    let use = try #require(text.range(of: module + ".consumeUniqueSnapshot("))
                    #expect(definition.lowerBound < mutation.lowerBound && mutation.lowerBound < use.lowerBound)
                    #expect(text.components(separatedBy: binding.expression).count == 2, Comment(rawValue: text))
                }
            }
            // The sole immediate query remains an inline expression, with
            // no added evaluation or needless result binding.
            let immediate = try #require(group.first { $0.displayName.hasPrefix(module + ".immediateSnapshot(") })
            let query = try #require(immediate.instructions.first(where: isQueryProducer))
            #expect(query.binding == nil)
            let callee = try #require(query.callee)
            let token = callee.hasPrefix("OUTLINED_FUNCTION_") ? callee : "isKnownUniquelyReferenced"
            for text in [immediate.renderPseudo(), immediate.renderStructured()] {
                #expect(text.components(separatedBy: token).count == 2, Comment(rawValue: text))
            }
        }
    }
}
