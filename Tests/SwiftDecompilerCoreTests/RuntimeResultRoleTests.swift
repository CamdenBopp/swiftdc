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
