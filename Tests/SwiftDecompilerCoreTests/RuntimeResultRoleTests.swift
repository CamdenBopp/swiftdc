import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

/// A call that ignores x8 leaves the caller's result buffer as it was, so
/// the stores before it are the result. That was granted to every name
/// starting `swift_` or `objc_` once the name was bound to its library.
/// The binding says whose function it is, not where the function puts its
/// result: `_objc_msgForward`, declared `void (void)` and bound to libobjc,
/// returns whatever the forwarded method returns, and after it
/// `staleAfterForward` rendered `return ResultRole.Big(a: 27, …)`.
/// resultrole.swift states each function's true behaviour.
private let resultRoleImage = "Fixtures/Sample/libResultRole.dylib"

private func resultRoleViews(_ name: String) async throws -> [String]? {
    guard FileManager.default.fileExists(atPath: resultRoleImage) else { return nil }
    var views: [String] = []
    for filtered in [false, true] {
        let functions = try await withStableDependencies {
            filtered ? try await Disassembler().disassemble(path: resultRoleImage, functionFilter: name)
                     : try await Disassembler().disassemble(path: resultRoleImage)
        }
        let function = try #require(functions.first { $0.displayName.hasPrefix("ResultRole.\(name)(") })
        views += [function.renderStructured(), function.renderPseudo()]
    }
    return views
}

/// The library a two-level import is bound to, from the symbol table.
private func resultRoleProvider(of name: String) throws -> String {
    let image = try BinaryLoader.load(path: resultRoleImage)
    let symbol = try #require(image.symbols.first { $0.name == "_" + name && $0.offset == 0 })
    let description = try #require(symbol.nlist.symbolDescription)
    let libraries = Array(image.dependencies)
    let index = Int(description.libraryOrdinal) - 1
    try #require(libraries.indices.contains(index))
    return libraries[index].dylib.name
}

/// The forwarding entry forwards the method's result convention.
@Test func aResultBufferIsNotKeptAcrossTheForwardingEntryIfPresent() async throws {
    guard let views = try await resultRoleViews("staleAfterForward") else { return }
    #expect(try resultRoleProvider(of: "_objc_msgForward") == "/usr/lib/libobjc.A.dylib")
    for text in views {
        #expect(!text.contains("Big(a:"), Comment(rawValue: text))
        #expect(text.contains("    return ?\n"), Comment(rawValue: text))
        #expect(text.contains("_objc_msgForward("), Comment(rawValue: text))
    }
}

/// The controls: bound to the runtime and declared to return nothing, one
/// register or two, or read by hand as returning nothing.
@Test func aResultBufferIsKeptAcrossARuntimeCallDeclaredDirectIfPresent() async throws {
    for (name, callee, word) in [("keptAfterRelease", "swift_release", 9), ("keptAfterAllocObject", "swift_allocObject", 11),
                                 ("keptAfterAllocBox", "swift_allocBox", 13), ("keptAfterReleaseN", "swift_release_n", 15)] {
        guard let views = try await resultRoleViews(name) else { return }
        #expect(try resultRoleProvider(of: callee) == "/usr/lib/swift/libswiftCore.dylib")
        for text in views {
            #expect(text.contains("    return ResultRole.Big(a: \(word), b: \(word), c: \(word), d: \(word), e: \(word))\n"),
                    Comment(rawValue: text))
        }
    }
}

/// A runtime name another library exports carries no declaration:
/// `swift_slowAlloc` is the runtime's pointer-returning allocator by name
/// and a five-word result here.
@Test(arguments: [("staleAfterForeignFuture", "swift_opaqueResult"), ("staleAfterForeignAlloc", "swift_slowAlloc")])
func aResultBufferIsNotKeptAcrossARuntimeNameFromAnotherLibraryIfPresent(name: String, callee: String) async throws {
    guard let views = try await resultRoleViews(name) else { return }
    #expect(try resultRoleProvider(of: callee) == "@rpath/libResultRoleProvider.dylib")
    for text in views {
        #expect(!text.contains("Big(a:"), Comment(rawValue: text))
        #expect(text.contains("    return ?\n"), Comment(rawValue: text))
        #expect(text.contains(callee + "("), Comment(rawValue: text))
    }
}

/// The runtime's own function returning three words through x8.
@Test func aResultBufferIsNotKeptAcrossARuntimeCallReturningThroughX8IfPresent() async throws {
    guard let views = try await resultRoleViews("staleAfterVersion") else { return }
    #expect(try resultRoleProvider(of: "_swift_stdlib_operatingSystemVersion") == "/usr/lib/swift/libswiftCore.dylib")
    for text in views {
        #expect(!text.contains("Big(a:"), Comment(rawValue: text))
        #expect(text.contains("    return ?\n"), Comment(rawValue: text))
    }
}

/// A name no table declares has no result convention, whatever its prefix.
@Test func aRuntimeNameNoTableDeclaresHasNoDirectResult() {
    for name in ["swift_opaqueResult", "swift_futureResult", "_swift_futureResult", "objc_futureResult",
                 "objc_release_x200", "objc_release_x"] {
        #expect(!Disassembler.isKnownDirectReturnCallee(name), "\(name)")
    }
    for name in ["_objc_msgForward", "_objc_msgForward_stret", "objc_msgSend", "objc_msgSend$count"] {
        #expect(!Disassembler.isKnownDirectReturnCallee(name), "\(name)")
    }
}

/// Each source of a declared direct result, separately.
@Test func aRuntimeNameIsDirectByItsOwnDeclaration() {
    // The runtime's table: nothing, a register, two words, d0, s0.
    for name in ["swift_release", "swift_allocObject", "swift_allocBox", "swift_intToFloat64", "swift_intToFloat32",
                 "_swift_isOptional"] {
        #expect(Disassembler.isKnownDirectReturnCallee(name), "\(name)")
    }
    // The SDK's headers.
    for name in ["objc_getClass", "objc_storeWeak", "objc_terminate"] {
        #expect(Disassembler.isKnownDirectReturnCallee(name), "\(name)")
    }
    // The key path setters, read by hand; the getter returns through x8.
    #expect(Disassembler.isKnownDirectReturnCallee("swift_setAtWritableKeyPath"))
    #expect(!Disassembler.isKnownDirectReturnCallee("swift_getAtKeyPath"))
    // Read by hand, with no row in a table.
    for name in Disassembler.undeclaredDirectResultRuntimeNames {
        #expect(DisassembledFunction.cPrototype(of: name) == nil, "\(name) has a declaration now")
        #expect(Disassembler.isKnownDirectReturnCallee(name), "\(name)")
    }
    // The retain family and the register-specific entries, which have
    // no declaration either.
    for name in ["swift_retain", "objc_retain_x19", "objc_autoreleaseReturnValue", "objc_release_x20"] {
        #expect(Disassembler.isKnownDirectReturnCallee(name), "\(name)")
    }
    // Outside the runtimes nothing moved.
    #expect(Disassembler.isKnownDirectReturnCallee("malloc"))
    #expect(Disassembler.isKnownDirectReturnCallee("__swift_memcpy16_8"))
    #expect(!Disassembler.isKnownDirectReturnCallee("getpid"))
}

/// `x` and `s` do not say where a result goes, except the runtime
/// table's `x`, which is two words.
@Test func aResultRoleIsDirectOnlyWhenItNamesRegisters() {
    for role in "vifd" {
        #expect(Disassembler.isDirectResultRole(role, inRuntimeTable: false))
        #expect(Disassembler.isDirectResultRole(role, inRuntimeTable: true))
    }
    #expect(Disassembler.isDirectResultRole("x", inRuntimeTable: true))
    #expect(!Disassembler.isDirectResultRole("x", inRuntimeTable: false))
    #expect(!Disassembler.isDirectResultRole("s", inRuntimeTable: true))
    #expect(!Disassembler.isDirectResultRole("s", inRuntimeTable: false))
}

/// Whose function it is and where its result goes are separate proofs:
/// each alone declines.
@Test func aLibraryBindingAndAResultDeclarationAreSeparateProofs() {
    let core = "/usr/lib/swift/libswiftCore.dylib", other = "@rpath/libResultRoleProvider.dylib"
    func bound(_ name: String, _ library: String) -> Bool {
        RuntimeFunctionReference(rawSymbol: "_" + name, libraryName: library).permitsNamedABI(named: name)
    }
    #expect(bound("swift_slowAlloc", core) && Disassembler.isKnownDirectReturnCallee("swift_slowAlloc"))
    #expect(!bound("swift_slowAlloc", other))
    #expect(!bound("swift_futureResult", core))
    #expect(!Disassembler.isKnownDirectReturnCallee("swift_futureResult"))
    // Bound and declared, and still not direct.
    #expect(bound("_objc_msgForward", "/usr/lib/libobjc.A.dylib"))
    #expect(!Disassembler.isKnownDirectReturnCallee("_objc_msgForward"))
}

/// The runtime table's generator writes `x` for any result width it does
/// not name. Each row below was read as two words (BoxPair,
/// MetadataResponse, MetadataDependency, TypeNamePair, OffsetPair,
/// ClassExtents, BufferAndSize, AsyncTaskAndContext, the executor
/// references). A new `x` row is read before it joins them.
@Test func everyTwoWordRuntimeResultWasRead() {
    let read: Set<String> = [
        "_swift_getObjCClassInstanceExtents", "_swift_getSwiftClassInstanceExtents", "swift_allocBox",
        "swift_allocBoxTyped", "swift_allocError", "swift_checkMetadataState", "swift_distributed_getWitnessTables",
        "swift_getAssociatedTypeWitness", "swift_getAssociatedTypeWitnessRelative",
        "swift_getAssociatedTypeWitnessSlow", "swift_getBorrowTypeMetadata",
        "swift_getCanonicalPrespecializedGenericMetadata", "swift_getCanonicalSpecializedMetadata",
        "swift_getFixedArrayTypeMetadata", "swift_getForeignTypeMetadata", "swift_getFunctionFullNameFromMangledName",
        "swift_getGenericMetadata", "swift_getMangledTypeName", "swift_getOpaqueTypeMetadata",
        "swift_getOpaqueTypeMetadata2", "swift_getSingletonMetadata", "swift_getTupleTypeLayout3",
        "swift_getTupleTypeMetadata", "swift_getTupleTypeMetadata2", "swift_getTupleTypeMetadata3", "swift_getTypeName",
        "swift_initClassMetadata2", "swift_makeBoxUnique", "swift_makeBoxUniqueTyped", "swift_task_create",
        "swift_task_create_common", "swift_task_getCurrentExecutor", "swift_task_getMainExecutor",
        "swift_task_getPreferredTaskExecutor", "swift_updateClassMetadata2",
    ]
    let table = Set(SwiftRuntimeSignatures.table.filter { $0.value.first == "x" }.keys)
    #expect(table.subtracting(read).sorted() == [])
    #expect(read.subtracting(table).sorted() == [])
}

/// Every runtime row of both tables is direct exactly when its result
/// code names registers.
@Test func everyDeclaredRuntimeRowIsDirectByItsResultCode() {
    func isRuntimeName(_ name: String) -> Bool {
        let bare = name.drop(while: { $0 == "_" })
        return bare.hasPrefix("swift_") || bare.hasPrefix("objc_")
    }
    let forwards: Set<String> = ["_objc_msgForward", "_objc_msgForward_stret"]
    var checked = 0
    for (name, entry) in SwiftRuntimeSignatures.table where isRuntimeName(name) {
        guard let role = entry.first else { continue }
        #expect(Disassembler.isKnownDirectReturnCallee(name) == "vifdx".contains(role), "\(name) \(role)")
        checked += 1
    }
    let sdk = SDKCPrototypes.data.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
    for line in sdk.split(separator: "\n") {
        let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count >= 2, let role = fields[1].first, fields[1].count == 1 else { continue }
        let name = String(fields[0])
        guard isRuntimeName(name), !forwards.contains(name) else { continue }
        #expect(Disassembler.isKnownDirectReturnCallee(name) == "vifd".contains(role), "\(name) \(role)")
        checked += 1
    }
    #expect(checked > 600)
}
