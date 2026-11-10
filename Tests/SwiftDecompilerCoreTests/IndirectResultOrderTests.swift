import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let indirectOrderFixtures = [
    "Fixtures/Sample/libIndirectResultOrder.dylib",
    "Fixtures/Sample/libIndirectResultOrder.opt.dylib",
    "Fixtures/Sample/libIndirectResultOrder.size.dylib",
]

@Test func nativeWholeIndirectResultRunsBeforeTheEffectIfPresent() throws {
    func check(_ path: String) throws {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        let entry = try #require(dlsym(library, "indirect_order_native"))
        #expect(unsafeBitCast(entry, to: Entry.self)() == 12, Comment(rawValue: path))
    }
    for path in indirectOrderFixtures where FileManager.default.fileExists(atPath: path) { try check(path) }
}

@Test func wholeIndirectResultIsBoundBeforeAnInterveningEffectIfPresent() async throws {
    for path in indirectOrderFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "IndirectOrder.ordered(")
        }
        let streamed = try await withStableDependencies {
            let image = try BinaryLoader.load(path: path)
            return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        for group in [functions, filtered, streamed] {
            let function = try #require(group.first { $0.displayName.hasPrefix("IndirectOrder.ordered(") })
            let producer = try #require(function.instructions.first { $0.callee == "indirect_order_make_packet" })
            let effect = try #require(function.instructions.first { $0.callee?.hasPrefix("IndirectOrder.effect(") == true })
            let exit = try #require(function.instructions.last { $0.controlFlow == .return })
            #expect(producer.address < effect.address && effect.address < exit.address)
            if path == indirectOrderFixtures[0], producer.binding == nil {
                // -Onone keeps the packet in a frame slot the producer was
                // given; that local's reach is the whole frame, so the
                // reload after effect() declines.
                #expect(exit.exit?.statement == "return ?", Comment(rawValue: function.renderPseudo()))
                continue
            }
            let binding = try #require(producer.binding)
            let statement = binding.statement
            #expect(statement.hasPrefix("let ") && statement.hasSuffix(" = indirect_order_make_packet()"))
            let name = String(statement.dropFirst(4).prefix { $0 != " " })
            #expect(exit.exit?.statement == "return \(name)")
            for text in [function.renderPseudo(), function.renderStructured()] {
                let definition = try #require(text.range(of: statement))
                let middle = try #require(text.range(of: "IndirectOrder.effect()"))
                let returned = try #require(text.range(of: "return \(name)"))
                #expect(definition.lowerBound < middle.lowerBound && middle.lowerBound < returned.lowerBound)
                #expect(text.components(separatedBy: "indirect_order_make_packet()").count == 2)
            }
        }
    }
}

@Test func nativeSavedResultAliasCanChangeTheWholeBufferIfPresent() throws {
    func check(_ path: String) throws {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        for (name, expected) in [("indirect_alias_native", Int64(1299)), ("indirect_alias_cleared_native", Int64(102)),
                                 ("indirect_alias_context_native", Int64(1299)),
                                 ("indirect_alias_outlined_native", Int64(199)), ("indirect_alias_outlined_relay_native", Int64(199))] {
            let entry = try #require(dlsym(library, name))
            #expect(unsafeBitCast(entry, to: Entry.self)() == expected, "\(path): \(name)")
        }
        typealias FlagEntry = @convention(c) (Int64) -> Int64
        let joined = try #require(dlsym(library, "indirect_alias_joined_native"))
        for (flag, expected) in [(Int64(0), Int64(1202)), (Int64(1), Int64(12299))] {
            #expect(unsafeBitCast(joined, to: FlagEntry.self)(flag) == expected, "\(path): joined \(flag)")
        }
    }
    for path in indirectOrderFixtures where FileManager.default.fileExists(atPath: path) { try check(path) }
}

@Test func losingAnEscapedResultPointerSpillDeclinesTheWholeReturnIfPresent() async throws {
    for path in indirectOrderFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "IndirectOrder.alias")
        }
        let streamed = try await withStableDependencies {
            let image = try BinaryLoader.load(path: path)
            return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        for group in [functions, filtered, streamed] {
            let lost = try #require(group.first { $0.displayName.hasPrefix("IndirectOrder.aliasOrdered(") })
            let cleared = try #require(group.first { $0.displayName.hasPrefix("IndirectOrder.aliasCleared(") })
            let exit = try #require(lost.instructions.last { $0.controlFlow == .return })
            #expect(exit.exit?.statement == "return ?")
            for text in [lost.renderPseudo(), lost.renderStructured()] {
                #expect(text.contains("return ?"), Comment(rawValue: text))
                #expect(!text.contains("return alias_result_make("), Comment(rawValue: text))
                #expect(text.components(separatedBy: "alias_result_make(").count == 2)
            }
            // Overwriting the spill before the escape preserves the valid
            // whole-result proof: the pointer no longer resides in that slot.
            let cleanExit = try #require(cleared.instructions.last { $0.controlFlow == .return })
            let cleanProducer = try #require(cleared.instructions.first { $0.callee == "alias_result_make" })
            if cleanExit.exit?.statement == "return ?" {
                // The pre-fix Osize lowering already lacks this complete
                // return proof. The unoptimized and O controls recover it;
                // keep those, and allow a future Osize recovery too.
                #expect(path.hasSuffix(".size.dylib"))
            } else if let binding = cleanProducer.binding {
                #expect(binding.expression.hasPrefix("alias_result_make("))
                #expect(cleanExit.exit?.statement == "return \(binding.name)")
            } else {
                #expect(cleanExit.exit?.statement.contains("alias_result_make(") == true)
            }
            let joined = try #require(group.first { $0.displayName.hasPrefix("IndirectOrder.aliasJoined(") })
            let joinedExit = try #require(joined.instructions.last { $0.controlFlow == .return })
            #expect(joinedExit.exit?.statement == "return ?")
            for name in ["aliasContext", "aliasOutlined", "aliasOutlinedRelay"] {
                let context = try #require(group.first { $0.displayName.hasPrefix("IndirectOrder.\(name)(") })
                let contextExit = try #require(context.instructions.last { $0.controlFlow == .return })
                #expect(contextExit.exit?.statement == "return ?", "\(path): \(name)")
            }
        }
    }
}
