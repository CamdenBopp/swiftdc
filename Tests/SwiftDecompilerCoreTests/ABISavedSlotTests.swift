import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func savedSlotFunction(_ words: [UInt32]) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_savedSlots", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

// sub sp, sp, #48; stp x19, x20, [sp, #16]; mov x19, x0; mov x20, x1;
// <store>; ldp x19, x20, [sp, #16]; add sp, sp, #48; ret.
// x19 is saved in [sp+16, sp+24), x20 in [sp+24, sp+32).
private func savedSlotClobbers(store: UInt32) throws -> Set<String> {
    let function = try savedSlotFunction([
        0xd100c3ff, 0xa90153f3, 0xaa0003f3, 0xaa0103f4,
        store, 0xa94153f3, 0x9100c3ff, 0xd65f03c0,
    ])
    return try #require(CalleeRegisterSummary.of(function)).clobberedCalleeSaved
}

@Test func abiSavedSlotsInvalidateAllOverlappingBytes() throws {
    let cases: [(UInt32, Set<String>, String)] = [
        (0x39004fe2, ["x19"], "strb w2, [sp, #19]"),
        (0x79002fe2, ["x19"], "strh w2, [sp, #22]"),
        (0x380133e2, ["x19"], "sturb w2, [sp, #19]"),
        (0x780173e2, ["x19", "x20"], "sturh w2, [sp, #23]: crosses both saves"),
        (0xb90017e2, ["x19"], "str w2, [sp, #20]"),
        (0xf80143e2, ["x19", "x20"], "stur x2, [sp, #20]: crosses both saves"),
        (0x3d8007e0, ["x19", "x20"], "str q0, [sp, #16]: covers both saves"),
        (0x29018fe2, ["x19"], "stp w2, w3, [sp, #12]: four-byte stride"),
        (0xad0007e0, ["x19", "x20"], "stp q0, q1, [sp]: sixteen-byte stride"),
        (0xa8010fe2, ["x19", "x20"], "stnp x2, x3, [sp, #16]"),
    ]
    for (word, expected, lowering) in cases {
        #expect(try savedSlotClobbers(store: word) == expected, Comment(rawValue: lowering))
    }
}

@Test func abiSavedSlotsKeepDisjointWritesAndWholeRegisterSaves() throws {
    // A byte and a four-byte word ending immediately before a save, and writes
    // immediately after both saves, are disjoint despite their nearby starts.
    // The old +/-4 invalidation falsely clobbered the preceding word's save.
    for store: UInt32 in [0x39003fe2, 0xb9000fe2, 0xf90013e2, 0x3d800be0] {
        #expect(try savedSlotClobbers(store: store).isEmpty)
    }
    // sub sp, sp, #32; stnp x19, x20, [sp]; overwrite x19/x20;
    // ldp x19, x20, [sp]; add sp, sp, #32; ret.
    let nonTemporalSave = try savedSlotFunction([
        0xd10083ff, 0xa80053f3, 0xaa0003f3, 0xaa0103f4,
        0xa94053f3, 0x910083ff, 0xd65f03c0,
    ])
    #expect(try #require(CalleeRegisterSummary.of(nonTemporalSave)).clobberedCalleeSaved.isEmpty)
    // Standard full-width STP saves remain proven when no store intervenes.
    #expect(try savedSlotClobbers(store: 0xd503201f).isEmpty) // nop
}

@Test func abiSavedSlotsKeepSupportedLoadsWithoutMemoryFlags() throws {
    // str x19, [sp, #-16]!; mov x19, x0; <load x19>; add sp, sp, #16; ret.
    for load: UInt32 in [0xf94003f3, 0xf84003f3, 0xa94053f3] { // ldr, ldur, ldp
        let original = try savedSlotFunction([0xf81f0ff3, 0xaa0003f3, load, 0x910043ff, 0xd65f03c0])
        let instructions = original.instructions.map { insn -> Instruction in
            guard insn.address == 0x1008, let detail = insn.detail else { return insn }
            let noMemoryFlags = StructuredInsn(
                id: detail.id, conditionCode: detail.conditionCode, updatesFlags: detail.updatesFlags,
                writeback: detail.writeback, postIndex: detail.postIndex,
                operands: detail.operands.map { info in
                    StructuredOperandInfo(operand: info.operand, shift: info.shift, extender: info.extender,
                                          access: info.operand.isMemory ? 0 : info.access)
                })
            return Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                               branchTarget: insn.branchTarget, detail: noMemoryFlags)
        }
        let function = DisassembledFunction(symbol: original.symbol, demangledName: nil,
            startAddress: original.startAddress, instructions: instructions, source: .symbol)
        // LDP also writes x20, whose unsaved incoming value is unproven; x19's
        // supported full-width reload must survive zero memory access flags.
        #expect(!((try #require(CalleeRegisterSummary.of(function))).clobberedCalleeSaved.contains("x19")))
    }
}

@Test func abiSavedSlotsDoNotReuseFloatingRegisterSaveFacts() throws {
    // A D-register load can copy the saved bits, but this summary does not
    // track FP arithmetic/writes. FMOV overwrites d0 before its store, so that
    // store must not re-establish the old saved entry value.
    let function = try savedSlotFunction([
        0xd10083ff, 0xf9000bf3, 0xaa0003f3, 0xfd400be0, 0x1e6e1000,
        0xfd000be0, 0xf9400bf3, 0x910083ff, 0xd65f03c0,
    ])
    #expect(try #require(CalleeRegisterSummary.of(function)).clobberedCalleeSaved == ["x19"])
}

@Test func abiSavedSlotsDeclineUnknownStackWrites() throws {
    // str x2, [sp, x3]: an unknown index can overwrite either save.
    #expect(try savedSlotClobbers(store: 0xf8236be2) == ["x19", "x20"])
    // stlr x2, [sp]: the unsupported store's extent is not modelled, so all
    // saves conservatively decline. Its missing access flags cannot prove safety.
    #expect(try savedSlotClobbers(store: 0xc89fffe2) == ["x19", "x20"])
    // Existing non-aliasing assumption: an incoming non-stack pointer does not
    // reach this function's register save area.
    #expect(try savedSlotClobbers(store: 0xf9000082).isEmpty) // str x2, [x4]
}

private let savedSlotFixture = "Fixtures/Sample/libABISavedSlots.dylib"

@Test func abiSavedSlotNativeOracleIfPresent() throws {
    guard FileManager.default.fileExists(atPath: savedSlotFixture) else { return }
    let handle = try #require(dlopen(savedSlotFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let bytePointer = try #require(dlsym(handle, "$s13ABIStackSlots12narrowCalleryS2i_SitF"))
    let overlapPointer = try #require(dlsym(handle, "$s13ABIStackSlots13overlapCalleryS2i_SitF"))
    let byte = unsafeBitCast(bytePointer, to: (@convention(thin) (Int, Int) -> Int).self)
    let overlap = unsafeBitCast(overlapPointer, to: (@convention(thin) (Int, Int) -> Int).self)
    for seed: UInt in [0, 0x1122334455667788, .max, 1 << 63] {
        for replacement: UInt in [0, 0xaa, 0xaabbccdd, .max] {
            let byteExpected = (seed & ~(UInt(0xff) << 24)) | ((replacement & 0xff) << 24)
            let overlapExpected = (seed & 0xffffffff) | ((replacement & 0xffffffff) << 32)
            #expect(UInt(bitPattern: byte(Int(bitPattern: seed), Int(bitPattern: replacement))) == byteExpected)
            #expect(UInt(bitPattern: overlap(Int(bitPattern: seed), Int(bitPattern: replacement))) == overlapExpected)
        }
    }
}

@Test func abiSavedSlotCallersDeclineTheirChangedResultIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: savedSlotFixture) else { return }
    // Both the unfiltered external listing and filtered Capstone entry points
    // must propagate the fragment's clobber into caller return rendering.
    for filter: String? in [nil, "ABIStackSlots"] {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: savedSlotFixture, functionFilter: filter)
        }
        let callers = functions.filter { $0.displayName.hasPrefix("ABIStackSlots.") }
        #expect(callers.count == 2)
        for function in callers {
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("return ?"), Comment(rawValue: text))
                #expect(!text.contains("return arg0"), Comment(rawValue: text))
                #expect(text.contains("abi_saved_"), Comment(rawValue: text))
            }
        }
    }
}
