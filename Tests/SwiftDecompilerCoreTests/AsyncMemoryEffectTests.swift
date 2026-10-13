import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func memoryEffectFunction(_ words: [UInt32], at: UInt64, allocations: Set<Int> = []) throws -> DisassembledFunction {
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

private func memoryEffectChain(_ prefix: [UInt32], resumeWords: [UInt32] = [0xf9400ac0, 0xf94006c1, 0xd61f0020]) throws -> (DisassembledFunction, DisassembledFunction, AsyncFuncletIndex, [UInt64: [Int: AbstractValue]]) {
    var entryWords = prefix
    // Compiler-style executor hop: x0 is the continuation address; x22
    // remains our own context. No unknown callee-buffer write is assumed safe.
    let pc = UInt32(0x1000 + entryWords.count * 4)
    let delta = UInt32(0x2000) - pc
    entryWords.append(0x10000000 | ((delta & 3) << 29) | (((delta >> 2) & 0x7ffff) << 5))
    let branchPC = UInt32(0x1000 + entryWords.count * 4)
    entryWords.append(0x14000000 | ((0x4000 - branchPC) >> 2))
    let entry = try memoryEffectFunction(entryWords, at: 0x1000)
    let resume = try memoryEffectFunction(resumeWords, at: 0x2000)
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


@Test func anUnknownPointerWriteInvalidatesLocalAsyncFacts() throws {
    let words: [UInt32] = [0xd28000e8, 0xf9000ac8, 0xd2800168, 0xf9000008,
                           0xf9400ac0, 0x94000000, 0xd65f03c0]
    let function = try memoryEffectFunction(words, at: 0x1000)
    let entry = MethodEntryConvention.asyncFunclet(base: .swiftFunction(scalarArguments: ["x0": 0]),
        seededRegisters: ["x22": .asyncContext])
    #expect(ValueTracer().analyze(function, entry: entry).callSites[0x1014]?.arguments.first != .immediate(7))
}

@Test func anUnknownPointerWriteInvalidatesDefiniteHandoffFacts() throws {
    let (_, _, _, slots) = try memoryEffectChain([0xd28000e8, 0xf9000ac8, 0xd2800168, 0xf9000008])
    #expect(slots.values.allSatisfy { $0[16] == nil })
}

@Test func nativeUnknownPointerWriteDoesNotRenderStaleAsyncValueIfPresent() async throws {
    let path = "Fixtures/Sample/libAsyncMemoryEffects.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let native = unsafeBitCast(try #require(dlsym(library, "async_memory_pointer")),
        to: (@convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64).self)
    var context: [UInt64] = [0, 0, 0]
    context.withUnsafeMutableBufferPointer { storage in
        #expect(native(storage.baseAddress!) == 11)
        #expect(storage[2] == 11)
    }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "pointerStoreLeaf")
    }
    let leaf = try #require(functions.first)
    #expect(leaf.asyncFunclet?.isEntry == true)
    #expect(!leaf.renderStructured().contains("observe(7)"))
}

private func asyncMemoryObservation(_ words: [UInt32], seeds: [Int: AbstractValue] = [16: .immediate(7)], calleeContext: Bool = false) throws -> AbstractValue {
    let function = try memoryEffectFunction(words, at: 0x1000)
    let entry = MethodEntryConvention.asyncFunclet(base: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]),
        seededRegisters: ["x22": calleeContext ? .asyncCalleeContext : .asyncContext])
    let result = ValueTracer(asyncContextSlots: seeds).analyze(function, entry: entry)
    let address = try #require(function.instructions.first { $0.controlFlow == .call }?.address)
    return result.callSites[address]?.arguments.first ?? .unknown
}

@Test func anUnknownWriteCannotResurrectSeedOnlyAsyncValues() throws {
    for load in [UInt32(0xf9400ac0), UInt32(0xa94106c0)] {
        #expect(try asyncMemoryObservation([0xd2800168, 0xf9000008, load, 0x94000000, 0xd65f03c0]) != .immediate(7))
    }
}

@Test func anUnknownWriteOnEitherPathInvalidatesAsyncSeedsAtTheJoin() throws {
    // cbz x1,load skips the write; its other predecessor may alias slot16.
    #expect(try asyncMemoryObservation([0xb4000061, 0xd2800168, 0xf9000008, 0xf9400ac0, 0x94000000, 0xd65f03c0]) != .immediate(7))
}

@Test func narrowPairedAndAtomicUnknownWritesInvalidateAsyncSeeds() throws {
    for store in [UInt32(0x39000008), UInt32(0x29002408), UInt32(0xf8288009)] {
        #expect(try asyncMemoryObservation([0xd2800168, store, 0xf9400ac0, 0x94000000, 0xd65f03c0]) != .immediate(7))
    }
}

@Test func anOverlappingNarrowContextWriteCannotResurrectASeed() throws {
    #expect(try asyncMemoryObservation([0x52800028, 0x390046c8, 0xf9400ac0, 0x94000000, 0xd65f03c0]) != .immediate(7))
}

@Test func aPairedContextLoadUsesTheLatestLocalStore() throws {
    // Independent native machine execution observes13+17=30.
    let function = try memoryEffectFunction([0xd28001a9, 0xd280022a, 0xa9012ac9, 0xa94106c0, 0x8b010000, 0xd65f03c0], at: 0x1000)
    let entry = MethodEntryConvention.asyncFunclet(base: nil, seededRegisters: ["x22": .asyncContext])
    #expect(ValueTracer().analyze(function, entry: entry).exitValues[0x1014] == .immediate(30))
}

@Test func callerOwnedAndBoundaryCrossingFrameWritesMayAliasAsyncContexts() throws {
    for store in [UInt32(0xf9000be8), UInt32(0xf81fc3e8)] {
        #expect(try asyncMemoryObservation([0xd2800168, store, 0xf9400ac0, 0x94000000, 0xd65f03c0]) != .immediate(7))
    }
}

@Test func aProvenNegativePrivateFrameWritePreservesAsyncFacts() throws {
    #expect(try asyncMemoryObservation([0xd10043ff, 0xd2800168, 0xf90003e8, 0x910043ff,
                                      0xf9400ac0, 0x94000000, 0xd65f03c0]) == .immediate(7))
}

@Test func anExactContextStoreAfterUnknownWriteRecoversItsLocalValue() throws {
    #expect(try asyncMemoryObservation([0xd2800168, 0xf9000008, 0xd28000e8, 0xf9000ac8,
                                      0xf9400ac0, 0x94000000, 0xd65f03c0]) == .immediate(7))
}

@Test func anUnknownWritePreservesAlreadyLoadedScalarSnapshots() throws {
    #expect(try asyncMemoryObservation([0xf9400ad3, 0xd2800168, 0xf9000008, 0xaa1303e0,
                                      0x94000000, 0xd65f03c0]) == .immediate(7))
}

@Test func anUnknownWriteCannotResurrectResumeParent() throws {
    let function = try memoryEffectFunction([0xd2800168, 0xf9000008, 0xf94006c1, 0xd61f0020], at: 0x1000)
    let entry = MethodEntryConvention.asyncFunclet(base: .swiftFunction(scalarArguments: ["x0": 0]), seededRegisters: ["x22": .asyncContext])
    #expect(ValueTracer().analyze(function, entry: entry).indirectControlFlowTargets[0x100c] != .asyncResumeParent)
}

@Test func anUnknownWriteCannotResurrectTheCalleeParentContext() throws {
    #expect(try asyncMemoryObservation([0xf9000001, 0xf94002d3, 0xf9400a60, 0x94000000, 0xd65f03c0], calleeContext: true) != .immediate(7))
}

@Test func aPartialCalleeHeaderWriteCannotResurrectItsParentContext() throws {
    for load in [UInt32(0xf94002c0), UInt32(0xa94006c0)] {
        #expect(try asyncMemoryObservation([0x52800028, 0x390002c8, load, 0x94000000, 0xd65f03c0], calleeContext: true) != .asyncContext)
    }
}

@Test func aDisjointContextStorePreservesResumeParent() throws {
    let function = try memoryEffectFunction([0xd28000e9, 0xf9000ac9, 0xf94006c8, 0xd61f0100], at: 0x1000)
    let entry = MethodEntryConvention.asyncFunclet(base: nil, seededRegisters: ["x22": .asyncContext])
    #expect(ValueTracer().analyze(function, entry: entry).indirectControlFlowTargets[0x100c] == .asyncResumeParent)
}

@Test func aNarrowWriteInvalidatesAnUnalignedCachedContextRange() throws {
    // Native result0x100000007; the earlier7 byte range[20,28) is overwritten.
    let function = try memoryEffectFunction([0xd28000e9, 0x5280002a, 0xf80142c9, 0xb9001aca, 0xf84142c0, 0xd65f03c0], at: 0x1000)
    let entry = MethodEntryConvention.asyncFunclet(base: nil, seededRegisters: ["x22": .asyncContext])
    #expect(ValueTracer().analyze(function, entry: entry).exitValues[0x1014] != .immediate(7))
}

@Test func fullWidthSIMDContextStoresDoNotInventIntegerValues() throws {
    for store in [UInt32(0xfd000ac0), UInt32(0x6d0106c0)] {
        // FMOVd0,#1.0 then STRd0 or STPd0,d1. A general float expression is
        // not the integer bit pattern loaded from its memory representation.
        #expect(try asyncMemoryObservation([0x1e6e1000, store, 0xf9400ac0, 0x94000000, 0xd65f03c0], seeds: [:]) == .unknown)
    }
}

@Test func aPairStraddlingEntrySPMayAliasCallerContextMemory() throws {
    // STPx8,x9,[sp,#-8] writes16bytes, including caller-owned[0,8).
    #expect(try asyncMemoryObservation([0xd2800168, 0xa93fa7e8, 0xf9400ac0, 0x94000000, 0xd65f03c0]) != .immediate(7))
}

@Test func anUnsupportedWidthCannotProveAPrivateFrameWriteDisjoint() throws {
    // STXRw9,x8,[sp] after private allocation. Width is unsupported by
    // accessBytes; a negative base alone must not establish disjointness.
    #expect(try asyncMemoryObservation([0xd10043ff, 0xd2800168, 0xc8097fe8, 0x910043ff,
                                      0xf9400ac0, 0x94000000, 0xd65f03c0]) != .immediate(7))
}

@Test func nativeAsyncMemoryCacheRangesAndBitPatternsIfPresent() throws {
    let path = "Fixtures/Sample/libAsyncMemoryEffects.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Native = @convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64
    for (name, expected) in [("async_memory_pair", UInt64(30)),
                             ("async_memory_unaligned", UInt64(0x100000007)),
                             ("async_memory_simd", UInt64(0x3ff0000000000000))] {
        let native = unsafeBitCast(try #require(dlsym(library, name)), to: Native.self)
        var context: [UInt64] = [0, 0, 0, 0]
        context.withUnsafeMutableBufferPointer { storage in
            #expect(native(storage.baseAddress!) == expected)
            if name == "async_memory_pair" {
                #expect(storage[2] == 13)
                #expect(storage[3] == 17)
            } else if name == "async_memory_unaligned" {
                #expect(storage[2] == 0x700000000)
                #expect(storage[3] == 1)
            } else {
                #expect(storage[2] == expected)
            }
        }
    }
    let st4 = unsafeBitCast(try #require(dlsym(library, "async_memory_st4")),
        to: (@convention(c) () -> UInt64).self)
    // This wrapper initializes a context in its own caller frame; the fragment
    // writes64bytes across entrySP and the wrapper reads the changedslot16.
    #expect(st4() == 0x4444444444444444)

}

@Test func anUnknownWriteInOneResumeInvalidatesLaterResumeSeeds() throws {
    // Entry initializes slot16 and preserves its pointer argument in slot24.
    // The first own-context continuation reloads that argument and may write
    // slot16 through it. The next continuation cannot inherit the old7 proof.
    let entryWords: [UInt32] = [0xd28000e8, 0xf9000ac8, 0xf9000ec0, 0x10007fa0, 0x14000bfc]
    let firstWords: [UInt32] = [0xf9400ec0, 0xd2800168, 0xf9000008, 0x10007fa0, 0x140007fc]
    let secondWords: [UInt32] = [0xf9400ac0, 0xf94006c1, 0xd61f0020]
    var entry = try memoryEffectFunction(entryWords, at: 0x1000)
    entry = DisassembledFunction(symbol: entry.symbol,
        demangledName: "M.entry(Swift.Int) async -> Swift.Int", startAddress: entry.startAddress,
        instructions: entry.instructions, source: .address)
    let raw: [UInt64: DisassembledFunction] = [0x1000: entry,
        0x2000: try memoryEffectFunction(firstWords, at: 0x2000),
        0x3000: try memoryEffectFunction(secondWords, at: 0x3000)]
    let index = AsyncFuncletIndex.build(hints: .init(entries: [0x1000], awaitReturns: [], continuations: [0x2000, 0x3000]),
        functionStarts: Set(raw.keys), instructions: { raw[$0]?.instructions ?? [] },
        nameOf: { $0 == 0x4000 ? "swift_task_switch" : raw[$0]?.displayName })
    try #require(index.chains[0x1000] == [0x1000, 0x2000, 0x3000])
    let functions = raw.mapValues { function in
        index.info(for: function.startAddress, parentName: { raw[$0]?.displayName })
            .map(function.attachingAsyncFunclet) ?? function
    }
    let seeds = Disassembler().asyncChainSlots(index: index, function: { functions[$0] },
        enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())
    #expect(seeds[0x3000]?[16] == nil)
}

@Test func anIncompleteAnalysisCannotProveAbsenceOfAsyncMemoryWrites() throws {
    var words = Array(repeating: UInt32(0xb4000020), count: 20) // cbz x0,next
    words += [0xf9000008, 0xd65f03c0]
    let function = try memoryEffectFunction(words, at: 0x1000)
    var tracer = ValueTracer()
    tracer.iterationsPerBlock = 0
    #expect(tracer.analyze(function).asyncUnboundedMemoryWrites)
}

@Test func anUnknownWideStoreCannotUseAnEightBytePrivateFrameAssumption() throws {
    // Native ST4 writes64bytes from entrySP-8, changing caller contextslot16
    // from7 to0x4444444444444444. A guessed8byte extent would miss the alias.
    #expect(try asyncMemoryObservation([0xd10043ff, 0x910023e0, 0x4c000c00, 0x910043ff,
                                      0xf9400ac0, 0x94000000, 0xd65f03c0]) != .immediate(7))
}

@Test func aCalleeContextOffsetCanAliasOwnContextFacts() throws {
    #expect(try asyncMemoryObservation([0xd2800168, 0xf90012c8, 0xf94002d3,
        0xf9400a60, 0x94000000, 0xd65f03c0], calleeContext: true) != .immediate(7))
}

@Test func anOwnContextOffsetCanAliasTheCalleeParentHeader() throws {
    #expect(try asyncMemoryObservation([0xf94002d3, 0xf81f0261, 0xf94002d3,
        0xf9400a60, 0x94000000, 0xd65f03c0], calleeContext: true) != .immediate(7))
}

@Test func nativeContextOffsetsCanReachTheOtherIdentityIfPresent() throws {
    let path = "Fixtures/Sample/libAsyncMemoryEffects.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Child = @convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64
    typealias Parent = @convention(c) (UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> UInt64
    let child = unsafeBitCast(try #require(dlsym(library, "async_memory_cross_child")), to: Child.self)
    let parent = unsafeBitCast(try #require(dlsym(library, "async_memory_cross_parent")), to: Parent.self)
    var words: [UInt64] = [0, 0, 0, 0, 7, 0, 0, 11]
    words.withUnsafeMutableBufferPointer { storage in
        let base = storage.baseAddress!
        storage[0] = UInt64(UInt(bitPattern: base.advanced(by: 2)))
        #expect(child(base) == 11)
        #expect(storage[4] == 11)
        storage[0] = UInt64(UInt(bitPattern: base.advanced(by: 2)))
        storage[4] = 7
        let replacement = base.advanced(by: 5)
        #expect(parent(base, replacement) == 11)
        #expect(storage[0] == UInt64(UInt(bitPattern: replacement)))
    }
}
