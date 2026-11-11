import Foundation
import Testing
@testable import SwiftDecompilerCore

// `objc_factory_return.m`: an ARC factory builds one object, configures it
// and returns it through a tail `b objc_autoreleaseReturnValue`. The return
// was not counted as a use of the object, so its one other use (the
// configuring send) inlined it, and the return printed the allocation again:
// `[[[self alloc] init] setLimit:arg0]` then `return [[self alloc] init]`,
// two allocations where the binary makes one.

private func factoryBodies(_ path: String) async throws -> [String: (structured: String, pseudo: String)]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    var bodies: [String: (structured: String, pseudo: String)] = [:]
    for function in functions where function.displayName.hasPrefix("+[SDFactory ") || function.displayName.hasPrefix("-[SDFactory ") {
        bodies[function.displayName] = (function.renderStructured(), function.renderPseudo())
    }
    return bodies
}

private func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

/// Each factory form (`objc_alloc_init`, a custom init send, `objc_opt_new`,
/// alloc then `initWithCapacity:`) allocates once: the object is bound once,
/// configured through the binding, and returned as the binding, in both the
/// structured and the pseudo view.
@Test func anObjCFactoryReturnsTheObjectItConfiguredIfPresent() async throws {
    guard let bodies = try await factoryBodies("Fixtures/Sample/libObjCFactoryReturn.dylib") else { return }
    let expected: [(name: String, binding: String, send: String)] = [
        ("+[SDFactory k1:]", "let r0 = [[self alloc] init]", "[r0 setLimit:arg0]"),
        ("+[SDFactory k2]", "initWithLimit:3]", "[r0 setLimit:4]"),
        ("+[SDFactory k3]", "let r0 = [[NSMutableArray alloc] init]", "[r0 addObject:@\"x\"]"),
        ("+[SDFactory k4]", "let r0 = [[NSMutableArray alloc] initWithCapacity:4]", "[r0 addObject:@\"y\"]"),
    ]
    for (name, binding, send) in expected {
        let body = try #require(bodies[name], "\(name) missing")
        for text in [body.structured, body.pseudo] {
            #expect(occurrences(of: " alloc]", in: text) == 1, "\(name) allocates once: \(text)")
            #expect(text.contains(binding), "\(name): \(text)")
            #expect(text.contains("let r0 = "), "\(name): \(text)")
            #expect(text.contains(send), "\(name): \(text)")
            #expect(text.contains("return r0"), "\(name): \(text)")
        }
    }
}

/// The guard against over-binding: an object built and returned with no
/// other use has one use, and stays inline.
@Test func anObjCFactoryWithOneUseStaysInlineIfPresent() async throws {
    guard let bodies = try await factoryBodies("Fixtures/Sample/libObjCFactoryReturn.dylib") else { return }
    let body = try #require(bodies["+[SDFactory k0]"])
    for text in [body.structured, body.pseudo] {
        #expect(text.contains("return [[self alloc] init]"), Comment(rawValue: text))
        #expect(!text.contains("let r"), Comment(rawValue: text))
    }
}

/// An in-image class object passed by address (`adrp; add x0, …` before
/// `objc_alloc`) is the class: `[[SDFactory alloc] initWithLimit:3]`, which
/// rendered `[[0x8180 alloc] …]`.
@Test func anInImageClassObjectIsNamedByItsClassIfPresent() async throws {
    guard let bodies = try await factoryBodies("Fixtures/Sample/libObjCFactoryReturn.dylib") else { return }
    let body = try #require(bodies["+[SDFactory k2]"])
    for text in [body.structured, body.pseudo] {
        #expect(text.contains("let r0 = [[SDFactory alloc] initWithLimit:3]"), Comment(rawValue: text))
    }
}

/// Two classes claiming one class object address name neither: the address
/// stays raw rather than taking whichever was read first.
@Test func aClassObjectAddressTwoClassesClaimIsNotNamed() {
    let names = ObjCMetadataSnapshot.classObjects([
        (address: 0x8180, name: "A"), (address: 0x8180, name: "B"),
        (address: 0x81d0, name: "C"), (address: 0x81d0, name: "C"),
    ])
    #expect(names == [0x81d0: "C"])
}

/// A Swift class is in the class list too, but its class object is its type
/// metadata: named by the class list, `type metadata accessor for
/// Sample.Widget` read `return SDWidget`, its `@objc` name.
@Test func aSwiftClassObjectIsNotNamedAsAnObjCClassIfPresent() async throws {
    let path = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "type metadata accessor for Sample.Widget")
    }
    let function = try #require(functions.first { $0.displayName == "type metadata accessor for Sample.Widget" })
    let text = function.renderStructured()
    #expect(text.contains("0x"), Comment(rawValue: text))
    #expect(!text.contains("SDWidget"), Comment(rawValue: text))
}
