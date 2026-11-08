import Testing
import Foundation
@testable import SwiftDecompilerCore

/// What a send asks of a selector's implementations is worked out once per
/// selector. These pin each answer to what scanning them says, across the
/// cases a memo can get wrong: instance against class methods, one class's
/// first declaration, disagreement, and an answer of nil.
private func binding(_ className: String, _ encoding: String, isClassMethod: Bool = false, selector: String = "go:") -> ObjCMethodBinding {
    ObjCMethodBinding(className: className, selector: selector, typeEncoding: encoding,
                      isClassMethod: isClassMethod, signature: "")
}

@Test func aSendAsksEachOfItsAnswersPerMethodKind() {
    let index = ObjCMetadataIndex(methods: [
        1: [binding("A", "v@:q")],
        2: [binding("A", "q24@0:8q16")],                     // A's second, same arguments
        3: [binding("B", "v@:q")],
        4: [binding("C", "d@:d", isClassMethod: true)],
    ], fieldMaps: [:])
    // A class's first declaration names the encoding, every one must agree.
    #expect(index.outgoingSignature(selector: "go:", className: "A", isClassMethod: false)
        == .known(encoding: "v@:q", types: ["q"]))
    #expect(index.outgoingSignature(selector: "go:", className: "B", isClassMethod: false)
        == .known(encoding: "v@:q", types: ["q"]))
    #expect(index.outgoingSignature(selector: "go:", className: "Z", isClassMethod: false) == .unavailable)
    // The class methods are their own answer, asked after the instance ones.
    #expect(index.outgoingSignature(selector: "go:", className: "C", isClassMethod: true)
        == .known(encoding: "d@:d", types: ["d"]))
    #expect(index.outgoingSignature(selector: "go:", className: "C", isClassMethod: false) == .unavailable)
    #expect(index.outgoingSignature(selector: "go:", className: "A", isClassMethod: true) == .unavailable)
    // One implementation that returns a value denies every void.
    #expect(!index.outgoingReturnsVoid(selector: "go:", className: "B", isClassMethod: false))
    let void = ObjCMetadataIndex(methods: [1: [binding("A", "v@:q")], 2: [binding("B", "v@:q")]], fieldMaps: [:])
    #expect(void.outgoingReturnsVoid(selector: "go:", className: "B", isClassMethod: false))
    #expect(!void.outgoingReturnsVoid(selector: "go:", className: "Z", isClassMethod: false))
    #expect(!void.outgoingReturnsVoid(selector: "go:", className: "B", isClassMethod: true))
}

@Test func aSelectorWhoseDeclarationsDisagreeIsDeclined() {
    let index = ObjCMetadataIndex(methods: [1: [binding("A", "v@:q")], 2: [binding("B", "v@:d")]], fieldMaps: [:])
    #expect(index.outgoingSignature(selector: "go:", className: "A", isClassMethod: false) == .declined)
    #expect(index.outgoingSignature(selector: "go:", className: "B", isClassMethod: false) == .declined)
}

/// The positional prefix is per selector, and nil is an answer to keep.
@Test func thePositionalPrefixIsAnsweredPerSelector() {
    let index = ObjCMetadataIndex(methods: [
        1: [binding("A", "v@:qd", selector: "mixed::")],
        2: [binding("A", "v@:qq", selector: "plain::")],
    ], fieldMaps: [:])
    for _ in 0 ..< 2 {
        #expect(index.positionalArgumentPrefix("mixed::") == 1)
        #expect(index.positionalArgumentPrefix("plain::") == nil)
    }
}

/// Instructions retired, which load does not change, for 100 and 800
/// classes: one answer per selector grows with the classes, and parsing
/// every implementation at every send with their square.
@Test func objcWorkGrowsWithTheClassesNotTheirSquareIfPresent() throws {
    let cli = URL(fileURLWithPath: ".build/debug/swiftdc")
    func retired(_ path: String) throws -> Double? {
        guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: cli.path) else { return nil }
        let process = Process(), err = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
        process.arguments = ["-l", cli.path, "objc", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = err
        try process.run()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: stderr, as: UTF8.self).split(separator: "\n").lazy.compactMap { line -> Double? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix("instructions retired") else { return nil }
            return Double(trimmed.split(separator: " ").first ?? "")
        }.first
    }
    guard let few = try retired("Fixtures/Sample/libManyAccessors100.dylib"),
          let many = try retired("Fixtures/Sample/libManyAccessors800.dylib")
    else { return }
    #expect(many / few < sendWorkGrowthCeiling, "8x the classes cost \(many / few)x the instructions")
}

/// 8x the classes measured 7.7x the instructions in debug, 7.4x in release,
/// and 13.8x in release when every send parsed every implementation.
private let sendWorkGrowthCeiling = 10.0
