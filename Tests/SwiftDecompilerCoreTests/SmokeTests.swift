import Testing
import Foundation
import Dependencies
import CCapstone
@_spi(Internals) import MachOSwiftSection  // re-exports MachOSymbols → SymbolIndexStore
@testable import SwiftDecompilerCore

private func operand(_ value: StructuredOperand) -> StructuredOperandInfo {
    StructuredOperandInfo(
        operand: value,
        shift: (ARM64_SFT_INVALID, 0),
        extender: ARM64_EXT_INVALID
    )
}

private func detail(_ id: arm64_insn, _ operands: [StructuredOperandInfo]) -> StructuredInsn {
    StructuredInsn(
        id: id, conditionCode: ARM64_CC_INVALID, updatesFlags: false,
        writeback: false, postIndex: false, operands: operands
    )
}

@Test func recognizesCacheGlobalObjectiveCSelectorStubs() {
    let x1 = PhysReg(kind: .gpr, number: 1, widthBits: 64)
    let instructions = [
        Instruction(
            address: 0x1000, text: "adrp x1, 0x2000",
            detail: detail(ARM64_INS_ADRP, [operand(.register(x1)), operand(.immediate(0x2000))])
        ),
        Instruction(
            address: 0x1004, text: "add x1, x1, #0x118",
            detail: detail(ARM64_INS_ADD, [
                operand(.register(x1)), operand(.register(x1)), operand(.immediate(0x118)),
            ])
        ),
        Instruction(
            address: 0x1008, text: "b 0x3000", controlFlow: .branch,
            branchTarget: 0x3000
        ),
    ]
    // Deliberately exceed the old 256-byte cache string read limit.
    let selector = "init" + (0..<30).map { "WithField\($0):" }.joined()
    #expect(selector.count > 256)
    #expect(CacheSymbolResolver.selectorStubName(
        in: instructions,
        selectorText: { $0 == 0x2118 ? selector : nil },
        dispatcherName: { $0 == 0x3000 ? "_objc_msgSend" : nil }
    ) == "objc_msgSend$\(selector)")
    #expect(CacheSymbolResolver.selectorStubName(
        in: instructions,
        selectorText: { _ in selector },
        dispatcherName: { _ in "_not_a_dispatcher" }
    ) == nil)
}

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
    #expect(
        DisassembledFunction.MessageSend(
            callee: "objc_msgSend$stringWithFormat:",
            arguments: ["NSString", "?", "@\"%ld\"", "self->_count"]
        )?.rendered == "[NSString stringWithFormat:@\"%ld\", self->_count]"
    )
    // Not a message send.
    #expect(DisassembledFunction.MessageSend(callee: "swift_allocObject", arguments: ["x"]) == nil)
    // objc_msgSend with no recoverable selector: don't invent bracket syntax.
    #expect(DisassembledFunction.MessageSend(callee: "objc_msgSend", arguments: ["x", "?"]) == nil)
}

/// Build a function from real machine code. These used to be hand-written
/// instruction *text*, which only ever exercised the old string parser; value
/// tracking now reads Capstone's structured operands, so the bytes are the input
/// that matters. They are assembled by clang, not hand-encoded.
private func assembledFunction(
    _ bytes: [UInt8],
    at address: UInt64 = 0x1000,
    symbol: String = "_$stest"
) -> DisassembledFunction? {
    guard let engine = CapstoneEngine() else { return nil }
    let instructions = engine.disassemble(Data(bytes), address: address).map {
        Instruction(
            address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
            branchTarget: $0.branchTarget, detail: $0.detail
        )
    }
    return DisassembledFunction(
        symbol: symbol, demangledName: "test", startAddress: address,
        instructions: instructions, source: .symbol
    )
}

/// A value stored to a stack slot is recovered when reloaded — and survives the
/// prologue moving `sp` underneath it, which is what makes ObjC receivers and
/// Swift `self` resolvable at all.
@Test func tracksStackSlotsAcrossFrameAdjustments() throws {
    //   stp  x29, x30, [sp, #-0x20]!   sp = frame-0x20  (pre-index writeback)
    //   sub  sp, sp, #0x10             sp = frame-0x30
    //   mov  x0, #0x2a
    //   str  x0, [sp, #0x8]            stack@-0x28 = 42
    //   ldr  x20, [sp, #0x8]           x20 = 42
    //   bl   L
    // L: ret
    // The slot is written and read at the same `sp+8`, but sp moves twice before
    // the store — the frame model is what keeps both at frame offset -0x28.
    let function = try #require(assembledFunction([
        0xfd, 0x7b, 0xbe, 0xa9,
        0xff, 0x43, 0x00, 0xd1,
        0x40, 0x05, 0x80, 0xd2,
        0xe0, 0x07, 0x00, 0xf9,
        0xf4, 0x07, 0x40, 0xf9,
        0x01, 0x00, 0x00, 0x94,
        0xc0, 0x03, 0x5f, 0xd6,
    ]))
    let site = try #require(ValueTracer().callSites(in: function)[0x1014])
    #expect(site.arguments.first == .immediate(42))
    // x20 was written by the `ldr` immediately before the call, so it counts as
    // this call's `self`.
    #expect(site.selfValue == .immediate(42))
}

/// The value tracer preserves the provenance of a register-indirect call target
/// without claiming that the loaded slot is executable. Mach-O enrichment makes
/// that second, stricter determination from fixups and the function index.
@Test func tracksIndirectCallTargetProvenance() throws {
    let x8 = PhysReg(kind: .gpr, number: 8, widthBits: 64)
    let x23 = PhysReg(kind: .gpr, number: 23, widthBits: 64)
    let function = DisassembledFunction(
        symbol: "_$stest", demangledName: "test", startAddress: 0x1000,
        instructions: [
            Instruction(
                address: 0x1000, text: "adrp x23, 0x8000",
                detail: detail(ARM64_INS_ADRP, [operand(.register(x23)), operand(.immediate(0x8000))])
            ),
            Instruction(
                address: 0x1004, text: "add x23, x23, #0xc0",
                detail: detail(ARM64_INS_ADD, [
                    operand(.register(x23)), operand(.register(x23)), operand(.immediate(0xc0)),
                ])
            ),
            Instruction(
                address: 0x1008, text: "ldr x8, [x23, #8]",
                detail: detail(ARM64_INS_LDR, [
                    operand(.register(x8)),
                    operand(.memory(base: x23, index: nil, displacement: 8)),
                ])
            ),
            Instruction(
                address: 0x100c, text: "blr x8", controlFlow: .call,
                detail: detail(ARM64_INS_BLR, [operand(.register(x8))])
            ),
        ],
        source: .symbol
    )

    let analysis = ValueTracer().analyze(function)
    #expect(analysis.indirectControlFlowTargets[0x100c] == .loaded(0x80c8))
}

/// Values placed in the AAPCS64 outgoing stack area are retained separately
/// from x0...x7. Objective-C variadic message sends use this path even when
/// their fixed receiver, selector, and format arguments all fit in registers.
@Test func tracksOutgoingStackArguments() throws {
    //   sub  sp, sp, #0x20
    //   mov  x9, #0x2a
    //   str  x9, [sp]
    //   bl   L
    // L: ret
    let function = try #require(assembledFunction([
        0xff, 0x83, 0x00, 0xd1,
        0x49, 0x05, 0x80, 0xd2,
        0xe9, 0x03, 0x00, 0xf9,
        0x01, 0x00, 0x00, 0x94,
        0xc0, 0x03, 0x5f, 0xd6,
    ]))
    let site = try #require(ValueTracer().callSites(in: function)[0x100c])
    #expect(site.stackArguments == [.immediate(42)])
}

/// Pair operations retain both halves: optimized Objective-C initializers use
/// `ldp` for entry-stack arguments and `stp` for adjacent ivar assignments.
@Test func tracksPairedObjectiveCValues() throws {
    //   ldp x9, x10, [sp]
    //   mov x0, x9
    //   mov x1, x10
    //   bl  L
    // L: ret
    let loads = try #require(assembledFunction([
        0xe9, 0x2b, 0x40, 0xa9,
        0xe0, 0x03, 0x09, 0xaa,
        0xe1, 0x03, 0x0a, 0xaa,
        0x01, 0x00, 0x00, 0x94,
        0xc0, 0x03, 0x5f, 0xd6,
    ]))
    let loadSite = try #require(ValueTracer().analyze(
        loads, entry: .objectiveC(argumentCount: 8)
    ).callSites[0x100c])
    #expect(loadSite.arguments.prefix(2).elementsEqual([.argument(6), .argument(7)]))

    // stp x2, x3, [x0, #8] ; ret
    let stores = try #require(assembledFunction([
        0x02, 0x8c, 0x00, 0xa9,
        0xc0, 0x03, 0x5f, 0xd6,
    ]))
    let access = try #require(ValueTracer().analyze(
        stores, entry: .objectiveC(argumentCount: 2)
    ).selfFieldAccesses[0x1000])
    #expect(access.offset == 8)
    #expect(access.bytes == 16)
    #expect(access.storedValues == [.argument(0), .argument(1)])
}

@Test func tracksObjectiveCStackArgumentsThroughSIMDRegisters() throws {
    let q0 = PhysReg(kind: .vector, number: 0, widthBits: 128)
    let q1 = PhysReg(kind: .vector, number: 1, widthBits: 128)
    let sp = PhysReg(kind: .stackPointer, number: 31, widthBits: 64)
    let memory = operand(.memory(base: sp, index: nil, displacement: 0))
    let function = DisassembledFunction(
        symbol: "_simd_args", demangledName: nil, startAddress: 0x1000,
        instructions: [
            Instruction(
                address: 0x1000, text: "ldp q0, q1, [sp]",
                detail: detail(ARM64_INS_LDP, [operand(.register(q0)), operand(.register(q1)), memory])
            ),
            Instruction(
                address: 0x1004, text: "stp q0, q1, [sp]",
                detail: detail(ARM64_INS_STP, [operand(.register(q0)), operand(.register(q1)), memory])
            ),
            Instruction(
                address: 0x1008, text: "bl 0x2000", controlFlow: .call,
                branchTarget: 0x2000
            ),
            Instruction(address: 0x100c, text: "ret", controlFlow: .return),
        ],
        source: .symbol
    )
    let site = try #require(ValueTracer().analyze(
        function, entry: .objectiveC(argumentCount: 10)
    ).callSites[0x1008])
    #expect(site.stackArguments == [
        .argument(6), .argument(7), .argument(8), .argument(9),
    ])
}

/// x20 is callee-saved, so a value set up for one call survives into the next.
/// Only a *fresh* write counts as `self`, or a Swift callee whose self isn't in
/// x20 at all inherits the previous call's receiver.
@Test func staleSwiftSelfIsNotReported() throws {
    //   mov x20, #0x7
    //   bl  L        <- self=7: x20 freshly written
    //   bl  L        <- x20 still holds 7, but it is stale now
    // L: ret
    let function = try #require(assembledFunction([
        0xf4, 0x00, 0x80, 0xd2,
        0x02, 0x00, 0x00, 0x94,
        0x01, 0x00, 0x00, 0x94,
        0xc0, 0x03, 0x5f, 0xd6,
    ]))
    let sites = ValueTracer().callSites(in: function)
    #expect(sites[0x1004]?.selfValue == .immediate(7))
    #expect(sites[0x1008]?.selfValue == .unknown)
}

/// The shifted-immediate fix, end to end through the tracker.
///
/// `sub sp, sp, #0x2, lsl #12` moves sp by 8192. The old text path read the
/// immediate and dropped the `lsl #12`, yielding a frame — and every local
/// offset in it — wrong by 4096x, and two distinct slots could collide on one
/// key.
@Test func tracksShiftedFrameAdjustment() throws {
    //   sub  sp, sp, #0x2, lsl #12     sp = frame-0x2000
    //   mov  x0, #0x2a
    //   str  x0, [sp, #0x8]            stack@-0x1ff8
    //   ldr  x1, [sp, #0x8]
    //   bl   L
    // L: ret
    let function = try #require(assembledFunction([
        0xff, 0x0b, 0x40, 0xd1,
        0x40, 0x05, 0x80, 0xd2,
        0xe0, 0x07, 0x00, 0xf9,
        0xe1, 0x07, 0x40, 0xf9,
        0x01, 0x00, 0x00, 0x94,
        0xc0, 0x03, 0x5f, 0xd6,
    ]))
    let site = try #require(ValueTracer().callSites(in: function)[0x1010])
    // Reached only if sp moved by 8192 on both the store and the load.
    #expect(site.arguments.count >= 2)
    #expect(site.arguments[1] == .immediate(42))
}

/// An atomic must clobber what it writes.
///
/// `ldaddal x1, x0, [x2]` writes **x0**, but Capstone reports no accesses at all
/// for it — `op.access` is 0 on every operand and `cs_regs_access` claims it
/// writes nothing. The old text path fell to a default that clobbered
/// `operands[0]` (x1), leaving x0's stale value to render verbatim as a later
/// call argument: a fabricated value, not a missing one. There are 583 atomic
/// sites in CoreLocation's __text alone.
///
/// The fix is the pessimistic default — an unmodelled instruction may write any
/// register it names. That also over-clobbers x1, which `ldaddal` only reads;
/// imprecise by construction, never a lie.
@Test func atomicsClobberTheirDestinations() throws {
    //   mov     x0, #0x99      x0 = 0x99   (tracked)
    //   mov     x5, #0x2a      x5 = 42     (tracked, untouched by the atomic)
    //   ldaddal x1, x0, [x2]   writes x0
    //   bl      L
    // L: ret
    let function = try #require(assembledFunction([
        0x20, 0x13, 0x80, 0xd2,
        0x45, 0x05, 0x80, 0xd2,
        0x40, 0x00, 0xe1, 0xf8,
        0x01, 0x00, 0x00, 0x94,
        0xc0, 0x03, 0x5f, 0xd6,
    ]))
    let site = try #require(ValueTracer().callSites(in: function)[0x100c])
    // The bug: x0 previously survived as 0x99 and was rendered as argument 0.
    #expect(site.arguments[0] == .unknown)
    // A register the atomic never names is untouched — the clobber is targeted,
    // not a blanket reset.
    #expect(site.arguments.count == 6)
    #expect(site.arguments[5] == .immediate(42))
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

/// Concrete protocol existential values carry concrete witness-table pointers.
/// Their `ldr slot; blr register` calls should become named graph edges, while
/// generic/unknown table dispatch remains unresolved.
@Test func resolvesConcreteWitnessTableDispatchIfPresent() async throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path)
    }
    let run = try #require(functions.first { $0.demangledName == "run()" })
    let indirectCalls = run.instructions.filter {
        $0.controlFlow == .call && $0.text.hasPrefix("blr")
    }
    #expect(indirectCalls.count >= 3)
    #expect(indirectCalls.allSatisfy { $0.branchTarget != nil })
    #expect(indirectCalls.allSatisfy {
        let annotation = $0.annotation ?? ""
        return annotation.hasPrefix("→ ")
            && (annotation.contains("Circle") || annotation.contains("Rectangle"))
    })

    let graph = CallGraph(functions: functions)
    for call in indirectCalls {
        #expect(graph.edges.contains { $0.site == call.address && $0.callee == call.branchTarget })
    }
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

/// ARC runtime helpers are exact lowerings of a source send, so each renders
/// back as that send — and composing them reproduces the original expression.
@Test func rendersObjCRuntimeIdioms() {
    func idiom(_ callee: String, _ arguments: [String]) -> String? {
        DisassembledFunction.objcRuntimeIdiom(callee: callee, arguments: arguments)
    }
    #expect(idiom("objc_alloc", ["NSString"]) == "[NSString alloc]")
    #expect(idiom("objc_opt_class", ["self"]) == "[self class]")
    #expect(idiom("objc_alloc_init", ["Foo"]) == "[[Foo alloc] init]")
    #expect(idiom("objc_opt_new", ["Foo"]) == "[[Foo alloc] init]")
    #expect(idiom("objc_opt_isKindOfClass", ["x", "[NSNumber class]"]) == "[x isKindOfClass:[NSNumber class]]")

    // The composed form. `objc_alloc(objc_opt_class(x))` is `[[x class] alloc]`
    // — NOT `[x alloc]`. The lowering is the reverse of what it looks like:
    // `[self alloc]` (a Class receiver) emits a bare objc_alloc(self), while
    // `[[self class] alloc]` (an instance receiver) is what routes through
    // objc_opt_class. Collapsing it drops a real call, and on an instance
    // receiver prints invalid ObjC — `alloc` is a class method.
    #expect(idiom("objc_alloc", [idiom("objc_opt_class", ["self"])!]) == "[[self class] alloc]")

    // An unrecovered operand renders `?`, never a shorter argument list:
    // `objc_alloc()` would claim the call takes no argument, which is false.
    #expect(idiom("objc_alloc", []) == "[? alloc]")
    #expect(idiom("objc_opt_isKindOfClass", ["x"]) == "[x isKindOfClass:?]")

    // Not a runtime idiom.
    #expect(idiom("objc_msgSend", ["a", "b"]) == nil)
    #expect(idiom("swift_allocObject", ["t"]) == nil)
}
