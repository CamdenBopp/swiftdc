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

    /// A private type IRGen did not wrap in an anonymous context: its
    /// descriptor's parent is the module, so the metadata names it
    /// `SIL.AccessPathWalker`, and only its descriptor symbol keeps the
    /// discriminator. Swift's own SIL module, in Xcode's
    /// `lib_InternalSwiftScan.dylib`, holds such types.
    @Test func aPrivateTypeWithoutAnonymousContextIsNamedByItsSymbolIfAvailable() async throws {
        let path = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/compiler/lib_InternalSwiftScan.dylib"
        guard let machO = try? BinaryLoader.load(path: path, architecture: "arm64"),
              machO.symbols.contains(where: { $0.name == "_$s3SIL16AccessPathWalker33_FFCBBB6CF68C612F8133E8B2C7CD6411LLVMn" })
        else { return }
        let text = await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
        #expect(text.contains("\nstruct SIL.(AccessPathWalker in _FFCBBB6CF68C612F8133E8B2C7CD6411) {"))
        #expect(text.contains("\nstruct SIL.(AccessPathWalker in _FFCBBB6CF68C612F8133E8B2C7CD6411).Path {"))
        #expect(!text.contains("\nstruct SIL.AccessPathWalker {"))
    }

    /// The descriptor symbol is used only when it names the printed type: a
    /// symbol that names another private type leaves the header as it was.
    @Test func aDescriptorSymbolNamingAnotherTypeIsNotUsedIfAvailable() throws {
        let path = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/compiler/lib_InternalSwiftScan.dylib"
        guard let machO = try? BinaryLoader.load(path: path, architecture: "arm64"),
              machO.symbols.contains(where: { $0.name == "_$s3SIL16AccessPathWalker33_FFCBBB6CF68C612F8133E8B2C7CD6411LLVMn" })
        else { return }
        let walker = try #require(UnrecordedTypes.all(in: machO).first {
            SwiftDeclarationDumper.displayName(of: $0, in: machO) == "SIL.AccessPathWalker"
        })
        let address = machO.address(forOffset: SwiftDeclarationDumper.descriptorOffset(of: walker))
        let header = "struct SIL.AccessPathWalker {\n}"
        let own = SwiftDeclarationDumper.placingLocalType(
            header, walker, symbols: [address: "_$s3SIL16AccessPathWalker33_FFCBBB6CF68C612F8133E8B2C7CD6411LLVMn"], in: machO)
        #expect(own == "struct SIL.(AccessPathWalker in _FFCBBB6CF68C612F8133E8B2C7CD6411) {\n}")
        let other = SwiftDeclarationDumper.placingLocalType(
            header, walker, symbols: [address: "_$s3SIL17CustomMirrorChild33_F86542DACA770FF4FE826722871B5CEELLVMn"], in: machO)
        #expect(other == header)
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

/// A type's descriptor points at its metadata accessor, so a stripped image
/// names it as its symbol does: `strip -x` left libSample.stripped 4 of its
/// 11 (the exported ones), the other 7 `sub_`.
@Test func aStrippedTypeMetadataAccessorIsNamedByItsDescriptorIfPresent() async throws {
    let original = "Fixtures/Sample/libSample.dylib", stripped = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: original), FileManager.default.fileExists(atPath: stripped) else { return }
    let machO = try BinaryLoader.load(path: original)
    var truth: [UInt64: String] = [:]
    for symbol in machO.symbols where symbol.name.hasSuffix("Ma") && symbol.name.hasPrefix("_$s") {
        guard let address = Disassembler.sectionAddress(of: symbol),
              let printed = accessorSymbolPrinted(String(symbol.name.dropFirst()))
        else { continue }
        truth[address] = printed
    }
    #expect(truth.count >= 10)
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: stripped) }
    for (address, name) in truth.sorted(by: { $0.key < $1.key }) {
        #expect(functions.first { $0.startAddress == address }?.displayName == name, "\(name)")
    }
}

/// A local type's accessor keeps the context its demangled name drops:
/// named `type metadata accessor for LocalTypes.Outer.LocalDouble`, it
/// claimed a member type `Outer` does not have.
@Test func aStrippedLocalTypesAccessorKeepsItsUnknownContextIfPresent() async throws {
    let path = "Fixtures/Sample/libLocalTypes.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let names = functions.map(\.displayName).filter { $0.hasPrefix("type metadata accessor for ") }
    #expect(names.contains { $0.hasPrefix("type metadata accessor for LocalTypes.Outer.(unknown context at $") && $0.hasSuffix(".LocalDouble") },
            "\(names)")
    #expect(!names.contains("type metadata accessor for LocalTypes.Outer.LocalDouble"), "\(names)")
    #expect(names.contains("type metadata accessor for LocalTypes.Outer"), "\(names)")
}

private func accessorSymbolPrinted(_ symbol: String) -> String? {
    (try? demangleAsNode(symbol))?.print(using: .default)
}

/// An accessor's type name leaves out an extension's where-clause, which
/// the descriptor and the symbol spell differently.
@Test func anAccessorNameLeavesOutWhereClauses() {
    #expect(MetadataSymbolizer.withoutWhereClauses(
        "(extension in M):Swift.Result< where A: Swift.Decodable, B: Swift.Error>.CodingKeys")
        == "(extension in M):Swift.Result.CodingKeys")
    #expect(MetadataSymbolizer.withoutWhereClauses("M.Box<Swift.Int>") == "M.Box<Swift.Int>")
    #expect(MetadataSymbolizer.withoutWhereClauses("M.A< where A: M.P<B>>.B< where C: M.Q>.C") == "M.A.B.C")
}

/// A struct's or enum's value witnesses, which its metadata record's table
/// points at, are named as their symbols demangle in the stripped image;
/// a function that only copies x1 to x0 or only returns (IRGen's shared
/// `__swift_memcpy40_8`, `__swift_noop_void_return`) is not named for one
/// type, and neither is one two types share.
@Test(arguments: ["libSample", "libReconstruction.opt", "libLocalTypes"])
func aStrippedValueWitnessIsNamedByItsTypesTableIfPresent(name: String) async throws {
    let original = "Fixtures/Sample/\(name).dylib", stripped = "Fixtures/Sample/\(name).stripped.dylib"
    guard FileManager.default.fileExists(atPath: original), FileManager.default.fileExists(atPath: stripped) else { return }
    let machO = try BinaryLoader.load(path: original)
    var truth: [UInt64: Set<String>] = [:]
    for symbol in machO.symbols {
        guard let address = Disassembler.sectionAddress(of: symbol) else { continue }
        let printed = symbol.name.hasPrefix("_$s") ? accessorSymbolPrinted(String(symbol.name.dropFirst())) : nil
        truth[address, default: []].insert(printed ?? symbol.name)
    }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: stripped) }
    let witnesses = functions.filter { $0.displayName.contains(" value witness for ") }
    #expect(witnesses.count >= 10, "\(witnesses.count)")
    for function in witnesses {
        let real = truth[function.startAddress] ?? []
        let marked = function.displayName.contains("(unknown context at $")
        let simple = function.displayName.components(separatedBy: ".").last ?? ""
        let agrees = real.contains(function.displayName)
            || (marked && real.contains { $0.hasPrefix(function.displayName.components(separatedBy: " for ")[0]) && $0.contains(simple + " #") })
        #expect(agrees, "\(name) 0x\(String(function.startAddress, radix: 16)): \(function.displayName) vs \(real)")
    }
}

/// IRGen's shared helpers sit in a type's value witness table, and are not
/// that type's witnesses: `__swift_memcpy200_8`, `Laden`'s initializeWithTake
/// alone in its slot, an unrolled copy longer than 16 instructions, stays
/// unnamed (`sharedwitness.swift`), while `Laden`'s own copy and assign
/// witnesses are named. Its destroy (load a reference, release it) has the
/// shape of `__swift_destroy_strong` and is declined with it.
@Test func aSharedHelperInOneTypesTableIsNotNamedForItIfPresent() async throws {
    let original = "Fixtures/Sample/libSharedWitness.dylib", stripped = "Fixtures/Sample/libSharedWitness.stripped.dylib"
    guard FileManager.default.fileExists(atPath: original), FileManager.default.fileExists(atPath: stripped) else { return }
    let machO = try BinaryLoader.load(path: original)
    let helpers = machO.symbols.filter {
        $0.name.hasPrefix("___swift_memcpy") || $0.name == "___swift_noop_void_return" || $0.name.hasSuffix("_strong")
    }
        .compactMap(Disassembler.sectionAddress(of:))
    #expect(helpers.count >= 6)
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: stripped) }
    for address in helpers {
        let name = functions.first { $0.startAddress == address }?.displayName ?? "-"
        #expect(!name.contains("value witness for"), "0x\(String(address, radix: 16)): \(name)")
    }
    for witness in ["initializeWithCopy", "assignWithCopy", "assignWithTake"] {
        #expect(functions.contains { $0.displayName == "\(witness) value witness for SharedWitness.Laden" }, "\(witness)")
    }
}

/// MachOSwiftSection 0.23 spells a local type it cannot place by its
/// anonymous context's address, `Outer.(Local in $1dbc)`. The bare name
/// comes back only when that address is the innermost context's; another
/// address is evidence that disagrees, and the name is declined.
@Test func aPositionNameIsUnwrappedOnlyAtItsInnermostContext() {
    let contexts: [(address: UInt64, below: [String])] = [(0x1dbc, ["Local"]), (0x1db4, ["Local"])]
    let text = "LocalTypes.Outer.(Local in $1dbc)"
    #expect(SwiftDeclarationDumper.withoutPositionName(text, contexts: contexts, from: text.startIndex)
        == "LocalTypes.Outer.Local")
    let other = "LocalTypes.Outer.(Local in $1db4)"
    #expect(SwiftDeclarationDumper.withoutPositionName(other, contexts: contexts, from: other.startIndex) == nil)
    let plain = "LocalTypes.Outer.Local"
    #expect(SwiftDeclarationDumper.withoutPositionName(plain, contexts: contexts, from: plain.startIndex) == plain)
}

/// Built with its anonymous contexts' mangled names, as Apple's cache
/// images are, a stripped local type is named by the function that
/// declares it (MachOSwiftSection 0.23), and its accessor and value
/// witnesses take that name, as their symbols demangle. A vtable label,
/// `T.method`, would append to the function's result type and is not
/// written for such a type.
@Test func aFunctionNamedLocalTypesAccessorIsNamedAsItsSymbolIfPresent() async throws {
    let original = "Fixtures/Sample/libLocalTypesNamed.dylib", stripped = "Fixtures/Sample/libLocalTypesNamed.stripped.dylib"
    guard FileManager.default.fileExists(atPath: original), FileManager.default.fileExists(atPath: stripped) else { return }
    let machO = try BinaryLoader.load(path: original)
    var truth: [UInt64: Set<String>] = [:]
    for symbol in machO.symbols where symbol.name.hasPrefix("_$s") {
        guard let address = Disassembler.sectionAddress(of: symbol),
              let printed = accessorSymbolPrinted(String(symbol.name.dropFirst()))
        else { continue }
        truth[address, default: []].insert(printed)
    }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: stripped) }
    let local = functions.filter { $0.displayName.contains(" #1 in ") }
    #expect(local.contains { $0.displayName == "type metadata accessor for Local #1 in LocalTypes.Outer.make() -> Any" },
            "\(local.map(\.displayName))")
    #expect(local.count >= 8, "\(local.map(\.displayName))")
    for function in local {
        #expect(truth[function.startAddress]?.contains(function.displayName) == true,
                "0x\(String(function.startAddress, radix: 16)): \(function.displayName) vs \(truth[function.startAddress] ?? [])")
    }
    #expect(!functions.contains { $0.displayName.hasSuffix("AnyObject.method") })
}

/// Only a local declaration on a name's context spine places a type: one
/// that appears in a generic argument (`Box<Local #1 in f()>`) says nothing
/// about where `Box` sits.
@Test func aLocalDeclarationPlacesATypeOnlyOnItsContextSpine() throws {
    let contexts: [(address: UInt64, below: [String])] = [(0x10, ["Local"]), (0x8, ["Local"])]
    let descriptor = try demangleAsNodeTransient("$s10LocalTypes5OuterV4makeypyF0A0L_VMn")
    #expect(SwiftDeclarationDumper.namesEveryAnonymousContext(descriptor, contexts: contexts))
    #expect(!SwiftDeclarationDumper.namesEveryAnonymousContext(descriptor, contexts: [(0x10, ["Other"])]))
    // `demangling cache variable for type metadata for M.Box<Local #1 in M.f() -> Any>`
    let box = try demangleAsNodeTransient("$s1M3BoxVyAA1fypyF5LocalL_VGMd")
    #expect(!SwiftDeclarationDumper.namesEveryAnonymousContext(box, contexts: contexts))
}

/// A protocol requirement's right-hand side prints as the type it is
/// (`protocolrhs.swift`). MachOSwiftSection 0.22 printed only the
/// associated types it found there, `Self.Readiness.Element ==
/// Self.Payload` for `== Event<Payload>`: a requirement the protocol does
/// not have. CloudKitDaemon's `CommonCheckProtocol` printed the same way.
@Test func aProtocolRequirementsGenericRightHandSideIsPrintedIfPresent() async throws {
    let path = "Fixtures/Sample/libProtocolRHS.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let interface = try await withStableDependencies { try await InterfaceReconstructor().reconstruct(machO) }
    #expect(interface.contains("Self.Readiness.Element == ProtocolRHS.Event<Self.Payload>"), Comment(rawValue: interface))
    #expect(interface.contains("Self.Pending == [Self.Payload]"), Comment(rawValue: interface))
    #expect(!interface.contains("Self.Readiness.Element == Self.Payload"), Comment(rawValue: interface))
}

/// A type nested in a local type carries its parent's position name,
/// `M.CostCache.(WorkItem in $3990c).State` (Xcode's SwiftUITap), and is
/// placed through it, as the type directly under the innermost context.
@Test func aNestedTypeIsUnwrappedThroughItsLocalParentsPositionName() {
    let contexts: [(address: UInt64, below: [String])] = [(0x3990c, ["State", "WorkItem"]), (0x39904, ["State", "WorkItem"])]
    let text = "M.CostCache.(WorkItem in $3990c).State"
    var unwrapped = SwiftDeclarationDumper.withoutPositionName(text, contexts: contexts, from: text.startIndex)
    #expect(unwrapped == "M.CostCache.WorkItem.State")
    #expect(unwrapped.map { SwiftDeclarationDumper.markingUnknownContexts(contexts, in: &unwrapped!, from: $0.startIndex) } == true)
    #expect(unwrapped == "M.CostCache.(unknown context at $39904).(unknown context at $3990c).WorkItem.State")
}

/// A stripped copy shares its original's install name and `LC_UUID`, the
/// key of MachOSwiftSection's per-image caches. Loaded after the original
/// in one process, it must not print the function names only the
/// original's symbols record. The pair has an install name of its own, so
/// no test running alongside loads a file with the same key.
@Test func aStrippedCopyLoadedAfterItsOriginalReadsOnlyItselfIfPresent() async throws {
    let original = "Fixtures/Sample/libLocalTypesPair.dylib", stripped = "Fixtures/Sample/libLocalTypesPair.stripped.dylib"
    guard FileManager.default.fileExists(atPath: original), FileManager.default.fileExists(atPath: stripped) else { return }
    let first = try BinaryLoader.load(path: original)
    let named = await withStableDependencies { await SwiftDeclarationDumper().dump(first, sections: [.types]) }
    #expect(named.contains("struct Local #1 in LocalTypes.Outer.make() -> Any {"))
    let second = try BinaryLoader.load(path: stripped)
    let text = await withStableDependencies { await SwiftDeclarationDumper().dump(second, sections: [.types]) }
    #expect(!text.contains("Local #1 in"), Comment(rawValue: text))
    #expect(text.contains("struct LocalTypes.Outer.(unknown context at $"), Comment(rawValue: text))
}
