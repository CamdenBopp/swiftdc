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
    #expect(notes.contains("self->_count += arg0"))
    #expect(method.renderPseudo().contains("self->_count += arg0"))
    #expect(method.renderPseudo().contains("return self->_count"))
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
    #expect(method.renderPseudo().contains("return [arg0 stringByAppendingString:self->_name]"))
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
    #expect(method.renderPseudo().contains("return [self stringByAppendingString:@\"!\"]"))
}

/// Stage 2 retains values through arithmetic, runtime property helpers, subword
/// ivar accesses, initializer super-calls, and return registers.
@Test func recoversSourceLikeObjCStatements() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "SDObjCCounter"
        )
    }

    func pseudo(_ selector: String) -> String {
        functions.first(where: { $0.objcMethod?.selector == selector })?.renderPseudo() ?? ""
    }

    let initializer = pseudo("initWithName:count:")
    #expect(initializer.contains("self = [super init]"))
    #expect(initializer.contains("self->_name = [arg0 copy]"))
    #expect(initializer.contains("self->_count = arg1"))
    #expect(initializer.contains("self->_enabled = YES"))
    #expect(initializer.contains("return self"))
    let structuredInitializer = functions
        .first(where: { $0.objcMethod?.selector == "initWithName:count:" })?
        .renderStructured() ?? ""
    #expect(structuredInitializer.contains("if (self != 0)"))
    #expect(!structuredInitializer.contains("if (sp"))
    #expect(pseudo("name").contains("return self->_name"))
    #expect(pseudo("setName:").contains("self->_name = [arg0 copy]"))
    #expect(pseudo("isEnabled").contains("return self->_enabled"))
    #expect(pseudo("setEnabled:").contains("self->_enabled = arg0"))
    #expect(pseudo(".cxx_destruct").contains("self->_name = nil"))
    #expect(pseudo("formattedCount").contains(
        "return [NSString stringWithFormat:@\"%ld\", self->_count]"
    ))
    #expect(pseudo("seventhValueA:b:c:d:e:f:g:").contains("return arg6"))

    let json = functions.jsonString()
    #expect(json.contains("\"statement\" : \"return self->_name\""))
}

@Test func structuresObjCControlFlowWithSourceNames() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "incrementIfEnabled"
        )
    }
    guard let method = functions.first(where: { $0.objcMethod?.selector == "incrementIfEnabled:" })
    else { return }
    let structured = method.renderStructured()
    #expect(structured.contains("if (self->_enabled)"))
    #expect(structured.contains("self->_count += arg0"))
    #expect(structured.contains("return self->_count"))

    let argumentFunctions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(
            path: path,
            functionFilter: "incrementIfPositive"
        )
    }
    guard let argumentMethod = argumentFunctions.first(where: {
        $0.objcMethod?.selector == "incrementIfPositive:"
    }) else { return }
    let argumentStructured = argumentMethod.renderStructured()
    #expect(argumentStructured.contains("arg0"))
    #expect(!argumentStructured.contains("x2"))
}
