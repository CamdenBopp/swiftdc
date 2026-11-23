import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A selector stub loads its selector into x1 and goes to objc_msgSend.
/// A stub was named `objc_msgSend$selector` for the load alone, so a
/// call to it rendered as a message send wherever the stub went next. In
/// selectorstubshape.s a stub of that opening branches to a function
/// that adds its first and third arguments, and its caller rendered
/// `[? take:7]`. A stub is a send only when it goes on to libobjc's
/// messenger.
private func views(_ name: String) async throws -> [String]? {
    let path = "Fixtures/Sample/libSelectorStubShape.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let function = try #require(functions.first { $0.symbol == "_\(name)" })
    return [function.renderStructured(), function.renderPseudo()]
}

/// Both forms a stub leaves by: a direct branch, and a jump through a
/// loaded slot. Neither reaches the messenger, so neither call is a send:
/// no selector is spelled, and the call is the stub's own.
@Test(arguments: [("calls_branching_stub", "branching_stub(", "take:"), ("calls_slot_stub", "slot_stub(", "show:")])
func aStubThatOnlyLoadsASelectorIsNotASendIfPresent(name: String, call: String, selector: String) async throws {
    guard let views = try await views(name) else { return }
    for text in views {
        #expect(!text.contains(selector), Comment(rawValue: text))
        #expect(!text.contains("objc_msgSend"), Comment(rawValue: text))
        #expect(text.contains("    \(call)"), Comment(rawValue: text))
    }
}

/// The control: a linker-made selector stub, which loads the messenger
/// from a slot bound to libobjc, still names its send (objcautorelease.m).
@Test func aSelectorStubThatReachesTheMessengerIsStillASendIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCAutorelease.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let named = functions.flatMap(\.instructions)
        .compactMap(DisassembledFunction.calleeName(of:))
        .filter { $0.hasPrefix("objc_msgSend$") }
    #expect(named.contains("objc_msgSend$appendString:"), "\(Set(named).sorted())")
    let rendered = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(rendered.contains(" appendString:"), "no appendString: send is rendered")
}
