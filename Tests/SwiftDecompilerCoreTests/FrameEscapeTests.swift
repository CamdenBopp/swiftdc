import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let frameEscapeFixture = "Fixtures/Sample/libFrameEscapeControls.dylib"

/// Each reduction stores 7 to a frame slot and returns the slot. The native
/// results are the oracle; the decompiler may decline, never claim 7 where
/// the machine returns something else.
private let frameEscapeCases: [(member: String, rendered: String)] = [
    ("callPersists", "return ?"),
    ("joinPersists", "return ?"),
    ("joinEscapedBefore", "return ?"),
    ("storeThrough", "return ?"),
    ("indexedStore", "return ?"),
    ("vectorStore", "return ?"),
    ("rbitEscape", "return ?"),
    ("stackArgument", "return ?"),
    ("slotReadBack", "return ?"),
    ("slotChainLater", "return ?"),
    ("slotIndexedLoss", "return ?"),
    ("joinDropped", "return ?"),
    ("wideEscape", "return ?"),
    ("unknownLoad", "return 7"),
    ("noEscape", "return 7"),
    ("argumentStore", "return 7"),
    ("dynamicAllocation", "return 7"),
]

@Test func frameEscapeReductionsRunAsDocumentedIfPresent() throws {
    guard FileManager.default.fileExists(atPath: frameEscapeFixture) else { return }
    let library = try #require(dlopen(frameEscapeFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias NoArgument = @convention(c) () -> Int64
    typealias OneArgument = @convention(c) (Int64) -> Int64
    func call(_ symbol: String) throws -> Int64 {
        try unsafeBitCast(#require(dlsym(library, symbol)), to: NoArgument.self)()
    }
    func call(_ symbol: String, _ argument: Int64) throws -> Int64 {
        try unsafeBitCast(#require(dlsym(library, symbol)), to: OneArgument.self)(argument)
    }
    #expect(try call("$s11FrameEscape12callPersistsSiyF") == 11)
    #expect(try call("$s11FrameEscape12joinPersistsyS2iF", 1) == 11)
    #expect(try call("$s11FrameEscape12joinPersistsyS2iF", 0) == 7)
    #expect(try call("$s11FrameEscape17joinEscapedBeforeyS2iF", 1) == 11)
    #expect(try call("$s11FrameEscape17joinEscapedBeforeyS2iF", 0) == 7)
    #expect(try call("$s11FrameEscape12storeThroughSiyF") == 11)
    #expect(try call("$s11FrameEscape12indexedStoreyS2iF", 8) == 11)
    #expect(try call("$s11FrameEscape12indexedStoreyS2iF", 16) == 7)
    #expect(try call("$s11FrameEscape11vectorStoreSiyF") == 0)
    #expect(try call("$s11FrameEscape10rbitEscapeSiyF") == 11)
    #expect(try call("$s11FrameEscape8noEscapeSiyF") == 7)
    for count: Int64 in [0, 1, 5] {
        #expect(try call("$s11FrameEscape17dynamicAllocationyS2iF", count) == 7)
    }
    #expect(try call("$s11FrameEscape13stackArgumentSiyF") == 11)
    #expect(try call("$s11FrameEscape12slotReadBackSiyF") == 11)
    #expect(try call("$s11FrameEscape14slotChainLaterSiyF") == 11)
    #expect(try call("$s11FrameEscape15slotIndexedLossyS2iF", 24) == 11)
    #expect(try call("$s11FrameEscape10wideEscapeSiyF") == 11)
    #expect(try call("$s11FrameEscape11unknownLoadSiyF") == 7)
    var flag: Int64 = 0
    let flagAddress = withUnsafeMutablePointer(to: &flag) { Int64(Int(bitPattern: $0)) }
    #expect(try call("$s11FrameEscape11joinDroppedyS2iF", flagAddress) == 11)
    flag = 1
    #expect(try call("$s11FrameEscape11joinDroppedyS2iF", flagAddress) == 7)
    var sink: Int64 = 0
    let sinkAddress = withUnsafeMutablePointer(to: &sink) { Int64(Int(bitPattern: $0)) }
    #expect(try call("$s11FrameEscape13argumentStoreyS2iF", sinkAddress) == 7)
    #expect(sink == 11)
}

/// The value a slot held before a write that may reach it is not its value
/// after. Each wrong case rendered `return 7`; the controls keep it.
@Test func escapedFrameSlotsAreNotReadAcrossWritesIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: frameEscapeFixture) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: frameEscapeFixture) }
    for (member, rendered) in frameEscapeCases {
        let function = try #require(functions.first { $0.displayName.contains("FrameEscape.\(member)(") }, "\(member)")
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(text.contains(rendered), "\(member): \(text)")
            if rendered != "return 7" { #expect(!text.contains("return 7"), "\(member): \(text)") }
        }
    }
}

private let compiledCallEffectFixtures = [
    "Fixtures/Sample/libStackCallEffects.dylib",
    "Fixtures/Sample/libStackCallEffects.opt.dylib",
    "Fixtures/Sample/libStackCallEffects.osize.dylib",
]

/// `cacheEscape` exports a stack address to a global, writes 7 through it,
/// and calls a helper that writes 11 through the global.
@Test func compiledStackEscapeObservesTheCallsWriteNativelyIfPresent() throws {
    typealias Oracle = @convention(c) (Int64) -> Int64
    for fixture in compiledCallEffectFixtures {
        guard FileManager.default.fileExists(atPath: fixture) else { continue }
        let library = try #require(dlopen(fixture, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        let oracle = unsafeBitCast(try #require(dlsym(library, "stack_compiled_global")), to: Oracle.self)
        for seed: Int64 in [0, 1, .min, .max] {
            #expect(oracle(seed) == 11, "\(fixture)")
        }
    }
}

/// -O and -Osize rendered `return 7`. Every decode path must decline, and
/// all three (the objdump-backed array path, the filtered Capstone path and
/// streaming) must render the same views. The array path once named the
/// stub `stack_chk_fail`, missed its known zero arity, and passed it the
/// closure's result.
@Test func compiledStackEscapeIsNotRenderedAsThePreCallStoreIfPresent() async throws {
    for fixture in compiledCallEffectFixtures {
        guard FileManager.default.fileExists(atPath: fixture) else { continue }
        let full = try await withStableDependencies { try await Disassembler().disassemble(path: fixture) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: fixture, functionFilter: "cacheEscape")
        }
        let streamed = try await withStableDependencies {
            let image = try BinaryLoader.load(path: fixture)
            return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        func views(_ functions: [DisassembledFunction], structured: Bool) -> [String: String] {
            Dictionary(uniqueKeysWithValues: functions.filter { $0.displayName.contains("cacheEscape(") }
                .map { ($0.symbol, structured ? $0.renderStructured() : $0.renderPseudo()) })
        }
        for structured in [false, true] {
            let fullViews = views(full, structured: structured)
            #expect(!fullViews.isEmpty, "\(fixture)")
            #expect(views(filtered, structured: structured) == fullViews, "\(fixture)")
            #expect(views(streamed, structured: structured) == fullViews, "\(fixture)")
            for text in fullViews.values {
                #expect(!text.contains("return 7"), "\(fixture): \(text)")
            }
        }
    }
}

/// A Mach-O symbol carries one linker underscore; the rest are the name's.
/// objdump's stub comment and a direct `bl` operand both name the C function
/// the in-process paths name.
@Test func objdumpCalleeNamesKeepTheirOwnUnderscores() {
    func callee(_ text: String) -> String? {
        DisassembledFunction.calleeName(of: Instruction(address: 0x1000, text: text, controlFlow: .call))
    }
    #expect(callee("bl\t0x744 ; symbol stub for: ___stack_chk_fail") == "__stack_chk_fail")
    #expect(callee("bl\t0x744 ; symbol stub for: _swift_release") == "swift_release")
    #expect(callee("bl\t___clang_call_terminate") == "__clang_call_terminate")
    #expect(callee("bl\t_$s1M1fyyF") == "$s1M1fyyF")
}
