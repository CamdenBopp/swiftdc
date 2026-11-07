import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let uniquenessFactoryFixtures = [
    ("Fixtures/Sample/libFactorySnapshot.Onone.dylib", "FactorySnapshotOnone"),
    ("Fixtures/Sample/libFactorySnapshot.O.dylib", "FactorySnapshot"),
    ("Fixtures/Sample/libFactorySnapshot.Osize.dylib", "FactorySnapshotSize"),
]

@Test func uniquenessObjectProducersHaveNativeCountAndOrderOraclesIfPresent() throws {
    for (path, _) in uniquenessFactoryFixtures where FileManager.default.fileExists(atPath: path) {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        typealias Action = @convention(c) () -> Void
        func counter(_ name: String) throws -> Entry {
            unsafeBitCast(try #require(dlsym(library, name)), to: Entry.self)
        }
        let reset = unsafeBitCast(try #require(dlsym(library, "query_factory_reset")), to: Action.self)
        let cleanup = unsafeBitCast(try #require(dlsym(library, "query_factory_destroy_last")), to: Action.self)
        let creations = try counter("query_factory_creation_count")
        let marks = try counter("query_factory_mark_count")
        let creationsAtMark = try counter("query_factory_creations_at_mark")
        for (name, expected): (String, [Int64]) in [
            ("immediate", [1, 1, 0, 0]), ("shallow", [2, 1, 1, 1]),
            ("deep", [29, 1, 1, 1]), ("operand_delayed", [1, 1, 1, 1]),
            ("deep_without_mark", [29, 1, 0, 0]), ("unused_query", [73, 1, 0, 0]),
        ] {
            reset()
            defer { cleanup() }
            let entry = try counter("query_factory_" + name + "_oracle")
            #expect([entry(), creations(), marks(), creationsAtMark()] == expected,
                    Comment(rawValue: path + ": " + name))
        }
    }
}

@Test func uniquenessObjectProducersKeepOneEvaluationBeforeEffectsInEveryPipelineIfPresent() async throws {
    for (path, module) in uniquenessFactoryFixtures where FileManager.default.fileExists(atPath: path) {
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
        for group in [listing, array, filtered, streamed, Array(each.values)] {
            for name in ["immediateWrapper", "shallowWrapper", "deepWrapper", "operandDelayedWrapper",
                         "deepWithoutMarkWrapper", "unusedQueryWrapper"] {
                let function = try #require(group.first { $0.displayName.hasPrefix(module + "." + name + "(") })
                let factories = function.instructions.filter { $0.callee?.hasPrefix(module + ".createFactoryObject(") == true }
                let factory = try #require(factories.count == 1 ? factories.first : nil)
                let producer = try #require(factory.binding)
                let queries = function.instructions.filter {
                    $0.controlFlow == .call && $0.callee.map(DisassembledFunction.isUniquenessCheck) == true
                }
                let query = try #require(queries.count == 1 ? queries.first : nil)
                #expect(factory.address < query.address)
                #expect(query.callArguments?.first == producer.name)
                let mark = function.instructions.first { $0.callee == "query_factory_mark" || $0.callee == "_query_factory_mark" }
                if name == "shallowWrapper" || name == "deepWrapper" {
                    let mark = try #require(mark)
                    let snapshot = try #require(query.binding)
                    #expect(query.address < mark.address)
                    #expect(snapshot.expression.contains(producer.name))
                    let consumer = try #require(function.instructions.first {
                        $0.callee?.hasPrefix(module + ".factoryLayer1(") == true
                    })
                    #expect(consumer.callArguments?.first?.contains(snapshot.name) == true)
                    #expect(consumer.callArguments?.first?.contains("isKnownUniquelyReferenced") == false)
                } else if name == "operandDelayedWrapper" {
                    let mark = try #require(mark)
                    #expect(factory.address < mark.address && mark.address < query.address)
                } else {
                    #expect(mark == nil)
                    #expect(query.binding == nil)
                }
                for text in [function.renderPseudo(), function.renderStructured()] {
                    // Even a query hidden by the depth limit, or with no use,
                    // must leave its factory's observable evaluation intact.
                    #expect(text.components(separatedBy: module + ".createFactoryObject(").count == 2,
                            Comment(rawValue: text))
                    let definition = try #require(text.range(of: producer.statement))
                    if let mark {
                        let effect = try #require(text.range(of: "query_factory_mark("))
                        #expect(definition.lowerBound < effect.lowerBound)
                        if name != "operandDelayedWrapper" {
                            let snapshot = try #require(query.binding)
                            let evaluation = try #require(text.range(of: snapshot.statement))
                            #expect(evaluation.lowerBound < effect.lowerBound)
                            #expect(text.components(separatedBy: snapshot.expression).count == 2,
                                    Comment(rawValue: text))
                        }
                    }
                }
            }
        }
    }
}
