import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let resilientOperatorFixtures = [
    ("Fixtures/Sample/libResilientOperator.Onone.dylib", "ResilientOpOnone"),
    ("Fixtures/Sample/libResilientOperator.O.dylib", "ResilientOp"),
    ("Fixtures/Sample/libResilientOperator.Osize.dylib", "ResilientOpSize"),
]

@Test func resilientOperatorArgumentsHaveCompilerAndNativeABIOraclesIfPresent() throws {
    for (path, module) in resilientOperatorFixtures where FileManager.default.fileExists(atPath: path) {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        let symbol = "$s\(module.count)\(module)12mixedWrapperSiyF"
        typealias Entry = @convention(c) () -> Int64
        let entry = unsafeBitCast(try #require(dlsym(library, symbol)), to: Entry.self)
        #expect(entry() == 139, Comment(rawValue: path))
    }
}

@Test func storageLayoutDoesNotPlaceResilientOperatorOperandsInAnyPipelineIfPresent() async throws {
    for (path, module) in resilientOperatorFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "mixedWrapper")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for group in [listing, array, filtered, streamed, Array(each.values)] {
            let function = try #require(group.first { $0.displayName.hasPrefix(module + ".mixedWrapper(") })
            let call = try #require(function.instructions.first { $0.callee?.contains(".+ infix(") == true })
            #expect(call.callArguments == ["?", "?"])
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains(".+ infix(?, ?)"), Comment(rawValue: text))
                #expect(!text.contains(".+ infix(?, 7)"), Comment(rawValue: text))
            }
        }
    }
}
