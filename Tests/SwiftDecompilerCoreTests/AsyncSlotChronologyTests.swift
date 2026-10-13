import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func chronologyFunction(_ words: [UInt32], at: UInt64, allocations: Set<Int> = []) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: at)
    return .init(symbol: at == 0x1000 ? "entry" : "resume",
        demangledName: at == 0x1000 ? "M.entry() async -> Swift.Int" : nil,
        startAddress: at, instructions: decoded.enumerated().map { i, insn in
            Instruction(address: insn.address, text: insn.text,
                annotation: insn.controlFlow == .call ? (allocations.contains(i) ? "swift_task_alloc" : "M.observe(Swift.Int) -> Swift.Int") : nil,
                controlFlow: insn.controlFlow, branchTarget: insn.controlFlow == .call ? nil : insn.branchTarget,
                detail: insn.detail)
        }, source: .address)
}

private func chronologyChain(_ prefix: [UInt32], resumeWords: [UInt32] = [0xf9400ac0, 0xf94006c1, 0xd61f0020]) throws -> (DisassembledFunction, DisassembledFunction, AsyncFuncletIndex, [UInt64: [Int: AbstractValue]]) {
    var entryWords = prefix
    // Compiler-style executor hop: x0 is the continuation address; x22
    // remains our own context. No unknown callee-buffer write is assumed safe.
    let pc = UInt32(0x1000 + entryWords.count * 4)
    let delta = UInt32(0x2000) - pc
    entryWords.append(0x10000000 | ((delta & 3) << 29) | (((delta >> 2) & 0x7ffff) << 5))
    let branchPC = UInt32(0x1000 + entryWords.count * 4)
    entryWords.append(0x14000000 | ((0x4000 - branchPC) >> 2))
    let entry = try chronologyFunction(entryWords, at: 0x1000)
    let resume = try chronologyFunction(resumeWords, at: 0x2000)
    let raw = [UInt64(0x1000): entry, UInt64(0x2000): resume]
    let index = AsyncFuncletIndex.build(hints: .init(entries: [0x1000], awaitReturns: [], continuations: [0x2000]),
        functionStarts: Set(raw.keys), instructions: { raw[$0]?.instructions ?? [] },
        nameOf: { $0 == 0x4000 ? "swift_task_switch" : raw[$0]?.displayName })
    try #require(index.chains[0x1000] == [0x1000, 0x2000])
    let functions = raw.mapValues { function in
        index.info(for: function.startAddress, parentName: { raw[$0]?.displayName })
            .map(function.attachingAsyncFunclet) ?? function
    }
    let slots = Disassembler().asyncChainSlots(index: index, function: { functions[$0] },
        enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())
    return (functions[0x1000]!, functions[0x2000]!, index, slots)
}

@Test func aLaterAsyncStoreCannotSeedAnEarlierObservation() throws {
    // Before the unique store, initial slot16=11. Native wrapper observes11,
    // then stores7. Global chain seeding must not invent observe(7).
    let (entry, _, index, slots) = try chronologyChain([0xf9400ac0, 0x94000000, 0xd28000e8, 0xf9000ac8])
    let convention = try #require(Disassembler.asyncConvention(for: entry, base: nil, index: index))
    let analysis = ValueTracer(asyncContextSlots: slots[0x1000] ?? [:]).analyze(entry, entry: convention)
    let site = try #require(analysis.callSites[0x1004])
    #expect(site.arguments.first != .immediate(7))
}

@Test func aConditionalSoleAsyncStoreCannotSeedTheUntouchedPath() throws {
    // cbz x1 skips the unique store before the common handoff.
    // Native wrapper returns11 on the skipped path and7 on the written path.
    let (_, resume, index, slots) = try chronologyChain([0xb4000061, 0xd28000e8, 0xf9000ac8])
    #expect(slots.values.allSatisfy { $0[16] == nil })
    let convention = try #require(Disassembler.asyncConvention(for: resume, base: nil, index: index))
    let analysis = ValueTracer(asyncContextSlots: slots[0x2000] ?? slots[0x1000] ?? [:]).analyze(resume, entry: convention)
    #expect(analysis.exitValues.values.allSatisfy { $0 != .immediate(7) })
}


@Test func aLaterResumeStoreCannotSeedTheEarlierResumeObservation() throws {
    let (_, resume, index, slots) = try chronologyChain([], resumeWords: [
        0xf9400ac0, 0x94000000, 0xd28000e8, 0xf9000ac8, 0xf94006c1, 0xd61f0020,
    ])
    let convention = try #require(Disassembler.asyncConvention(for: resume, base: nil, index: index))
    let analysis = ValueTracer(asyncContextSlots: slots[0x2000] ?? slots[0x1000] ?? [:]).analyze(resume, entry: convention)
    #expect(analysis.callSites[0x2004]?.arguments.first != .immediate(7))
}

@Test func nativeAsyncLeafChronologyAndRenderedCallsAgreeIfPresent() async throws {
    let path = "Fixtures/Sample/libAsyncSlotChronology.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let before = unsafeBitCast(try #require(dlsym(library, "async_chronology_before")),
        to: (@convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64).self)
    let conditional = unsafeBitCast(try #require(dlsym(library, "async_chronology_conditional")),
        to: (@convention(c) (UnsafeMutablePointer<UInt64>, UInt64) -> UInt64).self)
    var context: [UInt64] = [0, 0, 11]
    context.withUnsafeMutableBufferPointer { storage in
        #expect(before(storage.baseAddress!) == 11)
        #expect(storage[2] == 7)
        for flag in [UInt64(0), UInt64(1)] {
            storage[2] = 11
            #expect(conditional(storage.baseAddress!, flag) == (flag == 0 ? 11 : 7))
            #expect(storage[2] == (flag == 0 ? 11 : 7))
        }
    }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "Leaf")
    }
    let beforeLeaf = try #require(functions.first { $0.displayName.contains("beforeLeaf") })
    let conditionalLeaf = try #require(functions.first { $0.displayName.contains("conditionalLeaf") })
    #expect(beforeLeaf.asyncFunclet?.isEntry == true)
    #expect(conditionalLeaf.asyncFunclet?.isEntry == true)
    #expect(!beforeLeaf.renderStructured().contains("observe(7)"))
    #expect(!conditionalLeaf.renderStructured().contains("observe(7)"))
}

@Test func anUnconditionalEntryStoreStillSeedsItsResume() throws {
    let (_, resume, index, slots) = try chronologyChain([0xd28000e8, 0xf9000ac8])
    let seed = slots[0x2000] ?? slots[0x1000] ?? [:]
    #expect(seed[16] == .immediate(7))
    let convention = try #require(Disassembler.asyncConvention(for: resume, base: nil, index: index))
    #expect(ValueTracer(asyncContextSlots: seed).analyze(resume, entry: convention).exitValues[0x2008] == .immediate(7))
}

@Test func anEntryLoadAfterItsStoreStillProvesTheObservedValue() throws {
    let (entry, _, index, _) = try chronologyChain([0xd28000e8, 0xf9000ac8, 0xf9400ac0, 0x94000000])
    let convention = try #require(Disassembler.asyncConvention(for: entry, base: nil, index: index))
    #expect(ValueTracer().analyze(entry, entry: convention).callSites[0x100c]?.arguments.first == .immediate(7))
}


@Test func ordinaryAsyncAnalysisDoesNotCaptureUnrequestedSlotSnapshots() throws {
    let (entry, _, index, _) = try chronologyChain([0xd28000e8, 0xf9000ac8])
    let convention = try #require(Disassembler.asyncConvention(for: entry, base: nil, index: index))
    let analysis = ValueTracer().analyze(entry, entry: convention)
    #expect(analysis.asyncSlotFactsAtBranches.isEmpty)
    #expect(analysis.asyncSlotStores[16] == [.immediate(7)])
}
