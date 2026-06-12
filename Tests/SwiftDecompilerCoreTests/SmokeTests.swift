import Testing
import Foundation
@testable import SwiftDecompilerCore

@Test func versionIsSet() {
    #expect(SwiftDecompiler.version == "0.0.1")
}

/// Capstone decodes ARM64 and classifies control flow.
@Test func capstoneDecodesARM64() throws {
    let engine = try #require(CapstoneEngine())
    // ret = c0 03 5f d6 ; nop = 1f 20 03 d5 ; bl #0x100c (delta +0x8) = 02 00 00 94
    let bytes = Data([0xc0, 0x03, 0x5f, 0xd6, 0x1f, 0x20, 0x03, 0xd5, 0x02, 0x00, 0x00, 0x94])
    let insns = engine.disassemble(bytes, address: 0x1000)
    #expect(insns.count == 3)
    #expect(insns[0].mnemonic == "ret")
    #expect(insns[0].controlFlow == .return)
    #expect(insns[1].mnemonic == "nop")
    #expect(insns[1].controlFlow == .sequential)
    #expect(insns[2].mnemonic == "bl")
    #expect(insns[2].controlFlow == .call)
    #expect(insns[2].branchTarget == 0x1010)
}

/// Swift _SmallString decoding from its two-register encoding.
@Test func decodesSmallString() {
    // " the " = UTF-8 20 74 68 65 20, count 5, discriminator 0xE5.
    #expect(ValueTracer.decodeSmallString(lo: 0x0000002065687420, hi: 0xe500000000000000) == " the ")
    #expect(ValueTracer.decodeSmallString(lo: 0, hi: 0) == nil)                 // not a small string
    #expect(ValueTracer.decodeSmallString(lo: 0xff, hi: 0xe100000000000000) == nil) // non-printable
}

@Test func ownerNameParsing() {
    #expect(AnalysisReport.ownerName(of: "sample.Point.distance(to:) -> Swift.Double") == "sample.Point")
    #expect(AnalysisReport.ownerName(of: "Point.area.getter : Swift.Double") == "Point")
    #expect(AnalysisReport.ownerName(of: "Point.x.setter : Swift.Double") == "Point")
    #expect(AnalysisReport.ownerName(of: "sample.run() -> ()") == "sample")
}

/// Integration check that runs only when the compiled fixture is present
/// (build it with `Fixtures/Sample/build.sh`). Keeps `swift test` green on a
/// clean checkout while still exercising the real pipeline in dev.
@Test func dumpsFixtureTypesIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let text = await SwiftDeclarationDumper(preset: .simplified).dump(machO, sections: [.types])
    #expect(text.contains("struct Point"))
    #expect(text.contains("enum Direction"))
    #expect(text.contains("class Dog: Animal"))
}

/// Stripped binaries lose their symbol table, but LC_FUNCTION_STARTS + Swift
/// metadata let us re-delimit and (partly) name functions anyway.
@Test func recoversStrippedFunctionsIfPresent() async throws {
    let path = "Fixtures/Sample/sample.stripped"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await Disassembler(preset: .simplified).disassemble(path: path)
    // Re-segmented into many functions, not collapsed into one `_main` blob.
    #expect(functions.count > 50)
    // At least one function name was recovered from Swift metadata.
    #expect(functions.contains { $0.source == .metadata })
    #expect(functions.contains { ($0.demangledName ?? "").hasPrefix("Animal") })
    // A protocol-conformance witness was named (`<Type>: <Protocol>.<kind>`).
    #expect(functions.contains { ($0.demangledName ?? "").contains(": Shape") })

    // Correctness: the `Rectangle: Shape` area witness is `width * height`,
    // i.e. a double multiply. Guards against a bad witness-address calculation.
    if let areaWitness = functions.first(where: { $0.demangledName == "Rectangle: Shape.getter" }) {
        #expect(areaWitness.instructions.contains { $0.text.hasPrefix("fmul") })
    }
}

/// adrp/add operand references resolve to function/type-descriptor names.
@Test func annotatesOperandReferencesIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await Disassembler(preset: .simplified).disassemble(path: path)
    let annotations = functions.flatMap(\.instructions).compactMap(\.annotation)
    #expect(annotations.contains { $0.contains("→") })
    #expect(annotations.contains { $0.contains("type descriptor for") })
}

/// Objective-C headers are reconstructed from ObjC runtime metadata.
@Test func dumpsObjCHeadersIfPresent() throws {
    let path = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let text = ObjCDumper().dump(machO)
    #expect(text.contains("@interface SDWidget"))
    #expect(text.contains("ping"))
}

/// Capstone enrichment yields control-flow classification and basic blocks.
@Test func recoversBasicBlocksIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await Disassembler(preset: .simplified).disassemble(path: path)
    let tree = try #require(functions.first { $0.demangledName == "Tree.sum()" })
    // Control flow is classified by Capstone.
    #expect(tree.instructions.contains { $0.controlFlow == .call })
    #expect(tree.instructions.contains { $0.controlFlow == .return })
    // CFG: condition / recursive-case / ret (/ trap) → multiple blocks.
    let blocks = tree.basicBlocks()
    #expect(blocks.count >= 3)
    #expect(blocks.first?.successors.count == 2) // entry ends in a conditional branch
}

/// Value tracking recovers concrete call arguments (constants/addresses).
@Test func recoversCallArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await Disassembler(preset: .simplified).disassemble(path: path)
    let argLists = functions.flatMap(\.instructions).compactMap(\.callArguments)
    #expect(!argLists.isEmpty)
    // swift_allocObject(metadata, size, alignMask=7): a 3-arg call ending in "7".
    #expect(argLists.contains { $0.count == 3 && $0.last == "7" })
}

/// The pseudo view renders recovered call statements and hides ARC noise.
@Test func rendersPseudocodeIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await Disassembler(preset: .simplified).disassemble(path: path)
    let speak = try #require(functions.first { $0.demangledName == "Dog.speak()" })
    let pseudo = speak.renderPseudo()
    #expect(pseudo.hasPrefix("Dog.speak() {"))
    #expect(pseudo.contains("String.append"))
    #expect(!pseudo.contains("swift_release")) // runtime noise hidden
    // Signature isn't doubled with the recovered args.
    #expect(!pseudo.contains("(_:)("))
}

/// disasm JSON output parses and carries the expected fields.
@Test func emitsValidJSONIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await Disassembler(preset: .simplified).disassemble(path: path)
    let parsed = try JSONSerialization.jsonObject(with: Data(functions.jsonString().utf8))
    let array = try #require(parsed as? [[String: Any]])
    #expect(!array.isEmpty)
    #expect(array.first?["address"] is String)
    #expect(array.first?["instructions"] is [Any])
}

/// A call's return value flows into a later call's argument as a nested
/// expression (e.g. `Hasher._finalize(Hasher._combine())`).
@Test func threadsCallResultsIntoArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await Disassembler(preset: .simplified).disassemble(path: path)
    let arguments = functions.flatMap(\.instructions).compactMap(\.callArguments).flatMap { $0 }
    // At least one argument is itself a recovered call expression (has nesting).
    #expect(arguments.contains { $0.contains("(") && $0.contains(")") })
}

/// Small-string literal arguments decode to quoted text in the recovered args.
@Test func decodesSmallStringArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await Disassembler(preset: .simplified).disassemble(path: path)
    let arguments = functions.flatMap(\.instructions).compactMap(\.callArguments).flatMap { $0 }
    // e.g. Dog.speak()'s " the ", Rectangle.describe()'s "Rect "/"x", Dog("Rex","Lab").
    #expect(arguments.contains { $0 == "\" the \"" || $0 == "\"Rect \"" || $0 == "\"Rex\"" })
}
