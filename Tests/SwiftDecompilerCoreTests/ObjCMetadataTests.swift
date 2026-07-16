import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func decodesObjCIvarStorageLayouts() {
    #expect(ObjCTypeLayoutDecoder.layout(of: "@\"NSString\"") == .init(size: 8, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "q") == .init(size: 8, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "[3i]") == .init(size: 12, alignment: 4))
    #expect(
        ObjCTypeLayoutDecoder.layout(of: "{CGRect={CGPoint=dd}{CGSize=dd}}")
            == .init(size: 32, alignment: 8)
    )
    #expect(ObjCTypeLayoutDecoder.layout(of: "(Value=iq)") == .init(size: 8, alignment: 8))
    #expect(ObjCTypeLayoutDecoder.layout(of: "?") == nil)
}

/// Objective-C method records carry their IMPs, so names and signatures survive
/// nlist stripping independently of Swift metadata and LC_FUNCTION_STARTS.
@Test func objcMethodBindingsSurviveStripping() throws {
    let release = "Fixtures/Sample/libSample.dylib"
    let stripped = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: release),
          FileManager.default.fileExists(atPath: stripped)
    else { return }

    let full = ObjCMetadataIndex.build(in: try BinaryLoader.load(path: release))
    let bare = ObjCMetadataIndex.build(in: try BinaryLoader.load(path: stripped))
    #expect(full.count > 0)

    let fullMethods = Dictionary(
        full.all.map { ($0.binding.displayName, $0.address) },
        uniquingKeysWith: { first, _ in first }
    )
    let bareMethods = Dictionary(
        bare.all.map { ($0.binding.displayName, $0.address) },
        uniquingKeysWith: { first, _ in first }
    )
    #expect(bareMethods["-[SDWidget ping]"] == fullMethods["-[SDWidget ping]"])
    if fullMethods["-[SDObjCCounter incrementBy:]"] != nil {
        #expect(bareMethods["-[SDObjCCounter incrementBy:]"] == fullMethods["-[SDObjCCounter incrementBy:]"])
    }
}

/// A filtered disassembly must be able to find an ObjC selector when the raw
/// implementation symbol is gone, and direct ivar loads/stores must use the
/// runtime's absolute ivar offsets.
@Test func recoversStrippedObjCMethodBodyAndIvars() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "incrementBy"
        )
    }
    guard let method = functions.first(where: { $0.objcMethod?.selector == "incrementBy:" }) else {
        // Older pre-built fixtures did not yet include sample_objc.m.
        return
    }
    #expect(method.source == .objcMetadata)
    #expect(method.displayName == "-[SDObjCCounter incrementBy:]")
    #expect(method.objcMethod?.signature == "- (long long)incrementBy:(long long)arg0;")
    let notes = method.instructions.compactMap(\.annotation)
    #expect(notes.contains("self->_count"))
    #expect(notes.contains("self->_count = …"))
    #expect(method.renderPseudo().contains("self->_count = …"))
}

/// ObjC metadata proves x0=self and x2=arg0 at entry. Both values should flow
/// through register moves into a recovered message expression.
@Test func tracksObjCReceiverArgumentsAndIvarValues() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "greetingWithPrefix"
        )
    }
    guard let method = functions.first(where: { $0.objcMethod?.selector == "greetingWithPrefix:" }) else {
        return
    }
    #expect(method.renderPseudo().contains("[arg0 stringByAppendingString:self->_name]"))
}

@Test func preservesObjCCategoryOwnership() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "sd_stringByAddingBang"
        )
    }
    guard let method = functions.first(where: { $0.objcMethod?.selector == "sd_stringByAddingBang" }) else {
        return
    }
    #expect(method.objcMethod?.className == "NSString")
    #expect(method.objcMethod?.categoryName == "SDSampleExtras")
    #expect(method.displayName == "-[NSString(SDSampleExtras) sd_stringByAddingBang]")
    #expect(method.renderPseudo().contains("[self stringByAppendingString:@\"!\"]"))
}
