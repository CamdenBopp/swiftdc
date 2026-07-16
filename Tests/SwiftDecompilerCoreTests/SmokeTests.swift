import Testing
import Foundation
import Dependencies
@_spi(Internals) import MachOSwiftSection  // re-exports MachOSymbols → SymbolIndexStore
@testable import SwiftDecompilerCore

/// Runs `operation` with `\.symbolIndexStore` pre-seeded into DependencyValues.
///
/// Deep in SwiftDump/SwiftInterface, dumping and disassembly read
/// `@Dependency(\.symbolIndexStore)`. Under swift-testing, resolving that
/// dependency through swift-dependencies' *cached* path builds a per-test
/// `CachedValues.CacheKey`, which reads swift-testing's current `Test.ID` via
/// `String(reflecting:)` — a type-name reflection that segfaults on the current
/// toolchain (`objc_class::demangledName`, EXC_BAD_ACCESS at 0x3). The crash is
/// pre-existing and independent of the MachOSwiftSection version; the CLI never
/// links swift-testing, so it is unaffected.
///
/// Providing the value here writes it straight into `DependencyValues.storage`,
/// so the getter returns it directly — `DependencyValues.subscript` short-
/// circuits before ever building a `CacheKey` (and thus never reflects). The
/// live and test values are both `.shared`, so this is the exact instance
/// production uses: no behavior change, just no crash. Covers every access in
/// the scoped call, including `SwiftInterfaceIndexer.deinit`.
func withStableDependencies<R>(
    isolation: isolated (any Actor)? = #isolation,
    _ operation: () async throws -> R
) async rethrows -> R {
    try await withDependencies(
        isolation: isolation,
        { $0.symbolIndexStore = .shared },
        operation: operation
    )
}

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

/// Both `objc_msgSend` dispatch shapes fold into bracket syntax.
@Test func rendersMessageSends() {
    // Modern: per-selector stub, selector in the callee's name. x1 is `_cmd`
    // (junk at the call site, since the stub sets it), so args start at x2.
    let stub = DisassembledFunction.MessageSend(
        callee: "objc_msgSend$setBool:forKey:",
        arguments: ["NSUserDefaults", "?", "1", "@\"k\""]
    )
    #expect(stub?.rendered == "[NSUserDefaults setBool:1 forKey:@\"k\"]")

    // Classic: selector materialised into x1 at the call site.
    let classic = DisassembledFunction.MessageSend(
        callee: "objc_msgSend",
        arguments: ["view", "@selector(setTitle:)", "@\"hi\""]
    )
    #expect(classic?.rendered == "[view setTitle:@\"hi\"]")

    // Zero-argument selector takes no colon.
    #expect(
        DisassembledFunction.MessageSend(callee: "objc_msgSend$reload", arguments: ["table"])?
            .rendered == "[table reload]"
    )
    // A send to super names the receiver `super`, not x0.
    #expect(
        DisassembledFunction.MessageSend(callee: "objc_msgSendSuper2$init", arguments: ["x"])?
            .rendered == "[super init]"
    )
    // Missing arguments stay honest rather than being dropped.
    #expect(
        DisassembledFunction.MessageSend(callee: "objc_msgSend$a:b:", arguments: [])?
            .rendered == "[? a:? b:?]"
    )
    // Not a message send.
    #expect(DisassembledFunction.MessageSend(callee: "swift_allocObject", arguments: ["x"]) == nil)
    // objc_msgSend with no recoverable selector: don't invent bracket syntax.
    #expect(DisassembledFunction.MessageSend(callee: "objc_msgSend", arguments: ["x", "?"]) == nil)
}

/// A value stored to a stack slot is recovered when reloaded — and survives the
/// prologue moving `sp` underneath it, which is what makes ObjC receivers and
/// Swift `self` resolvable at all.
@Test func tracksStackSlotsAcrossFrameAdjustments() {
    func insn(_ address: UInt64, _ text: String, _ flow: ControlFlow = .sequential) -> Instruction {
        Instruction(address: address, text: text, controlFlow: flow, branchTarget: flow == .call ? 0x2000 : nil)
    }
    // The slot is written at sp+8 and read back at sp+8, but `sp` moves twice
    // between entry and the store — via pre-index writeback, then a plain sub.
    // Both stores land at frame offset -0x28, which is the point of the model.
    let function = DisassembledFunction(
        symbol: "_$stest", demangledName: "test", startAddress: 0x1000,
        instructions: [
            insn(0x1000, "stp\tx29, x30, [sp, #-0x20]!"), // sp = frame-0x20
            insn(0x1004, "sub\tsp, sp, #0x10"),           // sp = frame-0x30
            insn(0x1008, "movz\tx0, #0x2a"),
            insn(0x100c, "str\tx0, [sp, #0x8]"),          // stack@-0x28 = 42
            insn(0x1010, "ldr\tx20, [sp, #0x8]"),         // x20 = 42
            insn(0x1014, "bl\t0x2000", .call),
        ],
        source: .symbol
    )
    let site = ValueTracer().callSites(in: function)[0x1014]
    #expect(site?.arguments.first == .immediate(42))
    // x20 was written by the `ldr` immediately before the call, so it counts as
    // this call's `self`.
    #expect(site?.selfValue == .immediate(42))
}

/// x20 is callee-saved, so a value set up for one call survives into the next.
/// Only a *fresh* write counts as `self`, or a Swift callee whose self isn't in
/// x20 at all inherits the previous call's receiver.
@Test func staleSwiftSelfIsNotReported() {
    func insn(_ address: UInt64, _ text: String, _ flow: ControlFlow = .sequential) -> Instruction {
        Instruction(address: address, text: text, controlFlow: flow, branchTarget: flow == .call ? 0x2000 : nil)
    }
    let function = DisassembledFunction(
        symbol: "_$stest", demangledName: "test", startAddress: 0x1000,
        instructions: [
            insn(0x1000, "movz\tx20, #0x7"),
            insn(0x1004, "bl\t0x2000", .call), // self=7: x20 freshly written
            insn(0x1008, "bl\t0x2000", .call), // x20 still 7, but stale now
        ],
        source: .symbol
    )
    let sites = ValueTracer().callSites(in: function)
    #expect(sites[0x1004]?.selfValue == .immediate(7))
    #expect(sites[0x1008]?.selfValue == .unknown)
}

/// Swift-mangled symbols use the Swift calling convention (self in x20); C and
/// ObjC ones don't, and must not have x20 reported as `self`.
@Test func detectsSwiftMangling() {
    #expect(Disassembler.isSwiftMangled("_$sSS6appendyySSF"))
    #expect(Disassembler.isSwiftMangled("$s6sample3DogC4barkyyF"))
    #expect(Disassembler.isSwiftMangled("_$S6legacy3FooV"))     // pre-5.0 mangling
    #expect(!Disassembler.isSwiftMangled("_objc_msgSend"))
    #expect(!Disassembler.isSwiftMangled("_malloc"))
    #expect(!Disassembler.isSwiftMangled(""))
}

@Test func ownerNameParsing() {
    #expect(AnalysisReport.ownerName(of: "sample.Point.distance(to:) -> Swift.Double") == "sample.Point")
    #expect(AnalysisReport.ownerName(of: "Point.area.getter : Swift.Double") == "Point")
    #expect(AnalysisReport.ownerName(of: "Point.x.setter : Swift.Double") == "Point")
    #expect(AnalysisReport.ownerName(of: "sample.run() -> ()") == "sample")
}

/// The dyld-shared-cache loader lists images and resolves a system framework by
/// name. Skips where there's no host cache (some CI/sandboxes). Only exercises
/// the loader (fast) — not a full metadata dump of a huge framework.
@Test func listsAndFindsDyldCacheImagesIfAvailable() throws {
    let paths: [String]
    do {
        paths = try BinaryLoader.dyldCacheImagePaths(cachePath: nil)
    } catch {
        return // no host dyld shared cache on this system
    }
    #expect(!paths.isEmpty)
    #expect(paths.contains { $0.hasSuffix("/Foundation") })
    // A known image resolves by name without throwing (returns a cache MachOFile).
    _ = try BinaryLoader.loadFromDyldCache(cachePath: nil, selector: .name("libswiftCore"))
    // A bogus name surfaces a clear error rather than crashing.
    #expect(throws: (any Error).self) {
        _ = try BinaryLoader.loadFromDyldCache(cachePath: nil, selector: .name("NoSuchImage_ZZZ"))
    }
}

/// Integration check that runs only when the compiled fixture is present
/// (build it with `Fixtures/Sample/build.sh`). Keeps `swift test` green on a
/// clean checkout while still exercising the real pipeline in dev.
@Test func dumpsFixtureTypesIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let text = await withStableDependencies {
        await SwiftDeclarationDumper(preset: .simplified).dump(machO, sections: [.types])
    }
    #expect(text.contains("struct Point"))
    #expect(text.contains("enum Direction"))
    #expect(text.contains("class Dog: Animal"))
}

/// The SwiftInterface-backed reconstructor emits real Swift interface syntax —
/// generics with constraints, computed properties, enum cases — a higher
/// fidelity than the flat declaration dump.
@Test func reconstructsInterfaceIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let interface = try await withStableDependencies {
        try await InterfaceReconstructor().reconstruct(machO)
    }
    #expect(interface.contains("struct Point {"))
    #expect(interface.contains("var x: Swift.Double"))
    #expect(interface.contains("func distance(to: sample.Point) -> Swift.Double"))
    #expect(interface.contains("enum Direction {"))
    #expect(interface.contains("case north"))
    // A generic function reconstructed with its constraint clause.
    #expect(interface.contains("where"))
    #expect(interface.contains("Comparable"))
}

/// A `.app`/`.framework` bundle resolves to its main executable, lists its
/// embedded binaries, and selects one by name — so you can point swiftdc at an
/// app instead of digging out the binary first.
@Test func resolvesBundleInputIfFixturePresent() throws {
    let fixture = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let fm = FileManager.default

    // Throwaway iOS-layout .app (binary at bundle root) with an embedded framework.
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("swiftdc-bundle-\(UUID().uuidString)")
    let app = root.appendingPathComponent("MyApp.app")
    let framework = app.appendingPathComponent("Frameworks/SampleKit.framework")
    try fm.createDirectory(at: framework, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try fm.copyItem(atPath: fixture, toPath: app.appendingPathComponent("MyApp").path)
    try fm.copyItem(atPath: fixture, toPath: framework.appendingPathComponent("SampleKit").path)
    try #"<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>MyApp</string></dict></plist>"#
        .write(to: app.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

    // Default → the main executable.
    #expect(try BinaryLoader.resolveBinaryInput(app.path).hasSuffix("MyApp.app/MyApp"))
    // --binary → the named embedded framework.
    #expect(try BinaryLoader.resolveBinaryInput(app.path, binary: "SampleKit").hasSuffix("SampleKit.framework/SampleKit"))
    // Listing surfaces both, tagged by kind.
    let listed = try BinaryLoader.binaries(in: app.path)
    #expect(listed.contains { $0.name == "MyApp" && $0.kind == .executable })
    #expect(listed.contains { $0.name == "SampleKit" && $0.kind == .framework })
}

/// Stripped binaries lose their symbol table, but LC_FUNCTION_STARTS + Swift
/// metadata let us re-delimit and (partly) name functions anyway.
@Test func recoversStrippedFunctionsIfPresent() async throws {
    let path = "Fixtures/Sample/sample.stripped"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
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
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
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
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
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
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
    let argLists = functions.flatMap(\.instructions).compactMap(\.callArguments)
    #expect(!argLists.isEmpty)
    // swift_allocObject(metadata, size, alignMask=7): a 3-arg call ending in "7".
    #expect(argLists.contains { $0.count == 3 && $0.last == "7" })
}

/// The pseudo view renders recovered call statements and hides ARC noise.
@Test func rendersPseudocodeIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
    let speak = try #require(functions.first { $0.demangledName == "Dog.speak()" })
    let pseudo = speak.renderPseudo()
    #expect(pseudo.hasPrefix("Dog.speak() {"))
    #expect(pseudo.contains("String.append"))
    #expect(!pseudo.contains("swift_release")) // runtime noise hidden
    // Signature isn't doubled with the recovered args.
    #expect(!pseudo.contains("(_:)("))
}

/// Structured view folds the CFG into if/else with recovered conditions.
@Test func structuresControlFlowIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
    let tree = try #require(functions.first { $0.demangledName == "Tree.sum()" })
    let structured = tree.renderStructured()
    #expect(structured.contains("if ("))
    #expect(structured.contains("} else {"))
    #expect(structured.contains("return"))
    // Conditions are reconstructed (back-substituted), not bare temp registers.
    #expect(structured.contains("& 0xff"))
    // Trivial tails are duplicated: both inner branches are non-empty.
    #expect(structured.contains("trap()"))
    // Never emits structurally broken output.
    #expect(structured.filter { $0 == "{" }.count == structured.filter { $0 == "}" }.count)
}

/// Reducible loops fold into `while (true) { … break/continue }`.
@Test func foldsLoopsIntoWhileIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
    guard let loop = functions.first(where: { ($0.demangledName ?? "").hasPrefix("countMatches") })
    else { return }
    let structured = loop.renderStructured()
    #expect(structured.contains("while (true)"))
    #expect(structured.contains("continue") || structured.contains("break"))
    #expect(structured.filter { $0 == "{" }.count == structured.filter { $0 == "}" }.count)
}

/// disasm JSON output parses and carries the expected fields.
@Test func emitsValidJSONIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
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
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
    let arguments = functions.flatMap(\.instructions).compactMap(\.callArguments).flatMap { $0 }
    // At least one argument is itself a recovered call expression (has nesting).
    #expect(arguments.contains { $0.contains("(") && $0.contains(")") })
}

/// Small-string literal arguments decode to quoted text in the recovered args.
@Test func decodesSmallStringArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
    let arguments = functions.flatMap(\.instructions).compactMap(\.callArguments).flatMap { $0 }
    // e.g. Dog.speak()'s " the ", Rectangle.describe()'s "Rect "/"x", Dog("Rex","Lab").
    #expect(arguments.contains { $0 == "\" the \"" || $0 == "\"Rect \"" || $0 == "\"Rex\"" })
}

/// The in-process Capstone front-end (`disassemble(machO:)`) recovers the same
/// functions as the llvm-objdump front-end — same `__text`, same
/// `LC_FUNCTION_STARTS`. This is the path that lets `disasm` read dyld-cache
/// images, which have no standalone file for llvm-objdump.
@Test func inProcessDisasmMatchesObjdumpIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }

    let objdump = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
    let machO = try BinaryLoader.load(path: path)
    let inProcess = await withStableDependencies {
        await Disassembler(preset: .simplified).disassemble(machO: machO)
    }
    #expect(!inProcess.isEmpty)

    // Same key function at the same address with the same instruction count.
    let objTree = try #require(objdump.first { $0.demangledName == "Tree.sum()" })
    let ipTree = try #require(inProcess.first { $0.demangledName == "Tree.sum()" })
    #expect(objTree.startAddress == ipTree.startAddress)
    #expect(objTree.instructions.count == ipTree.instructions.count)
    // Capstone gives control flow directly.
    #expect(ipTree.instructions.contains { $0.controlFlow == .call })
    #expect(ipTree.instructions.contains { $0.controlFlow == .return })
    // adrp adaptation + value tracking survive the Capstone text format.
    #expect(inProcess.flatMap(\.instructions).contains { $0.callArguments != nil })
    // Direct within-image call/branch targets are resolved to names (Tree.sum
    // recurses), so the in-process listing isn't just bare `bl #0x…`.
    #expect(inProcess.flatMap(\.instructions).contains { ($0.annotation ?? "").hasPrefix("→") })
}

/// A filtered disasm decodes only the matched function's slice of __text, and
/// must recover that function *identically* to a whole-binary decode — same
/// address, same instructions.
@Test func filteredDisasmMatchesUnfilteredIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let all = await withStableDependencies {
        await Disassembler(preset: .simplified).disassemble(machO: machO)
    }
    let filtered = await withStableDependencies {
        await Disassembler(preset: .simplified).disassemble(machO: machO, functionFilter: "Tree.sum")
    }
    let whole = try #require(all.first { $0.demangledName == "Tree.sum()" })
    let sliced = try #require(filtered.first { $0.demangledName == "Tree.sum()" })
    #expect(sliced.startAddress == whole.startAddress)
    #expect(sliced.instructions.map(\.address) == whole.instructions.map(\.address))
    #expect(sliced.instructions.map(\.text) == whole.instructions.map(\.text))
    // A filter matching nothing returns empty, not everything.
    let none = await withStableDependencies {
        await Disassembler(preset: .simplified).disassemble(machO: machO, functionFilter: "NoSuchFunctionZZZ")
    }
    #expect(none.isEmpty)
}
