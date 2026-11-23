import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let stackLifetimeFixture = "Fixtures/Sample/libStackLifetime.dylib"

@Test func calleeStackReuseHasNativeValueAndBoundaryOraclesIfPresent() throws {
    guard FileManager.default.fileExists(atPath: stackLifetimeFixture) else { return }
    let library = try #require(dlopen(stackLifetimeFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Entry = @convention(c) () -> Int64
    for (name, expected): (String, Int64) in [
        ("reuseUnknown", 99), ("reuseProven", 7), ("reuseExact", 99), ("reuseAbove", 7),
        ("reusePreservation", 99), ("keepPreservation", 7), ("reusePointer", 99),
    ] {
        let symbol = "$s13StackLifetime\(name.count)\(name)SiyF"
        let entry = unsafeBitCast(try #require(dlsym(library, symbol)), to: Entry.self)
        #expect(entry() == expected, Comment(rawValue: name))
    }
    typealias Dynamic = @convention(c) (Int64) -> Int64
    let dynamic = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime12reuseDynamicyS2iF")), to: Dynamic.self)
    #expect(dynamic(0) == 99)
    #expect(dynamic(16) == 7)
    let dynamicAbove = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime17reuseDynamicAboveyS2iF")), to: Dynamic.self)
    #expect(dynamicAbove(-16) == 99)
    #expect(dynamicAbove(0) == 7)
    #expect(dynamicAbove(16) == 7)
    let probed = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime11reuseProbedyS2iF")), to: Dynamic.self)
    for bytes: Int64 in [0, 1, 16, 100] { #expect(probed(bytes) == 7) }
    let probedRaw = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime14reuseProbedRawyS2iF")), to: Dynamic.self)
    for bytes: Int64 in [0, 16, 96] { #expect(probedRaw(bytes) == 7) }
    typealias Pair = @convention(c) (Int64, Int64) -> Int64
    let mismatch = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime13probeMismatchyS2i_SitF")), to: Pair.self)
    #expect(mismatch(16, 16) == 7)
    #expect(mismatch(16, -16) == 99)
    let probedTwice = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime16reuseProbedTwiceyS2iF")), to: Dynamic.self)
    for bytes: Int64 in [0, 1, 16, 100] { #expect(probedTwice(bytes) == 7) }
    for symbol in ["18reuseProbedSpilled", "23reuseProbedSpilledTwice", "25reuseProbedSpilledEscaped"] {
        let spilled = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime\(symbol)yS2iF")), to: Dynamic.self)
        for bytes: Int64 in [0, 1, 16, 100] { #expect(spilled(bytes) == 7, Comment(rawValue: symbol)) }
    }
    let chain = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime16reuseProbedChainyS2iF")), to: Dynamic.self)
    for bytes: Int64 in [0, 1, 16, 100] { #expect(chain(bytes) == 7) }
    let chainStore = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime15probeChainStoreyS2iF")), to: Dynamic.self)
    #expect(chainStore(16) == 7)
    #expect(chainStore(0) == 5)
    // `***pp` is the size; `q` points at the same word.
    typealias Deep = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int64>) -> Int64
    let deepSize = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime19reuseProbedDeepSizeyS2iF")), to: Deep.self)
    let deepTwice = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime20reuseProbedDeepTwiceyS2iF")), to: Deep.self)
    let deepStubbed = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime18reuseProbedStubbedyS2iF")), to: Deep.self)
    let deepReload = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime15probeDeepReloadyS2i_SitF")), to: Deep.self)
    for bytes: Int64 in [0, 1, 16, 100] {
        let size = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        let inner = UnsafeMutablePointer<UnsafeMutablePointer<Int64>>.allocate(capacity: 1)
        let outer = UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<Int64>>>.allocate(capacity: 1)
        defer { size.deallocate(); inner.deallocate(); outer.deallocate() }
        inner.pointee = size; outer.pointee = inner
        size.pointee = bytes
        #expect(deepSize(UnsafeMutableRawPointer(outer), size) == 7)
        #expect(deepTwice(UnsafeMutableRawPointer(outer), size) == 7)
        #expect(deepStubbed(UnsafeMutableRawPointer(outer), size) == 7)
        size.pointee = 16
        #expect(deepReload(UnsafeMutableRawPointer(outer), size) == 99)
    }
    typealias Stale = @convention(c) (Int64, UnsafeMutableRawPointer) -> Int64
    let stale = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime14probeStaleSizeyS2i_SitF")), to: Stale.self)
    do {
        let size = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        let inner = UnsafeMutablePointer<UnsafeMutablePointer<Int64>>.allocate(capacity: 1)
        let outer = UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<Int64>>>.allocate(capacity: 1)
        defer { size.deallocate(); inner.deallocate(); outer.deallocate() }
        inner.pointee = size; outer.pointee = inner; size.pointee = 16
        #expect(stale(16, UnsafeMutableRawPointer(outer)) == 7)
    }
    let pushed = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime17reuseProbedPushedyS2iF")), to: Dynamic.self)
    for bytes: Int64 in [0, 1, 16, 100] { #expect(pushed(bytes) == 7) }
    let rebasedPush = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime19reuseProbedRebasedPyS2iF")), to: Dynamic.self)
    for bytes: Int64 in [0, 1, 16, 100] { #expect(rebasedPush(bytes) == 7) }
    let popPast = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime16probePopPastPushyS2iF")), to: Dynamic.self)
    #expect(popPast(0) == 99)
    #expect(popPast(32) == 7)
    typealias Plain = @convention(c) () -> Int64
    let x8Unread = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime13reuseX8UnreadSiyF")), to: Plain.self)
    #expect(x8Unread() == 7)
    let x8Written = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime14probeX8WrittenSiyF")), to: Plain.self)
    #expect(x8Written() == 0)
    let reaching = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime18probeSpillReachingyS2iF")), to: Dynamic.self)
    #expect(reaching(16) == 99)
    let stacked = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime12probeStackedyS2i_SitF")), to: Pair.self)
    #expect(stacked(16, 16) == 7)
    #expect(stacked(0, -16) == 99)
    // Each reads its size from a global and takes p (unused), m, and q, the
    // global's address (the Swift mangling names only the first two).
    typealias Reload = @convention(c) (UnsafeMutablePointer<Int64>, Int64, UnsafeMutablePointer<Int64>) -> Int64
    let size = try #require(dlsym(library, "stack_lifetime_size")).assumingMemoryBound(to: Int64.self)
    for symbol in ["11probeReload", "9probeCall", "10probeTwice"] {
        let reload = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime\(symbol)ySiSpySiG_SitF")), to: Reload.self)
        size.pointee = 16
        #expect(reload(size, 16, size) == 7, Comment(rawValue: symbol))
        size.pointee = 16
        #expect(reload(size, -16, size) == 99, Comment(rawValue: symbol))
    }
}

@Test func anUnprovedCallCannotKeepAnEarlierCalleesStackWordInAnyPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stackLifetimeFixture) else { return }
    let image = try BinaryLoader.load(path: stackLifetimeFixture)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: stackLifetimeFixture) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: stackLifetimeFixture, functionFilter: "StackLifetime.")
    }
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for name in ["reuseUnknown", "reuseDynamic", "reuseDynamicAbove", "reusePreservation", "reusePointer",
                     "probeMismatch", "probeReload", "probeCall", "probeTwice", "probeStacked", "probeSpillReaching",
                     "probeChainStore", "probeDeepReload",
                     "probePopPastPush", "probeStaleSize",
                     "probeX8Written"] {
            let function = try #require(group.first { $0.displayName.hasPrefix("StackLifetime.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("return ?"), Comment(rawValue: text))
                #expect(!text.contains("return 7"), Comment(rawValue: text))
            }
        }
        for (name, expected) in [("reuseProven", 7), ("reuseExact", 99), ("reuseAbove", 7), ("keepPreservation", 7),
                                 ("reuseProbed", 7), ("reuseProbedRaw", 7),
                                 ("reuseProbedTwice", 7), ("reuseProbedSpilled", 7), ("reuseProbedSpilledTwice", 7),
                                 ("reuseProbedSpilledEscaped", 7), ("reuseProbedChain", 7),
                                 ("reuseProbedDeepSize", 7), ("reuseProbedPushed", 7),
                                 ("reuseProbedDeepTwice", 7), ("reuseX8Unread", 7),
                                 ("reuseProbedStubbed", 7), ("reuseProbedRebasedP", 7)] {
            let function = try #require(group.first { $0.displayName.hasPrefix("StackLifetime.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("return \(expected)"), Comment(rawValue: text))
            }
        }
    }
}

// Analysis-only instructions with an explicit external runtime binding.
// The unknown-sp variant is not invoked as a native callable function.
@Test func anUnknownStackPointerCannotProtectFrameFactsAtAStackProbe() throws {
    let engine = try #require(CapstoneEngine())
    for unknownSP in [false, true] {
        let words: [UInt32] = [
            0xd10083ff, 0xd28000e9, 0xf90007e9, 0x910003f3,
            unknownSP ? 0x9100001f : 0xd503201f,
            0x940003fb, 0x9100027f, 0xf94007e0, 0x910083ff, 0xd65f03c0,
        ]
        let data = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } })
        let decoded = engine.disassemble(data, address: 0x1000)
        try #require(decoded.count == words.count)
        let body = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail,
                callee: .kept($0.controlFlow == .call ? "__chkstk_darwin" : nil))
        }
        let function = DisassembledFunction(symbol: "_stack_probe_lifetime_control", demangledName: nil,
            startAddress: 0x1000, instructions: body, source: .address)
        let result = ValueTracer().analyze(function, entry: nil).exitValues[0x1024]
        if unknownSP { #expect(result != .immediate(7)) }
        else { #expect(result == .immediate(7)) }
    }
}

@Test func preservationUsesTheSameCalleeStackBoundaryAndKeepsLostPointerReach() {
    let initial = Preservation.State(registers: ["sp": .stack(-32)],
        slots: [-40: .entry("x19"), -24: .entry("x20")])
    var known = initial
    Preservation.applyCall(CalleeEffect(), inputs: [], to: &known, clobbersMayAliasStack: false)
    #expect(known.load(at: -40) == .unknown)
    #expect(known.load(at: -24) == .entry("x20"))
    var unknown = initial
    unknown.setRegister("sp", to: .unknown)
    Preservation.applyCall(CalleeEffect(), inputs: [], to: &unknown, clobbersMayAliasStack: false)
    #expect(unknown.load(at: -40) == .unknown)
    #expect(unknown.load(at: -24) == .unknown)
    var complete = initial
    let noWrites = CalleeEffect(memoryEffect: .literalStores([], inputs: []))
    Preservation.applyCall(noWrites, inputs: [], to: &complete, clobbersMayAliasStack: false)
    #expect(complete.load(at: -40) == .entry("x19"))
    #expect(complete.load(at: -24) == .entry("x20"))
    var pointer = Preservation.State(registers: ["sp": .stack(-32)],
        slots: [-40: .stack(-24), -24: .entry("x19")])
    Preservation.applyCall(CalleeEffect(), inputs: [], to: &pointer, clobbersMayAliasStack: false)
    #expect(pointer.load(at: -24) == .unknown)
    #expect(pointer.stackAddressEscaped)
}

/// Edge refinement: a block spills a loaded word to [sp, #8] and tests it
/// with `cbz`; on the zero edge the slot holds zero too, so its reload passes
/// 0 (`stack_lifetime.s`, `_stack_lifetime_edge_*`). Each control breaks the
/// identity between the spill and the branch (an unknown store to the slot,
/// a byte store inside it, a write of the register, a store of unknown
/// extent through its address), tests the other edge or only the low half,
/// and reads no 0 from the slot. The -Onone `try` exit is the same shape:
/// `Reconstruction.typedForward` reloads x21 from its spill on the zero edge.
@Test func aSpilledRegisterTestedZeroLeavesItsSlotZeroIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stackLifetimeFixture) else { return }
    let library = try #require(dlopen(stackLifetimeFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Edge = @convention(c) (UnsafeMutablePointer<Int64>) -> Int64
    let spilled = unsafeBitCast(try #require(dlsym(library, "stack_lifetime_edge_spilled")), to: Edge.self)
    var word: Int64 = 0
    #expect(spilled(&word) == 1)
    word = 5
    #expect(spilled(&word) == 10)
    typealias Escaped = @convention(c) (UnsafeMutablePointer<Int64>, Int64, Int64) -> Int64
    let escaped = unsafeBitCast(try #require(dlsym(library, "stack_lifetime_edge_escaped")), to: Escaped.self)
    word = 0
    #expect(escaped(&word, 0, 41) == 42)
    let lowHalf = unsafeBitCast(try #require(dlsym(library, "stack_lifetime_edge_lowhalf")), to: Edge.self)
    word = 1 << 32
    #expect(lowHalf(&word) == 1 << 32 + 1)
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: stackLifetimeFixture) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == "_stack_lifetime_edge_\(name)" }, "no \(name)").renderStructured()
    }
    let refined = try text("spilled")
    #expect(refined.contains("stack_lifetime_take(0)"), Comment(rawValue: refined))
    for name in ["overwritten", "narrowed", "rewritten", "nonzero", "escaped", "lowhalf"] {
        let control = try text(name)
        #expect(!control.contains("stack_lifetime_take(0)"), Comment(rawValue: "\(name): \(control)"))
    }
}
