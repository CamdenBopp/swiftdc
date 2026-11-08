import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

/// The callee's metadata gives `whole:ratio:tail:` GP/FP/GP arguments. A
/// receiver loaded from a typed ivar is not `.selfPointer`, but its declared
/// class is still available without guessing from the selector spelling.
@Test func typedNonselfReceiverUsesItsMetadataABIIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCNonselfOutgoing.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }

    let image = try BinaryLoader.load(path: path)
    let index = ObjCMetadataIndex.build(in: image)
    let callerFields = try #require(index.fieldMaps["SDNonselfCaller"])
    #expect(callerFields.lookup(offset: 8, bytes: 8)
        == .success(.whole(name: "_target", typeMangledName: "@\"SDNonselfTarget\"")))
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path, functionFilter: "SDNonselfCaller"
        )
    }
    let whole = try #require(functions.first { $0.objcMethod?.selector == "forwardWhole:ratio:tail:" })
    let twice = try #require(functions.first { $0.objcMethod?.selector == "forwardTwice:" })
    let untyped = try #require(functions.first { $0.objcMethod?.selector == "forwardUntyped:value:" })
    #expect(whole.renderPseudo().contains("[self->_target whole:arg0 ratio:arg1 tail:arg2]"))
    #expect(twice.renderPseudo().contains("[self->_target twice:arg0]"))
    #expect(untyped.renderPseudo().contains("[arg0 twice:?]"))
    #expect(!untyped.renderPseudo().contains("[arg0 twice:arg0]"))
}

@Test func typedNonselfNativeOracleIfPresent() throws {
    let path = "Fixtures/Sample/libObjCNonselfOutgoing.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let wholeSymbol = try #require(dlsym(library, "SDNonselfNativeWhole"))
    let twiceSymbol = try #require(dlsym(library, "SDNonselfNativeTwice"))
    let whole = unsafeBitCast(wholeSymbol, to: (@convention(c) () -> Double).self)
    let twice = unsafeBitCast(twiceSymbol, to: (@convention(c) () -> Double).self)
    #expect(whole() == 46.5)
    #expect(twice() == 2.5)
}
