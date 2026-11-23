import Foundation
import Testing
import Ccapstone
@testable import SwiftDecompilerCore

/// Same machine body and callee spelling, with independently resolved providers.
/// The second call must only be transparent when its exact runtime ABI is known.
private func resultAfterResolvedARC(_ name: String, provider: String?, cache: ValueTracer.CallFactsCache) throws -> AbstractValue? {
    let engine = try #require(CapstoneEngine())
    let words: [UInt32] = [0x94000400, 0x940007ff, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let body = decoded.map { item in
        var facts = Instruction.Facts()
        if item.address == 0x1004, let provider {
            facts.arcIdentityContract = RuntimeFunctionReference(rawSymbol: "_" + name, libraryName: provider)
                .permitsARCIdentity(named: name)
        }
        return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
            branchTarget: item.branchTarget, detail: item.detail,
            callee: .kept(item.address == 0x1000 ? "make_identity_value" : item.address == 0x1004 ? name : nil),
            facts: facts)
    }
    let function = DisassembledFunction(symbol: "_runtime_origin_control", demangledName: nil,
        startAddress: 0x1000, instructions: body, source: .address)
    var tracer = ValueTracer()
    tracer.callFactsCache = cache
    return tracer.analyze(function, entry: nil).exitValues[0x1008]
}

@Test func arcIdentityDoesNotLeakAcrossSameNamedCallsWithDifferentProviders() throws {
    for name in ["swift_retain", "swift_retain_n", "swift_nonatomic_retain",
                 "swift_bridgeObjectRetain", "swift_bridgeObjectRetain_n",
                 "swift_unknownObjectRetain", "swift_unknownObjectRetain_n",
                 "objc_retain", "objc_autorelease", "objc_retainAutorelease", "objc_retainAutoreleasedReturnValue",
                 "objc_claimAutoreleasedReturnValue", "objc_unsafeClaimAutoreleasedReturnValue",
                 "objc_retainAutoreleaseReturnValue", "objc_autoreleaseReturnValue"] {
        let runtime = name.hasPrefix("swift_") ? "@rpath/libswiftCore.dylib" : "/usr/lib/libobjc.A.dylib"
        for runtimeFirst in [true, false] {
            let cache = ValueTracer.CallFactsCache()
            let providers: [String?] = runtimeFirst
                ? [runtime, "@rpath/libFalseARC.dylib", nil, runtime]
                : ["@rpath/libFalseARC.dylib", runtime, nil, runtime]
            for provider in providers {
                let actual = try resultAfterResolvedARC(name, provider: provider, cache: cache)
                #expect(actual == .callResult(provider == runtime ? 0x1000 : 0x1004),
                        Comment(rawValue: name + " provider=" + (provider ?? "unproved")))
            }
        }
    }
}

@Test func arcIdentityRejectsAProviderOrSymbolFromADifferentContract() throws {
    let cache = ValueTracer.CallFactsCache()
    for (name, provider) in [("swift_retain", "/usr/lib/libobjc.A.dylib"),
                             ("objc_retain", "@rpath/libswiftCore.dylib"),
                             ("swift_retainReturningCount", "@rpath/libswiftCore.dylib"),
                             ("swift_isUniquelyReferenced_nonNull_native", "@rpath/libswiftCore.dylib")] {
        #expect(try resultAfterResolvedARC(name, provider: provider, cache: cache) != .callResult(0x1000))
    }
}

@Test func arcIdentityRequiresTheExactResolvedSymbol() {
    for raw in ["_swift_release", "_swift_retain_n", "_objc_retain", "__swift_retain"] {
        let reference = RuntimeFunctionReference(rawSymbol: raw, libraryName: "/usr/lib/swift/libswiftCore.dylib")
        #expect(!reference.permitsARCIdentity(named: "swift_retain"))
    }
}

@Test func anUnusedUnprovedARCCallRemainsAnEffectInBothRenderers() {
    for trusted in [false, true] {
        var facts = Instruction.Facts()
        facts.arcIdentityContract = trusted
        let function = DisassembledFunction(symbol: "_unused_arc_name", demangledName: nil,
            startAddress: 0x1000, instructions: [
                Instruction(address: 0x1000, text: "bl 0x2000", controlFlow: .call, branchTarget: 0x2000,
                            callArguments: ["arg0", "arg1"], callee: .kept("swift_retain"), facts: facts),
                Instruction(address: 0x1004, text: "ret", controlFlow: .return,
                            facts: Instruction.Facts(exit: .normal("9"))),
            ], source: .address)
        for text in [function.renderPseudo(), function.renderStructured()] {
            #expect(text.contains("swift_retain(") == !trusted, Comment(rawValue: text))
            #expect(text.contains("return 9"), Comment(rawValue: text))
        }
    }
}

@Test func unprovedARCNamesDoNotProveExceptionBehavior() {
    for name in ["swift_retain", "objc_retain", "objc_retain_x19"] {
        for trusted in [false, true] {
            var facts = Instruction.Facts()
            facts.arcIdentityContract = trusted
            let call = Instruction(address: 0x1000, text: "bl 0x2000", controlFlow: .call,
                                   branchTarget: 0x2000, callee: .kept(name), facts: facts)
            #expect(ValueTracer.provablyDoesNotThrow(call) == trusted)
            #expect(ValueTracer.CallFacts(call).provablyDoesNotThrow == trusted)
        }
    }
}

@Test func arcImportIslandsOnlyPrepareScratchRegistersAndTakeTheirJump() throws {
    let engine = try #require(CapstoneEngine())
    func instructions(_ words: [UInt32], at address: UInt64 = 0x1000) -> [Instruction] {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        return engine.disassemble(Data(bytes), address: address).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
    }
    // Actual arm64 stub words: adrp x16; ldr x16,[x16,#32]; br x16.
    let plain = instructions([0x90000030, 0xf9401210, 0xd61f0200])
    #expect(RuntimeFunctionReference.pointerSlot(in: plain, startingAt: 0x1000) == 0x5020)
    let rejected: [[UInt32]] = [
        [0x90000020, 0xf9401210, 0xd61f0200], // writes x0
        [0x90000030, 0xb9401210, 0xd61f0200], // 32-bit load
        [0x90000030, 0xf9001210, 0xd61f0200], // store
        [0x90000030, 0xf9401210, 0xd28000e0, 0xd61f0200], // changes argument x0 after loading the target
        [0x90000030, 0xf9401210, 0xd61f0220], // jumps through x17
        [0x90000030, 0xf9401210, 0xd63f0200], // calls instead of jumping
        [0x90000030, 0xf9401210, 0xd65f03c0], // returns
        [0x90000030, 0xf9401210, 0xd61f0200, 0xd503201f], // incomplete boundary
    ]
    for words in rejected {
        #expect(RuntimeFunctionReference.pointerSlot(in: instructions(words), startingAt: 0x1000) == nil)
    }
    // The cache's arm64e island also prepares x17 for pointer authentication.
    let x16 = PhysReg(kind: .gpr, number: 16, widthBits: 64)
    let x17 = PhysReg(kind: .gpr, number: 17, widthBits: 64)
    func operand(_ value: StructuredOperand) -> StructuredOperandInfo {
        StructuredOperandInfo(operand: value, shift: (AARCH64_SFT_INVALID, 0), extender: AARCH64_EXT_INVALID)
    }
    func instruction(_ id: aarch64_insn, _ operands: [StructuredOperand], _ address: UInt64,
                     flow: ControlFlow = .sequential) -> Instruction {
        Instruction(address: address, text: "", controlFlow: flow,
                    detail: StructuredInsn(id: id, conditionCode: AArch64CC_Invalid, updatesFlags: false,
                                           writeback: false, postIndex: false, operands: operands.map(operand)))
    }
    let authenticated = [
        instruction(AARCH64_INS_ADRP, [.register(x17), .immediate(0x5000)], 0x1000),
        instruction(AARCH64_INS_ADD, [.register(x17), .register(x17), .immediate(32)], 0x1004),
        instruction(AARCH64_INS_LDR, [.register(x16), .memory(base: x17, index: nil, displacement: 0)], 0x1008),
        instruction(AARCH64_INS_BRAA, [.register(x16), .register(x17)], 0x100c, flow: .branch),
    ]
    #expect(RuntimeFunctionReference.pointerSlot(in: authenticated, startingAt: 0x1000) == 0x5020)

    // The actual decoder resynchronizes past an undecodable word. That hole
    // must not disappear from a proof of a complete import island.
    let skipped = instructions([0x90000030, 0xf9401210, 0xffff_ffff, 0xd61f0200])
    let skippedAddresses = skipped.map(\.address)
    try #require(skippedAddresses == [0x1000, 0x1004, 0x100c])
    #expect(RuntimeFunctionReference.pointerSlot(in: skipped, startingAt: 0x1000) == nil)

    let skippedEntry = instructions([0xffff_ffff, 0x90000030, 0xf9401210, 0xd61f0200])
    let skippedEntryAddresses = skippedEntry.map(\.address)
    try #require(skippedEntryAddresses == [0x1004, 0x1008, 0x100c])
    #expect(RuntimeFunctionReference.pointerSlot(in: skippedEntry, startingAt: 0x1000) == nil)
    #expect(RuntimeFunctionReference.pointerSlot(in: skippedEntry, startingAt: 0x1004) == 0x5020)

    let unaligned = instructions([0x90000030, 0xf9401210, 0xd61f0200], at: 0x1001)
    try #require(unaligned.count == 3)
    #expect(RuntimeFunctionReference.pointerSlot(in: unaligned, startingAt: 0x1001) == nil)

}
