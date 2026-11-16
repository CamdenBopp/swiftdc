import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let contextResultFixtures = [
    "Fixtures/Sample/libContextResultUse.dylib",
    "Fixtures/Sample/libContextResultUse.opt.dylib",
    "Fixtures/Sample/libContextResultUse.size.dylib",
]

@Test func nativeContextSelfResultsHaveOneLifetimeIfPresent() throws {
    for path in contextResultFixtures where FileManager.default.fileExists(atPath: path) {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        for (name, expected) in [
            ("self_use_context_only_oracle", Int64(1234)),
            ("self_use_mixed_oracle", Int64(1234)),
            ("self_use_direct_oracle", Int64(134)),
            ("self_use_indirect_oracle", Int64(1234)),
        ] {
            let entry = try #require(dlsym(library, name))
            #expect(unsafeBitCast(entry, to: Entry.self)() == expected, "\(path): \(name)")
        }
    }
}

@Test func contextSelfUsesReuseTheOriginalEvaluationInEveryPipelineIfPresent() async throws {
    for path in contextResultFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let all = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "self_use_")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(all.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [listing, all, filtered, streamed, Array(each.values)] {
            for shape in ["context_only", "mixed", "direct", "indirect"] {
                let function = try #require(functions.first { $0.symbol == "_self_use_\(shape)_shape" })
                let factory = shape == "indirect" ? "SelfUse.makeSelfUseHolder()" : "SelfUse.makeSelfUseBox()"
                let producer = try #require(function.instructions.first { $0.callee?.hasPrefix(factory) == true })
                let use = try #require(function.instructions.first { $0.callee?.hasPrefix("SelfUse.SelfUseBox.use(") == true })
                #expect(use.callArguments == ["9"])
                // Bind even an adjacent context use: a later presentation
                // rewrite may hide its consumer, but not the factory's effect.
                let binding = try #require(producer.binding)
                #expect(binding.expression == factory)
                #expect(use.callSelf == binding.name + (shape == "indirect" ? ".box" : ""))
                if shape != "direct" {
                    let middle = try #require(function.instructions.first {
                        $0.callee?.hasPrefix(shape == "mixed" ? "SelfUse.takeSelfUseBox(" : "SelfUse.selfUseEffect(") == true
                    })
                    #expect(producer.address < middle.address && middle.address < use.address)
                    if shape == "mixed" { #expect(middle.callArguments == [binding.name]) }
                    for text in [function.renderPseudo(), function.renderStructured()] {
                        let definition = try #require(text.range(of: binding.statement))
                        let intervening = try #require(text.range(of: shape == "mixed" ? "SelfUse.takeSelfUseBox(" : "SelfUse.selfUseEffect("))
                        let consumption = try #require(text.range(of: "SelfUse.SelfUseBox.use("))
                        #expect(definition.lowerBound < intervening.lowerBound && intervening.lowerBound < consumption.lowerBound)
                    }
                }
                for text in [function.renderPseudo(), function.renderStructured()] {
                    #expect(text.components(separatedBy: factory).count == 2, Comment(rawValue: text))
                }
            }
        }
    }
}
