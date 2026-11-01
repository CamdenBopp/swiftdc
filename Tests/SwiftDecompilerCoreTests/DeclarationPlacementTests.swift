import Testing
import Foundation
import Demangling
import MachOSwiftSection
@testable import SwiftDecompilerCore

/// Where `dump` places a type, and how it prints a field's type, checked
/// against what the binary itself says (`localtypes.swift`).
struct DeclarationPlacementTests {
    private func types(_ name: String) async throws -> String? {
        let path = "Fixtures/Sample/\(name)"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let machO = try BinaryLoader.load(path: path)
        return await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
    }

    /// A function-local type printed as a member of the enclosing type
    /// (`LocalTypes.Outer.Local`). With the type's descriptor symbol it is
    /// named by its function, as `swift-demangle` names that symbol.
    @Test func aLocalTypeIsNamedByItsFunctionIfPresent() async throws {
        guard let text = try await types("libLocalTypes.dylib") else { return }
        #expect(text.contains("struct Local #1 in LocalTypes.Outer.make() -> Any {"), Comment(rawValue: text))
        #expect(text.contains("struct FreeLocal #1 in LocalTypes.freeMake() -> Any {"), Comment(rawValue: text))
        #expect(!text.contains("struct LocalTypes.Outer.Local"), Comment(rawValue: text))
        // In a private function, where the renderer printed the private
        // discriminator form.
        #expect(text.contains("struct PrivateLocal #1 in LocalTypes.(privateMake in _"), Comment(rawValue: text))
    }

    /// Stripped, nothing names the function, and the anonymous context is
    /// marked where it was dropped, as the Swift runtime prints one.
    @Test func aStrippedLocalTypeKeepsItsUnknownContextIfPresent() async throws {
        guard let text = try await types("libLocalTypes.stripped.dylib") else { return }
        let local = text.split(separator: "\n").first { $0.hasSuffix(".Local {") }.map(String.init) ?? ""
        #expect(local.hasPrefix("struct LocalTypes.Outer.(unknown context at $"), "\(local)")
        #expect(!text.contains("struct LocalTypes.Outer.Local"), Comment(rawValue: text))
        #expect(!text.contains("struct LocalTypes.FreeLocal"), Comment(rawValue: text))
    }

    /// In a stripped binary a local class's methods are named from its
    /// vtable, and the name placed the class in `Outer`
    /// (`LocalTypes.Outer.LocalCounter.method`).
    @Test func aStrippedLocalClassMethodKeepsItsUnknownContextIfPresent() throws {
        let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
        let fixture = "Fixtures/Sample/libLocalTypes.stripped.dylib"
        guard FileManager.default.fileExists(atPath: binary.path), FileManager.default.fileExists(atPath: fixture) else { return }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = binary
        process.arguments = ["disasm", fixture]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let headers = String(decoding: data, as: UTF8.self).split(separator: "\n").filter { $0.contains("LocalCounter.method:") || $0.contains("LocalDouble.method:") }
        #expect(headers.count == 2, "\(headers)")
        for header in headers {
            #expect(header.hasPrefix("LocalTypes.Outer.(unknown context at $"), "\(header)")
        }
    }

    /// A class member's vtable entry was named like an instance one:
    /// `LocalTypes.Registry.getter` for `class var kind`.
    @Test func aStrippedClassMemberIsNamedStaticIfPresent() async throws {
        let path = "Fixtures/Sample/libLocalTypes.stripped.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let machO = try BinaryLoader.load(path: path)
        let names = await withStableDependencies { MetadataSymbolizer().functionNames(in: machO) }
        let registry = Set(names.unique.values.filter { $0.contains("Registry.") })
        #expect(registry.contains("static LocalTypes.Registry.getter"), "\(registry.sorted())")
        #expect(registry.contains("static LocalTypes.Registry.method"), "\(registry.sorted())")
        #expect(registry.contains("LocalTypes.Registry.method"), "\(registry.sorted())")
        #expect(registry.contains("static LocalTypes.SpecialRegistry.getter"), "\(registry.sorted())")
        #expect(!registry.contains("LocalTypes.Registry.getter"), "\(registry.sorted())")
    }

    /// A private class's anonymous context is its file, which the private
    /// discriminator names (`Foundation.(__PlistEncoder in _5692…)`). Marking
    /// local contexts must keep such a name, not decline it: on a stripped
    /// copy of Swift 5.0's back-deployed libswiftFoundation, the private
    /// encoder classes' methods are named.
    @Test func aPrivateClassKeepsItsDiscriminatedNameIfAvailable() async throws {
        let source = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.0/appletvos/libswiftFoundation.dylib"
        guard FileManager.default.fileExists(atPath: source) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-private-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stripped = directory.appendingPathComponent("stripped").path
        for arguments in [["strip", "-x", "-o", stripped, source]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0, "\(arguments)")
        }
        let machO = try BinaryLoader.load(path: stripped)
        let names = await withStableDependencies { MetadataSymbolizer().functionNames(in: machO) }
        let encoder = names.unique.values.filter { $0.contains("(__PlistEncoder in _") }
        #expect(!encoder.isEmpty, "\(names.unique.values.filter { $0.contains("PlistEncoder") })")
    }

    /// A constrained existential field printed `symbolic existential type
    /// (non-unique) 0x0 <Swift.String>`: no protocol, no meaning.
    @Test func aConstrainedExistentialFieldNamesItsProtocolIfPresent() async throws {
        guard let text = try await types("libLocalTypes.stripped.dylib") else { return }
        #expect(text.contains("var source: Swift.Optional<any LocalTypes.Source<Self.LocalTypes.Source.Element == Swift.String>>"), Comment(rawValue: text))
        #expect(!text.contains("symbolic existential"), Comment(rawValue: text))
        let machO = try BinaryLoader.load(path: "Fixtures/Sample/libLocalTypes.stripped.dylib")
        let maps = try await withStableDependencies { try FieldMapBuilder.build(in: machO) }
        let holder = try #require(maps["LocalTypes.Holder"])
        #expect(holder.fieldTypeNames["pair"] == "Swift.Optional<any LocalTypes.Source<Self.LocalTypes.Source.Element == Swift.Int>>")
    }

    /// A shape whose type names a parameter the arguments do not supply is
    /// not printed as a type.
    @Test func anUnresolvableShapeDeclines() {
        let parameter = Node.create(kind: .type, child: Node.create(kind: .dependentGenericParamType, children: [
            Node.create(kind: .index, index: 0), Node.create(kind: .index, index: 1),
        ]))
        let shape = Node.create(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, child: parameter)
        let arguments = Node.create(kind: .typeList, child: Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"), Node.create(kind: .identifier, text: "Int"),
        ])))
        let field = Node.create(kind: .type, child: Node.create(kind: .symbolicExtendedExistentialType, children: [shape, arguments]))
        #expect(throws: ExtendedExistentials.Unresolved.self) { try ExtendedExistentials.resolve(field) }
        // A parameter at depth 1 is no generalization parameter.
        let deeper = Node.create(kind: .type, child: Node.create(kind: .symbolicExtendedExistentialType, children: [
            Node.create(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, child: Node.create(kind: .type, child: Node.create(kind: .dependentGenericParamType, children: [
                Node.create(kind: .index, index: 1), Node.create(kind: .index, index: 0),
            ]))),
            arguments,
        ]))
        #expect(throws: ExtendedExistentials.Unresolved.self) { try ExtendedExistentials.resolve(deeper) }
        // Index 0 is supplied: it resolves to the argument.
        let resolvable = Node.create(kind: .type, child: Node.create(kind: .symbolicExtendedExistentialType, children: [
            Node.create(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, child: Node.create(kind: .type, child: Node.create(kind: .dependentGenericParamType, children: [
                Node.create(kind: .index, index: 0), Node.create(kind: .index, index: 0),
            ]))),
            arguments,
        ]))
        #expect((try? ExtendedExistentials.resolve(resolvable))?.print(using: .default) == "Swift.Int")
    }

    /// A type no `__swift5_types` record lists, reachable only from its
    /// field descriptor and another type's field, was missing from `dump`.
    @Test func aTypeNoRecordListsIsDeclaredIfPresent() async throws {
        guard let text = try await types("libUnrecordedType.dylib") else { return }
        #expect(text.contains("struct UnrecordedType.Inner {\n    var a: Swift.Int\n    var b: Swift.Int"), Comment(rawValue: text))
        #expect(text.contains("struct UnrecordedType.Holder {"), Comment(rawValue: text))
    }

    /// Swift Testing's noncopyable `FileHandle` has no record, and its field
    /// descriptor names it through an indirect (0x02) reference.
    @Test func aTypeNamedIndirectlyByItsFieldDescriptorIsDeclaredIfAvailable() async throws {
        let path = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/Testing.framework/Testing"
        guard let machO = try? BinaryLoader.load(path: path, architecture: "arm64"),
              machO.symbols.contains(where: { $0.name == "_$s7Testing10FileHandleVMn" })
        else { return }
        let text = await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
        #expect(text.contains("struct Testing.FileHandle: ~Swift.Copyable {\n    var _fileHandle: "))
    }

    /// `layout` and field naming read the same types: `Inner`, which no
    /// record lists, has its two fields.
    @Test func aTypeNoRecordListsIsLaidOutIfPresent() async throws {
        let path = "Fixtures/Sample/libUnrecordedType.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let machO = try BinaryLoader.load(path: path)
        let maps = try await withStableDependencies { try FieldMapBuilder.build(in: machO) }
        let inner = try #require(maps["UnrecordedType.Inner"])
        #expect(inner.fields.map(\.name) == ["a", "b"])
        #expect(inner.instanceSize == 16)
    }

    /// The reader the walk uses returns the file's bytes, at every offset
    /// and width, against a plain read of the file.
    @Test func theFieldDescriptorReaderReadsTheFileIfPresent() throws {
        let path = "Fixtures/Sample/libUnrecordedType.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let machO = try BinaryLoader.load(path: path)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let section = try #require(machO.sections.first { $0.sectionName == "__swift5_fieldmd" })
        var mismatches = 0
        for offset in section.offset ..< section.offset + section.size - 4 {
            let byte = bytes[offset]
            let word = bytes[offset ..< offset + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if UnrecordedTypes.read(offset, as: UInt8.self, in: machO) != byte { mismatches += 1 }
            if UnrecordedTypes.read(offset, as: UInt32.self, in: machO) != word { mismatches += 1 }
            if UnrecordedTypes.read(offset, as: UInt16.self, in: machO) != UInt16(truncatingIfNeeded: word) { mismatches += 1 }
        }
        #expect(mismatches == 0)
    }

    /// A type the renderer fails on was skipped, which read as a binary
    /// without it: GenerativeAgents' `OpenAICompatibleModel` (its argument
    /// type is a cross-image reference the reader does not follow).
    @Test func aTypeThatFailsToRenderIsNamedIfAvailable() async throws {
        let path = "/System/Library/PrivateFrameworks/GenerativeAgents.framework/Versions/A/GenerativeAgents"
        guard let machO = try? BinaryLoader.loadFromDyldCache(cachePath: nil, selector: .path(path)) else { return }
        // The metadata, not the output, says whether the type is there.
        let names = ((try? machO.swift.types) ?? []).map { SwiftDeclarationDumper.displayName(of: $0, in: machO) }
        guard names.contains("GenerativeAgents.OpenAICompatibleModel") else { return }
        let text = await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
        #expect(text.contains("// struct GenerativeAgents.OpenAICompatibleModel: not rendered: ")
            || text.contains("struct GenerativeAgents.OpenAICompatibleModel {"), Comment(rawValue: String(text.prefix(2000))))
    }
}
