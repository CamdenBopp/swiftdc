import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let childSeedFixture = "Fixtures/Sample/libAsyncChildSeed.dylib"

private func seedBranch(from: UInt64, to: UInt64, link: Bool) -> UInt32 {
    (link ? 0x94000000 : 0x14000000) | (UInt32(truncatingIfNeeded: (Int64(to) - Int64(from)) >> 2) & 0x03ffffff)
}

/// `adr x<register>, target` at `pc`, for a target above it.
private func seedADR(_ register: UInt32, at pc: UInt64, to target: UInt64) -> UInt32 {
    let delta = UInt32(truncatingIfNeeded: target - pc)
    return 0x10000000 | register | (delta & 3) << 29 | ((delta >> 2) & 0x7ffff) << 5
}

// mov x8, #7; str x8, [x22, #16]: the entry's one store to slot 16.
private let storeSeven: [UInt32] = [0xd28000e8, 0xf9000ac8]
// ldr x0, [x22, #16]; ldr x1, [x22, #8]; br x1
private let returnSlot: [UInt32] = [0xf9400ac0, 0xf94006c1, 0xd61f0020]

/// The chain rooted at 0x1000, its index, and the slots each resume funclet
/// is seeded with. Analysis seams, not complete native async functions.
private func seedChain(
    _ bodies: [UInt64: [UInt32]], names: [UInt64: String],
    awaitReturns: [UInt64] = [], continuations: [UInt64] = [], expecting chain: [UInt64],
    recorder: ProbeRecorder? = nil
) throws -> (index: AsyncFuncletIndex, slots: [UInt64: [Int: AbstractValue]]) {
    let engine = try #require(CapstoneEngine())
    var raw: [UInt64: DisassembledFunction] = [:]
    for (address, words) in bodies {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: address)
        try #require(decoded.count == words.count)
        raw[address] = DisassembledFunction(
            symbol: address == 0x1000 ? "entry" : "f\(address)",
            demangledName: address == 0x1000 ? "M.entry() async -> Swift.Int" : nil,
            startAddress: address,
            instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .address)
    }
    let index = AsyncFuncletIndex.build(
        hints: .init(entries: [0x1000], awaitReturns: awaitReturns, continuations: continuations),
        functionStarts: Set(raw.keys), instructions: { raw[$0]?.instructions ?? [] },
        nameOf: { names[$0] })
    try #require(index.chains[0x1000] == chain)
    let functions = raw.mapValues { function in
        index.info(for: function.startAddress, parentName: { raw[$0]?.displayName })
            .map(function.attachingAsyncFunclet) ?? function
    }
    func slots() -> [UInt64: [Int: AbstractValue]] {
        Disassembler().asyncChainSlots(index: index, function: { functions[$0] },
            enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())
    }
    guard let recorder else { return (index, slots()) }
    return (index, Probe.recording(recorder) { slots() })
}

private func hopChain(recorder: ProbeRecorder? = nil) throws -> (index: AsyncFuncletIndex, slots: [UInt64: [Int: AbstractValue]]) {
    // adr x0, resume; b swift_task_switch
    try seedChain([
        0x1000: storeSeven + [seedADR(0, at: 0x1008, to: 0x2000), seedBranch(from: 0x100c, to: 0x4000, link: false)],
        0x2000: returnSlot,
    ], names: [0x4000: "swift_task_switch"], continuations: [0x2000], expecting: [0x1000, 0x2000], recorder: recorder)
}

private func waitChain(recorder: ProbeRecorder? = nil) throws -> (index: AsyncFuncletIndex, slots: [UInt64: [Int: AbstractValue]]) {
    // adr x2, resume; b swift_task_future_wait: the wait's resume function
    // travels in x2, and its result buffer in x0 is whatever the caller holds.
    try seedChain([
        0x1000: storeSeven + [seedADR(2, at: 0x1008, to: 0x2000), seedBranch(from: 0x100c, to: 0x4000, link: false)],
        0x2000: returnSlot,
    ], names: [0x4000: "swift_task_future_wait"], continuations: [0x2000], expecting: [0x1000, 0x2000],
       recorder: recorder)
}

private func awaitChain() throws -> (index: AsyncFuncletIndex, slots: [UInt64: [Int: AbstractValue]]) {
    // bl swift_task_alloc; adr x8, resume; bl header; b child, where header is
    // `stp x22, x8, [x0]; mov x22, x0; ret`: the entry neither stores nor
    // copies its context, and the child still receives it as its Parent word.
    try seedChain([
        0x1000: storeSeven + [
            seedBranch(from: 0x1008, to: 0x4000, link: true), seedADR(8, at: 0x100c, to: 0x2000),
            seedBranch(from: 0x1010, to: 0x3000, link: true), seedBranch(from: 0x1014, to: 0x5000, link: false),
        ],
        0x2000: [0xd65f03c0],
        0x3000: [0xa9002016, 0xaa0003f6, 0xd65f03c0],
    ], names: [0x4000: "swift_task_alloc", 0x5000: "M.child() async -> Swift.Int"],
       awaitReturns: [0x2000], expecting: [0x1000, 0x2000])
}

/// Control: nothing else runs on the task across an executor hop, so the
/// value the entry stored is the value its continuation reads.
@Test func anExecutorHopKeepsTheEntrySlotSeed() throws {
    let chain = try hopChain()
    #expect(chain.index.transfers[0x1000]?.map(\.kind) == [.executorHop])
    #expect(chain.slots[0x2000]?[16] == .immediate(7))
}

/// A runtime wait completes into the buffer its caller passed, which nothing
/// here proves is outside the context.
@Test func aRuntimeWaitDeclinesTheEntrySlotSeed() throws {
    let chain = try waitChain()
    #expect(chain.index.transfers[0x1000]?.map(\.kind) == [.runtimeWait("swift_task_future_wait")])
    #expect(chain.slots[0x2000]?[16] == nil)
}

/// An awaited callee reaches its caller's context through its own Parent
/// word, whatever the caller itself stored or copied.
@Test func anAwaitedCalleeDeclinesTheEntrySlotSeed() throws {
    let chain = try awaitChain()
    #expect(chain.index.transfers[0x1000]?.map(\.kind) == [.awaitCall])
    #expect(chain.slots[0x2000]?[16] == nil)
}

/// The seed is the value at the entry's suspension, and every later funclet
/// of the chain receives it: a transfer out of any of them counts.
@Test func aLaterFuncletsRuntimeWaitDeclinesTheWholeChain() throws {
    let chain = try seedChain([
        0x1000: storeSeven + [seedADR(0, at: 0x1008, to: 0x2000), seedBranch(from: 0x100c, to: 0x4000, link: false)],
        0x2000: [seedADR(2, at: 0x2000, to: 0x3000), seedBranch(from: 0x2004, to: 0x5000, link: false)],
        0x3000: returnSlot,
    ], names: [0x4000: "swift_task_switch", 0x5000: "swift_task_future_wait"],
       continuations: [0x2000, 0x3000], expecting: [0x1000, 0x2000, 0x3000])
    #expect(chain.index.transfers[0x1000]?.map(\.kind) == [.executorHop])
    #expect(chain.index.transfers[0x2000]?.map(\.kind) == [.runtimeWait("swift_task_future_wait")])
    #expect(chain.slots[0x2000]?[16] == nil)
    #expect(chain.slots[0x3000]?[16] == nil)
}

/// The decline names its cause and its site, once per chain; a chain of
/// hops records none.
@Test func anUnprovedTransferIsRecordedAtItsSite() throws {
    func declines(_ recorder: ProbeRecorder) -> [UInt64?] {
        recorder.records.filter {
            $0.event == .contextEscapeUnknown && $0["reason"] == .label("unproved-transfer-effect")
        }.map(\.address)
    }
    let waited = ProbeRecorder()
    _ = try waitChain(recorder: waited)
    #expect(declines(waited) == [0x100c])
    let hopped = ProbeRecorder()
    _ = try hopChain(recorder: hopped)
    #expect(declines(hopped).isEmpty)
    #expect(hopped.count(of: .slotProven) == 1)
}

/// The machine's answer for the two authored chains: the child that follows
/// its Parent word changes the caller's slot 16 to 11 before the resume
/// funclet reads it; the child that writes its own context leaves it 7.
@Test func nativeAwaitedChildrenReachOrMissTheCallerSlotIfPresent() throws {
    guard FileManager.default.fileExists(atPath: childSeedFixture) else { return }
    let library = try #require(dlopen(childSeedFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Adapter = @convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64
    func run(_ name: String) throws -> (UInt64, UInt64) {
        let adapter = try unsafeBitCast(#require(dlsym(library, "async_child_seed_run_" + name)), to: Adapter.self)
        var context: [UInt64] = [0, 0, 3, 0]
        let result = context.withUnsafeMutableBufferPointer { adapter($0.baseAddress!) }
        return (result, context[2])
    }
    #expect(try run("followed") == (11, 11))
    #expect(try run("disjoint") == (7, 7))
}

/// async_child_seed.s: each resume funclet passes slot 16 to `observe`. The
/// entry stored 7 there. Across the awaited children the slot is 11 or 7 by
/// what the child did, which the caller's chain does not show: neither is
/// named. Across the executor hop it is the entry's 7. Every way in is held
/// to it: the whole image, a filter, the streamed image and one function at
/// a time.
@Test func anAwaitedChildsSlotIsNotTheEntrysStoreIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: childSeedFixture) else { return }
    let image = try BinaryLoader.load(path: childSeedFixture)
    let listing = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: childSeedFixture)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: childSeedFixture, functionFilter: "AsyncChildSeed")
    }
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler(preset: .default).analyzeEachFunction(at: Set(listing.map(\.startAddress)), in: image, transform: { $0 })
    }
    for (way, functions) in [("listing", listing), ("filtered", filtered), ("streamed", streamed), ("each", Array(each.values))] {
        for (symbol, kept) in [("_$s14AsyncChildSeed8followedSiyYaFTQ0_", false),
                               ("_$s14AsyncChildSeed8disjointSiyYaFTQ0_", false),
                               ("_$s14AsyncChildSeed6hoppedSiyYaFTY0_", true)] {
            let resume = try #require(functions.first { $0.symbol == symbol }, "\(way): \(symbol)")
            for text in [resume.render(), resume.renderPseudo(), resume.renderStructured()] {
                #expect(text.contains("AsyncChildSeed.observe("), "\(way): \(text)")
                // One function at a time recovers no suspension edges, so
                // no chain and no seed: the hop's 7 is not claimed there.
                if kept, way != "each" {
                    #expect(text.contains("observe(7)"), "\(way): \(text)")
                } else if !kept {
                    #expect(!text.contains("observe(7)"), "\(way): \(text)")
                }
                #expect(!text.contains("observe(11)"), "\(way): \(text)")
            }
        }
    }
}
