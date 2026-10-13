import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func aliasEscapeFunction(_ words: [UInt32]) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x2000)
    #expect(decoded.count == words.count)
    return .init(symbol: "resume", demangledName: nil, startAddress: 0x2000,
        instructions: decoded.map { Instruction(address: $0.address, text: $0.text,
            controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }, source: .address)
}

@Test func storingAnAsyncContextPointerCannotLeaveAConstantProof() throws {
    // The independent ARM64 oracle in async_alias_escape.s starts
    // slot16 at7, spills/reloads its context pointer, mutates through it and
    // returns18. A memory spill must not erase the possibility of mutation.
    let function = try aliasEscapeFunction([
        0xf94002d3, // ldr x19,[x22]
        0xf90013f3, // str x19,[sp,#32]
        0xf94013f4, // ldr x20,[sp,#32]
        0x91004280, // add x0,x20,#16
        0x94001000, // bl mutate
        0xf9400a80, // ldr x0,[x20,#16]
        0xd65f03c0,
    ])
    #expect(AsyncContextEscapes().lowestOffset(in: function) == Int.min)
}

@Test func anAsyncContextCopiedToFramePointerCannotLoseItsAlias() throws {
    let function = try aliasEscapeFunction([
        0xf94002d3, // ldr x19,[x22]
        0xaa1303fd, // mov x29,x19
        0x910043a0, // add x0,x29,#16
        0x94001000, 0xd65f03c0,
    ])
    #expect(AsyncContextEscapes().lowestOffset(in: function) != nil)
}

@Test func aNarrowWriteCannotPreserveOverlappingAsyncSlot() throws {
    let function = try aliasEscapeFunction([
        0xf94002d3, // ldr x19,[x22]
        0x52800028, // mov w8,#1
        0x39004668, // strb w8,[x19,#17]: slot16 becomes263, not7
        0xf9400a60, // ldr x0,[x19,#16]
        0xd65f03c0,
    ])
    #expect((AsyncContextEscapes().lowestOffset(in: function) ?? Int.max) <= 16)
}

@Test func indexedAsyncContextWritesCannotLeaveConstantProofs() throws {
    let function = try aliasEscapeFunction([
        0xf94002d3, // ldr x19,[x22]
        0xf8206a68, // str x8,[x19,x0]
        0xd65f03c0,
    ])
    #expect(AsyncContextEscapes().lowestOffset(in: function) == Int.min)
}

private func chainSlotsForAliasResume(_ words: [UInt32]) throws -> [Int: AbstractValue] {
    let engine = try #require(CapstoneEngine())
    let entryWords: [UInt32] = [
        0xd28000e8, 0xf9000ac8, 0x94000000, 0x10007fa9,
        0xf9000409, 0xaa0003f6, 0x14000bfa,
    ]
    let bytes = entryWords.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    let entry = DisassembledFunction(symbol: "entry", demangledName: "M.entry() async -> Swift.Int", startAddress: 0x1000,
        instructions: decoded.map { Instruction(address: $0.address, text: $0.text,
            annotation: $0.controlFlow == .call ? "swift_task_alloc" : nil,
            controlFlow: $0.controlFlow, branchTarget: $0.controlFlow == .call ? nil : $0.branchTarget,
            detail: $0.detail) }, source: .address)
    let resume = try aliasEscapeFunction(words)
    let raw = [UInt64(0x1000): entry, UInt64(0x2000): resume]
    let index = AsyncFuncletIndex.build(hints: .init(entries: [0x1000], awaitReturns: [0x2000]),
        functionStarts: Set(raw.keys), instructions: { raw[$0]?.instructions ?? [] },
        nameOf: { $0 == 0x4000 ? "M.callee() async -> Swift.Int" : raw[$0]?.displayName })
    try #require(index.chains[0x1000] == [0x1000, 0x2000])
    let functions = raw.mapValues { function in
        index.info(for: function.startAddress, parentName: { raw[$0]?.displayName })
            .map(function.attachingAsyncFunclet) ?? function
    }
    return Disassembler().asyncChainSlots(index: index, function: { functions[$0] },
        enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())[0x2000] ?? [:]
}

@Test func aSpilledContextAliasInvalidatesChainWideSlotProofs() throws {
    #expect(try chainSlotsForAliasResume([
        0xf94002d3, 0xf90013f3, 0xf94013f4, 0x91004280,
        0x94001000, 0xf9400a80, 0xd65f03c0,
    ])[16] == nil)
}

@Test func aByteWriteInvalidatesChainWideOverlappingSlotProofs() throws {
    #expect(try chainSlotsForAliasResume([
        0xf94002d3, 0x52800028, 0x39004668, 0xf9400a60, 0xd65f03c0,
    ])[16] == nil)
}

@Test func nativeAsyncContextAliasesAndByteWritesReallyModifySlotsIfPresent() throws {
    let path = "Fixtures/Sample/libAsyncAliasEscape.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Oracle = @convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64
    for (name, expected) in [("async_alias_spill", UInt64(18)), ("async_alias_byte", UInt64(263)), ("async_alias_interior", UInt64(18)), ("async_alias_unaligned", UInt64(263)), ("async_alias_fmov", UInt64(18)), ("async_alias_vector_load", UInt64(18))] {
        let pointer = try #require(dlsym(library, name))
        let oracle = unsafeBitCast(pointer, to: Oracle.self)
        var own: [UInt64] = [0, 0, 7, 0]
        own.withUnsafeMutableBufferPointer { storage in
            var callee: UInt64 = UInt64(UInt(bitPattern: storage.baseAddress!))
            let result = withUnsafeMutablePointer(to: &callee) { oracle($0) }
            #expect(result == expected)
            #expect(storage[2] == expected)
        }
    }
}

@Test func aConditionalContextCopyCannotLoseEitherInputAlias() throws {
    for copy in [UInt32(0x9a9f02d3), UInt32(0x9a9603f3)] {
        // csel x19,x22,xzr,eq / csel x19,xzr,x22,eq
        let function = try aliasEscapeFunction([copy, 0x91004260, 0x94001000, 0xd65f03c0])
        #expect(AsyncContextEscapes().lowestOffset(in: function) == Int.min)
    }
}

@Test func anInteriorContextPointerCannotProveLowerSlotsUnchanged() throws {
    // Callee at pointer24 can store at -8; it modifies slot16 from7 to18.
    let words: [UInt32] = [0xf94002d3, 0x91006260, 0x94001000, 0xf9400a60, 0xd65f03c0]
    #expect(AsyncContextEscapes().lowestOffset(in: try aliasEscapeFunction(words)) == Int.min)
    #expect(try chainSlotsForAliasResume(words)[16] == nil)
}

@Test func anUnalignedWideWriteCannotPreserveOverlappingAsyncSlots() throws {
    let words: [UInt32] = [0xf94002d3, 0xd2800028, 0xf8011268, 0xf9400a60, 0xd65f03c0]
    // stur x8,[x19,#17] overlaps the earlier aligned slot16 store.
    #expect(AsyncContextEscapes().lowestOffset(in: try aliasEscapeFunction(words)) == Int.min)
    #expect(try chainSlotsForAliasResume(words)[16] == nil)
}

@Test func unsupportedStoreWidthsCannotPreserveAsyncSlotProofs() throws {
    for store in [UInt32(0x3d800660), UInt32(0x29022668)] {
        // str q0,[x19,#16] / stp w8,w9,[x19,#16]
        let words: [UInt32] = [0xf94002d3, store, 0xf9400a60, 0xd65f03c0]
        #expect(AsyncContextEscapes().lowestOffset(in: try aliasEscapeFunction(words)) == Int.min)
        #expect(try chainSlotsForAliasResume(words)[16] == nil)
    }
}

@Test func asyncContextCopiesToOtherRegisterBanksCannotLoseTheirAlias() throws {
    for copy in [UInt32(0x9e670260), UInt32(0x9100027f)] {
        // fmov d0,x19 / mov sp,x19. The independent native FMOV round trip
        // changes slot16 from7 to18 after copying d0 back into x20.
        let words: [UInt32] = [0xf94002d3, copy, 0x9e660014, 0x91004280,
                              0x94001000, 0xf9400a80, 0xd65f03c0]
        #expect(AsyncContextEscapes().lowestOffset(in: try aliasEscapeFunction(words)) == Int.min)
        #expect(try chainSlotsForAliasResume(words)[16] == nil)
    }
}

@Test func nonIntegerOrPartialParentPointerLoadsCannotLoseAliases() throws {
    for load in [UInt32(0xfd4002c0), UInt32(0x3dc002c0), UInt32(0xb94002d3), UInt32(0x384012d3)] {
        // ldr d0/q0/w19,[x22] / ldurb w19,[x22,#1]. The parent pointer
        // can be moved or reconstructed into a GPR and used to mutate slot16.
        let words: [UInt32] = [load, 0x9e660014, 0x91004280, 0x94001000, 0xf9400a80, 0xd65f03c0]
        #expect(AsyncContextEscapes().lowestOffset(in: try aliasEscapeFunction(words)) == Int.min)
        #expect(try chainSlotsForAliasResume(words)[16] == nil)
    }
}

@Test func indexedParentPointerLoadsCannotLeaveChainWideConstants() throws {
    // ldr x20,[x22,x0] reads the parent pointer when x0 is zero.
    let words: [UInt32] = [0xf8606ad4, 0x91004280, 0x94001000, 0xf9400a80, 0xd65f03c0]
    #expect(AsyncContextEscapes().lowestOffset(in: try aliasEscapeFunction(words)) == Int.min)
    #expect(try chainSlotsForAliasResume(words)[16] == nil)
}
