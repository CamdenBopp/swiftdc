import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let importedReceiverFixtures = [
    "Fixtures/Sample/libImportedReceiver.dylib",
    "Fixtures/Sample/libImportedReceiver.opt.dylib",
    "Fixtures/Sample/libImportedReceiver.size.dylib",
]

@Test func importedReceiverABIsHaveNativeOraclesIfPresent() throws {
    for path in importedReceiverFixtures where FileManager.default.fileExists(atPath: path) {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        for name in ["imported_url_bridge_oracle", "imported_url_bridge_opaque_oracle",
                     "imported_string_prefix_address_oracle", "imported_string_prefix_scalar_oracle",
                     "imported_string_reference_oracle", "imported_passthrough_oracle", "imported_wide_oracle",
                     "imported_string_paired_oracle", "imported_string_mismatched_oracle",
                     "imported_scalar_word_oracle", "imported_scalar_whole_oracle", "imported_double_word_oracle",
                     "imported_integer_word_oracle", "imported_four_oracle", "imported_unused_receiver_oracle",
                     "imported_spanning_field_oracle"] {
            let entry = try #require(dlsym(library, name))
            #expect(unsafeBitCast(entry, to: Entry.self)() == 1, "\(path): \(name)")
        }
    }
}

@Test func importedReceiverWordsRequireTheirActualABIIfPresent() async throws {
    for path in importedReceiverFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "imported_")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [listing, array, filtered, streamed, Array(each.values)] {
            for name in ["_imported_url_bridge_shape", "_imported_url_bridge_opaque"] {
                let function = try #require(functions.first { $0.symbol == name })
                let call = try #require(function.instructions.first {
                    DisassembledFunction.calleeName(of: $0)?.contains("URL._bridgeToObjectiveC") == true
                })
                #expect(call.callArguments?.isEmpty ?? true, "\(path): \(name)")
                #expect(!function.renderPseudo().contains("0x1234"), "\(path): \(name)")
            }
            for name in ["_imported_string_prefix_address", "_imported_string_prefix_scalar"] {
                let function = try #require(functions.first { $0.symbol == name })
                let call = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0)?.contains("String.hasPrefix") == true
                })
                #expect(call.callSelf == nil, "\(path): \(name)")
                #expect(call.callArguments == ["\"ab\"", "\"abc\""], "\(path): \(name)")
                for text in [function.renderPseudo(), function.renderStructured()] {
                    #expect(text.contains("Swift.String.hasPrefix(\"ab\", \"abc\")"), Comment(rawValue: text))
                    #expect(!text.contains("0x1238"), Comment(rawValue: text))
                }
            }
        }
    }
}

@Test func unchangedEntryValueRemainsAProvenReceiverIfPresent() async throws {
    for path in importedReceiverFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "ImportedSelf.passThrough(")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [listing, array, filtered, streamed, Array(each.values)] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("ImportedSelf.passThrough(") })
            let call = try #require(function.instructions.first {
                DisassembledFunction.calleeName(of: $0)?.contains("Meter.scaled") == true
            })
            // The value receiver is the method's self (dev renders its words
            // as `self:`); the formal stays positional. -Onone materializes
            // Meter through a separate constructor whose result this IR cannot
            // yet recover; keep that receiver unknown.
            let receiver = path == importedReceiverFixtures[0] ? "?" : "arg1"
            #expect(call.callSelf == receiver, Comment(rawValue: function.renderPseudo()))
            #expect(call.callArguments == ["arg0"], Comment(rawValue: function.renderPseudo()))
        }
    }
}

@Test func importedReceiverExpressionsRequireWholeValuesIfPresent() async throws {
    for path in importedReceiverFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "imported_")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [listing, array, filtered, streamed, Array(each.values)] {
            // String.hasPrefix takes its receiver's words after the formal;
            // a Meter receiver is the method's value self.
            for (name, callee, expected, receiver) in [
                ("_imported_string_prefix_paired", "String.hasPrefix", ["\"abc\"", "ImportedSelf.makeReceiverString()"], nil),
                ("_imported_string_prefix_mismatched", "String.hasPrefix", ["\"abc\"", "?"], nil),
                ("_imported_scalar_receiver_word", "Meter.scaled", ["7"], "?"),
                // The whole receiver is the bound result of makeReceiverScalar().
                ("_imported_scalar_receiver_whole", "Meter.scaled", ["7"], "r0"),
                // -Onone stores the receiver's entry word for debug state,
                // which is a positive machine read. Optimized bodies do not.
                ("_imported_unused_receiver", "Meter.ignore", ["7"], path == importedReceiverFixtures[0] ? "0x1234" : nil),
            ] as [(String, String, [String], String?)] {
                let function = try #require(functions.first { $0.symbol == name })
                let call = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0)?.contains(callee) == true
                })
                #expect(call.callArguments == expected, Comment(rawValue: function.renderPseudo()))
                #expect(call.callSelf == receiver, Comment(rawValue: function.renderPseudo()))
                if receiver == "r0" {
                    #expect(function.renderPseudo().contains("let r0 = ImportedSelf.makeReceiverScalar()"),
                            Comment(rawValue: function.renderPseudo()))
                }
            }
        }
    }
}

@Test func receiverFootprintsKeepTheCompilerDirectIndirectBoundaryIfPresent() throws {
    for path in importedReceiverFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let maps = try FieldMapBuilder.build(in: image)
        let direct = SwiftLowering.directAggregateRegisters(of: "ImportedSelf.Four", fieldMaps: maps)
        #expect(direct?.integers == 4 && direct?.floats == 0)
        #expect(SwiftLowering.directAggregateRegisters(of: "ImportedSelf.Wide", fieldMaps: maps) == nil)
        let indirect = SwiftLowering.aggregateRegisters(of: "ImportedSelf.Wide", fieldMaps: maps)
        #expect(indirect?.integers == 1 && indirect?.floats == 0)
    }
}

@Test func receiverIntegerWordsRequireAnIntegerFieldIfPresent() async throws {
    for path in importedReceiverFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "Word")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [listing, array, filtered, streamed, Array(each.values)] {
            for (name, receiver) in [("ImportedSelf.boxWordBits(", "?"),
                                     ("ImportedSelf.DoubleBox.selfWordBits(", "?"),
                                     ("ImportedSelf.DoubleBox.selfIntegerWord(", "self.integer"),
                                     ("ImportedSelf.PackedBox.packedWord(", "?"),
                                     ("ImportedSelf.boxIntegerWord(", "arg0.integer")] {
                let function = try #require(functions.first { $0.displayName.hasPrefix(name) })
                let call = try #require(function.instructions.first {
                    $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0)?.contains("Meter.scaled") == true
                })
                #expect(call.callArguments == ["3"], Comment(rawValue: function.renderPseudo()))
                #expect(call.callSelf == receiver, Comment(rawValue: function.renderPseudo()))
            }
        }
    }
}
