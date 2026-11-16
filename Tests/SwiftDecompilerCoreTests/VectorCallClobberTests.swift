import Ccapstone
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif
@testable import SwiftDecompilerCore

/// AAPCS64 preserves d8-d15, not q8-q15. A tracked vector's high lane
/// cannot be reused after a call, even when its low lane stays known.
@Test func aCallPreservesOnlyTheLowLaneOfACalleeSavedVector() {
    let before = AbstractValue.aggregate([.immediate(7), .immediate(19)])
    let after = AbstractValue.aggregate([.immediate(7), .unknown])
    #expect(ValueTracer.callPreservedVectorValue(before) == after)
    #expect(ValueTracer.callPreservedVectorValue(after) == after)
    #expect(ValueTracer.scalarView(after, bits: 64) == .immediate(7))
    #expect(ValueTracer.callPreservedVectorValue(.aggregate([])) == .unknown)
    // A scalar is the register with a zero high lane; after a call only its
    // low lane is known, and a narrower view of it is still the scalar.
    #expect(ValueTracer.callPreservedVectorValue(.unknown) == .unknown)
    for scalar: AbstractValue in [.immediate(7), .argument(0), .loaded(0x4000)] {
        let kept = ValueTracer.callPreservedVectorValue(scalar)
        #expect(kept == .aggregate([scalar]))
        #expect(ValueTracer.scalarView(kept, bits: 64) == scalar)
        #expect(ValueTracer.scalarView(kept, bits: 32) == scalar)
        // A second call leaves it as the first did.
        #expect(ValueTracer.callPreservedVectorValue(kept) == kept)
    }
    let joined = AbstractValue.select(condition: .argument(0), whenTrue: before,
                                     whenFalse: .aggregate([.immediate(11), .immediate(23)]))
    #expect(ValueTracer.callPreservedVectorValue(joined) == .select(
        condition: .argument(0), whenTrue: after,
        whenFalse: .aggregate([.immediate(11), .unknown])))
}

private func vectorCallOperand(_ value: StructuredOperand) -> StructuredOperandInfo {
    StructuredOperandInfo(operand: value, shift: (AARCH64_SFT_INVALID, 0), extender: AARCH64_EXT_INVALID)
}

private func vectorCallDetail(_ id: aarch64_insn, _ operands: [StructuredOperand]) -> StructuredInsn {
    StructuredInsn(id: id, conditionCode: AArch64CC_Invalid, updatesFlags: false,
                   writeback: false, postIndex: false, operands: operands.map(vectorCallOperand))
}

/// Seed a vector, call an unknown function, spill the vector and reload one
/// lane as the result. The synthetic body reaches the real transfer and
/// stack-store paths with values no instruction in the fixture produces.
private func vectorAcrossCalls(
    register: Int, value: AbstractValue, lane: Int, calls: Int = 1, indirect: Bool = false,
    storeBits: Int = 128, clobbered: Bool = false
) -> (analysis: FunctionAnalysis, store: UInt64, exit: UInt64) {
    var instructions: [Instruction] = []
    for index in 0..<calls {
        instructions.append(Instruction(address: 0x1000 + UInt64(index * 4),
            text: indirect ? "blr x16" : "bl 0x2000", controlFlow: .call,
            branchTarget: indirect ? nil : 0x2000))
    }
    let store = UInt64(0x1000 + calls * 4)
    let sp = PhysReg(kind: .stackPointer, number: 31, widthBits: 64)
    let vector = PhysReg(kind: .vector, number: register, widthBits: storeBits)
    let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
    instructions += [
        Instruction(address: store, text: "str \(storeBits == 128 ? "q" : "d")\(register), [sp]",
            detail: vectorCallDetail(AARCH64_INS_STR, [
                .register(vector), .memory(base: sp, index: nil, displacement: 0),
            ])),
        Instruction(address: store + 4, text: "ldr x0, [sp, #\(lane * 8)]",
            detail: vectorCallDetail(AARCH64_INS_LDR, [
                .register(x0), .memory(base: sp, index: nil, displacement: Int64(lane * 8)),
            ])),
        Instruction(address: store + 8, text: "ret", controlFlow: .return),
    ]
    let function = DisassembledFunction(symbol: "_vectorAcrossCalls", demangledName: nil,
        startAddress: 0x1000, instructions: instructions, source: .symbol)
    var tracer = ValueTracer()
    if clobbered { tracer.calleeClobbers = [0x2000: ["v\(register)"]] }
    let analysis = tracer.analyze(function, entry: .swiftValueInstance(seededRegisters: ["v\(register)": value]))
    return (analysis, store, store + 8)
}

@Test func directAndIndirectCallsForgetCalleeSavedVectorHighLanes() throws {
    for register in 8...15 {
        for indirect in [false, true] {
            for calls in [1, 2] {
                let value = AbstractValue.aggregate([.immediate(7), .immediate(19)])
                let high = vectorAcrossCalls(register: register, value: value, lane: 1,
                                            calls: calls, indirect: indirect)
                #expect(high.analysis.exitValues[high.exit] == nil)
                #expect(try #require(high.analysis.memoryWrites[high.store]).values
                        == [.aggregate([.immediate(7), .unknown])])
                let low = vectorAcrossCalls(register: register, value: value, lane: 0,
                                           calls: calls, indirect: indirect)
                #expect(low.analysis.exitValues[low.exit] == .immediate(7))
            }
        }
    }
}

@Test func vectorCallClobberingKeepsScalarAndNoCallControls() {
    for register in 8...15 {
        let value = AbstractValue.aggregate([.immediate(7), .immediate(19)])
        let noCall = vectorAcrossCalls(register: register, value: value, lane: 1, calls: 0)
        #expect(noCall.analysis.exitValues[noCall.exit] == .immediate(19))
        let scalar = vectorAcrossCalls(register: register, value: .immediate(7), lane: 0, storeBits: 64)
        #expect(scalar.analysis.exitValues[scalar.exit] == .immediate(7))
        let clobbered = vectorAcrossCalls(register: register, value: value, lane: 0, clobbered: true)
        #expect(clobbered.analysis.exitValues[clobbered.exit] == nil)
    }
    // Adjacent caller-saved registers keep no lane at all.
    for register in [7, 16, 31] {
        for lane in 0...1 {
            let result = vectorAcrossCalls(register: register,
                value: .aggregate([.immediate(7), .immediate(19)]), lane: lane)
            #expect(result.analysis.exitValues[result.exit] == nil)
        }
    }
}

@Test func aJoinedVectorForgetsBothPossibleUpperLanesAcrossACall() throws {
    let before = AbstractValue.select(condition: .argument(0),
        whenTrue: .aggregate([.immediate(7), .immediate(19)]),
        whenFalse: .aggregate([.immediate(11), .immediate(23)]))
    let after = AbstractValue.select(condition: .argument(0),
        whenTrue: .aggregate([.immediate(7), .unknown]),
        whenFalse: .aggregate([.immediate(11), .unknown]))
    for indirect in [false, true] {
        let high = vectorAcrossCalls(register: 8, value: before, lane: 1, indirect: indirect)
        #expect(try #require(high.analysis.memoryWrites[high.store]).values == [after])
        #expect(high.analysis.exitValues[high.exit] == nil)
    }
    // The tracer does not yet project individual lanes from a select of
    // whole vectors. This checks the actual call transfer without claiming
    // that a selected low lane is recoverable through a subsequent spill.
}

/// Instructions from vectorcallclobber.s, independently assembled by clang
/// for arm64-apple-macosx15.0. Unlike seeded values, MOVI here must reach the
/// real decoder, transfer, call clobber, vector spill and scalar reload paths.
@Test func aDecodedVectorCallDoesNotReturnItsPreCallHighLane() throws {
    let engine = try #require(CapstoneEngine())
    func returnedValue(_ words: [UInt32]) throws -> AbstractValue? {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let function = DisassembledFunction(symbol: "_decodedVectorCall", demangledName: nil,
            startAddress: 0x1000, instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .symbol)
        return ValueTracer().analyze(function, entry: nil).exitValues[try #require(decoded.last).address]
    }
    // Save d8, zero q8, call a helper, spill q8, load one lane, restore d8.
    let prefix: [UInt32] = [0xa9bd7bfd, 0x910003fd, 0xfd000be8, 0x6f00e408]
    let suffix: [UInt32] = [0xfd400be8, 0xa8c37bfd, 0xd65f03c0]
    #expect(try returnedValue(prefix + [0x94000019, 0x3d800be8, 0xf94017e0] + suffix) == nil)
    #expect(try returnedValue(prefix + [0x94000019, 0x3d800be8, 0xf94013e0] + suffix) == .immediate(0))
    #expect(try returnedValue(prefix + [0x3d800be8, 0xf94017e0] + suffix) == .immediate(0))
}

private let vectorCallFixture = "Fixtures/Sample/libVectorCallClobber.dylib"

@Test func vectorCallHighLanesAreNotFabricatedInWholeOrFilteredOutputIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: vectorCallFixture) else { return }
    for filter: String? in [nil, "VectorCallClobber"] {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: vectorCallFixture, functionFilter: filter)
        }
        func output(_ name: String) throws -> String {
            try #require(functions.first { $0.displayName.hasPrefix("VectorCallClobber.\(name)(") })
                .renderStructured()
        }
        // The high lane is gone, whichever way it is read. `untouched` calls
        // a helper that keeps it, but no summary covers v8: declined, not wrong.
        for name in ["high", "umovHigh", "untouched"] {
            let text = try output(name)
            #expect(text.contains("return ?"), Comment(rawValue: text))
        }
        // The low 64 bits are what the ABI preserves.
        #expect(try output("low").contains("return 0"))
        #expect(try output("scalar").contains("return 7"))
        #expect(try output("dupLow").contains("return 7"))
        #expect(try output("noCall").contains("return 0"))
    }
}

#if canImport(Darwin)
/// Native oracle: the fixture run on this machine, so the helper really does
/// change the high lane the renders above decline.
@Test func vectorCallHighLaneNativeOracleIfPresent() throws {
    #if arch(arm64)
    guard FileManager.default.fileExists(atPath: vectorCallFixture) else { return }
    let handle = try #require(dlopen(vectorCallFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    for (name, result) in [("4high", 19), ("8umovHigh", 19), ("3low", 0), ("6noCall", 0),
                           ("6scalar", 7), ("6dupLow", 7), ("9untouched", 0)] {
        let pointer = try #require(dlsym(handle, "$s17VectorCallClobber\(name)SiyF"))
        let call = unsafeBitCast(pointer, to: (@convention(c) () -> Int).self)
        #expect(call() == result)
    }
    #endif
}
#endif
