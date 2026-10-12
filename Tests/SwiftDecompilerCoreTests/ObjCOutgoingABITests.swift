import Foundation
import Darwin
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

@Test(arguments: ["Fixtures/Sample/libObjCOutgoing.dylib", "Fixtures/Sample/libObjCOutgoing.opt.dylib"])
func objcOutgoingMixedBanksPreserveSourceOrder(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "forwardWhole") }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(functions.count == 1)
    #expect(text.contains("[self whole:arg0 fraction:arg1 object:arg2 tail:arg3]"), Comment(rawValue: text))
}

@Test(arguments: ["Fixtures/Sample/libObjCOutgoing.dylib", "Fixtures/Sample/libObjCOutgoing.opt.dylib"])
func objcOutgoingMixedConstantsPreserveFPValue(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "constants") }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(functions.count == 1)
    #expect(text.contains("[self whole:11 fraction:2.5 object:0 tail:33]"), Comment(rawValue: text))
}

@Test func objcOutgoingConflictingSelectorABIDeclines() {
    let caller = ObjCMethodBinding(className: "Base", selector: "forward:", typeEncoding: "v@:@",
        isClassMethod: false, signature: "")
    let base = ObjCMethodBinding(className: "Base", selector: "mixed:other:", typeEncoding: "v@:d@",
        isClassMethod: false, signature: "")
    let conflicting = ObjCMethodBinding(className: "Subclass", selector: "mixed:other:", typeEncoding: "v@:@d",
        isClassMethod: false, signature: "")
    let index = ObjCMetadataIndex(methods: [1: [base], 2: [conflicting]], fieldMaps: [:])
    guard case .declined = index.outgoingSignature(selector: "mixed:other:", className: caller.className, isClassMethod: caller.isClassMethod) else {
        Issue.record("Conflicting dynamic selector ABIs must not select a signature")
        return
    }
    let exact = ObjCMetadataIndex(methods: [1: [base]], fieldMaps: [:])
    guard case .known(_, let types) = exact.outgoingSignature(selector: "mixed:other:", className: caller.className, isClassMethod: caller.isClassMethod) else {
        Issue.record("A matching local declaration must recover argument types")
        return
    }
    #expect(types == ["d", "@"])
}

@Test func objcOutgoingConflictingSelectorRendersUnknownArguments() async throws {
    let path = "Fixtures/Sample/libObjCOutgoing.conflict.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "forwardWhole") }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(functions.count == 1)
    #expect(text.contains("[self whole:? fraction:? object:? tail:?]"), Comment(rawValue: text))
}

@Test func objcNativeFloatingReturnOracle() throws {
    let path = "Fixtures/Sample/libObjCOutgoing.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let doubleSymbol = try #require(dlsym(library, "SDOutgoingNativeDouble"))
    let floatSymbol = try #require(dlsym(library, "SDOutgoingNativeFloat"))
    let doubleOracle = unsafeBitCast(doubleSymbol, to: (@convention(c) () -> Double).self)
    let floatOracle = unsafeBitCast(floatSymbol, to: (@convention(c) () -> Float).self)
    #expect(doubleOracle() == 2.5)
    #expect(floatOracle() == 1.25)
}

/// The entry side: a method's own arguments seeded from its type encoding.
/// Positionally, `whole:fraction:object:tail:` read its `object` as arg1 and
/// its `tail` as arg2: the double in d0 shifted every later integer argument.
@Test(arguments: ["Fixtures/Sample/libObjCOutgoing.dylib", "Fixtures/Sample/libObjCOutgoing.opt.dylib"])
func objcEntryArgumentsFollowTheirBanks(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "-[SDOutgoingProbe whole:fraction:object:tail:]")
    }
    let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("self->_fraction = arg1"), Comment(rawValue: text))
    #expect(text.contains("self->_tail = arg3"), Comment(rawValue: text))
}

/// A receiver of unknown class (`forwardUntyped:(id)target value:(double)`),
/// sending a selector some implementation in the image takes a double for:
/// x2 may be stale while the value is in d0.
@Test func objcSendToUnknownReceiverWithFloatSelectorDeclinesIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCNonselfOutgoing.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "forwardUntyped")
    }
    let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("[arg0 twice:?]"), Comment(rawValue: text))
    #expect(!text.contains("twice:arg0"), Comment(rawValue: text))
}
