import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A callee that takes stack arguments reads bytes from the sp it was
/// entered with upward, of an extent the call site does not state. A frame
/// address among them escapes whether or not the words below it were
/// stored and however many there are: the padding in front of a
/// 16-byte-aligned argument is a word nothing writes, and a call can pass
/// more than sixteen words. stackhole.s states each body's true behaviour.
private let stackHolePath = "Fixtures/Sample/libStackHole.dylib"

private func stackHoleFunctions() async throws -> [DisassembledFunction]? {
    guard FileManager.default.fileExists(atPath: stackHolePath) else { return nil }
    return try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: stackHolePath)
    }
}

/// What the pipeline states at the one `ret`, and what the tracer alone,
/// with no summary of any callee, holds in x0 there.
private func returned(by symbol: String, in functions: [DisassembledFunction]) throws -> (statement: String, value: AbstractValue) {
    let function = try #require(functions.first { $0.symbol == symbol }, "no \(symbol)")
    let ret = try #require(function.instructions.last { $0.controlFlow == .return })
    let analysis = ValueTracer().analyze(function)
    return (ret.exit?.statement ?? "", analysis.exitValues[ret.address] ?? .unknown)
}

/// The local is 11 after each of these calls. Nothing proves that, so the
/// return is unknown; it is never the 7 stored before the call.
@Test(arguments: [
    "_$s9StackHole6paddedSiyF",       // &local behind a word nothing stored
    "_$s9StackHole11seventeenthSiyF", // &local as the seventeenth word
    "_$s9StackHole6packedSiyF",       // &local behind a byte and a 4-byte word
])
func aLocalWhoseAddressIsAStackArgumentIsNotItsValueBeforeTheCallIfPresent(symbol: String) async throws {
    guard let functions = try await stackHoleFunctions() else { return }
    let result = try returned(by: symbol, in: functions)
    #expect(result.value == .unknown, "\(symbol): \(result.value)")
    #expect(!result.statement.contains("7"), "\(symbol): \(result.statement)")
}

/// The controls: a call whose stack words hold no address leaves the local
/// alone, and so does one whose only copy of the address is in a slot
/// above the prologue's register save area, where no argument can be.
@Test(arguments: ["_$s9StackHole5quietSiyF", "_$s9StackHole7spilledSiyF"])
func aLocalNoStackArgumentAddressesKeepsItsValueIfPresent(symbol: String) async throws {
    guard let functions = try await stackHoleFunctions() else { return }
    let result = try returned(by: symbol, in: functions)
    #expect(result.value == .immediate(7), "\(symbol): \(result.value)")
    #expect(result.statement == "return 7", "\(symbol): \(result.statement)")
}

/// The same shapes as machine words, so the rule is held without the
/// fixture. Each body stores 7 in a local, calls, reloads the local into
/// x2 and calls again: the second call's third argument is what the tracer
/// holds for the local after the first.
private func localAfterCall(_ words: [UInt32], secondCall: UInt64, firstCallee: String? = nil) throws -> AbstractValue {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0)
    try #require(decoded.count == words.count)
    var named = false
    let instructions = decoded.map { insn -> Instruction in
        if insn.controlFlow == .call, !named, let firstCallee {
            named = true
            return Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                               branchTarget: insn.branchTarget, detail: insn.detail, callee: .kept(firstCallee))
        }
        return Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                           branchTarget: insn.branchTarget, detail: insn.detail)
    }
    let function = DisassembledFunction(symbol: "_t", demangledName: "t", startAddress: 0,
                                        instructions: instructions, source: .symbol)
    // A call whose every argument is unknown records no site.
    let arguments = ValueTracer().callSites(in: function)[secondCall]?.arguments ?? []
    return arguments.count > 2 ? arguments[2] : .unknown
}

//   sub sp, sp, #0x40
//   mov x8, #7;  str x8, [sp, #0x30]; str x8, [sp]     local = 7, first stack word = 7
//   add x9, sp, #0x30; str x9, [sp, #0x10]   &local, with [sp, #8] never stored
//   bl f
//   ldr x2, [sp, #0x30]; bl g
//   add sp, sp, #0x40; ret; ret
private let addressPastAnUnstoredWord: [UInt32] = [
    0xd10103ff, 0xd28000e8, 0xf9001be8, 0xf90003e8, 0x9100c3e9, 0xf9000be9, 0x94000005,
    0xf9401be2, 0x94000003, 0x910103ff, 0xd65f03c0, 0xd65f03c0,
]

@Test func aStackWordNothingStoredDoesNotEndTheStackArguments() throws {
    #expect(try localAfterCall(addressPastAnUnstoredWord, secondCall: 0x20) == .unknown)
}

/// The arguments begin at sp. With nothing stored there, a frame address
/// kept in a slot further up is a local of this frame and the callee is
/// not handed it.
@Test func aSlotAboveAnUnstoredFirstWordIsNoStackArgument() throws {
    var words = addressPastAnUnstoredWord
    words[3] = 0xf90007e8   // str x8, [sp, #8]: the first word stays unstored
    #expect(try localAfterCall(words, secondCall: 0x20) == .immediate(7))
}

/// A callee whose signature fits its parameters in registers reads no
/// stack word, wherever the address is stored.
@Test func aCalleeProvenToTakeNoStackArgumentsLeavesTheLocal() throws {
    #expect(try localAfterCall(addressPastAnUnstoredWord, secondCall: 0x20,
                               firstCallee: "M.take(Swift.Int) -> ()") == .immediate(7))
}

@Test func theSeventeenthStackWordIsStillAnArgument() throws {
    //   sub sp, sp, #0xb0
    //   mov x8, #7;  str x8, [sp, #0x90]     local = 7
    //   add x9, sp, #0x90; mov x10, #1
    //   stp x10, x10, [sp] … [sp, #0x70]     sixteen words of 1
    //   str x9, [sp, #0x80]                  &local, the seventeenth
    //   bl f
    //   ldr x2, [sp, #0x90]; bl g
    //   add sp, sp, #0xb0; ret; ret
    #expect(try localAfterCall([
        0xd102c3ff, 0xd28000e8, 0xf9004be8, 0x910243e9, 0xd280002a,
        0xa9002bea, 0xa9012bea, 0xa9022bea, 0xa9032bea, 0xa9042bea, 0xa9052bea, 0xa9062bea, 0xa9072bea,
        0xf90043e9, 0x94000005, 0xf9404be2, 0x94000003, 0x9102c3ff, 0xd65f03c0, 0xd65f03c0,
    ], secondCall: 0x40) == .unknown)
}

@Test func anAddressAboveTheRegisterSaveAreaIsNoStackArgument() throws {
    //   sub sp, sp, #0x40
    //   stp x29, x30, [sp, #0x10]            the save area: arguments end below it
    //   mov x8, #7;  str x8, [sp, #0x28]     local = 7
    //   add x9, sp, #0x28; str x9, [sp, #0x30]   &local kept in a slot above the save area
    //   str x8, [sp]                         one stack word, no address
    //   bl f
    //   ldr x2, [sp, #0x28]; bl g
    //   add sp, sp, #0x40; ret; ret
    #expect(try localAfterCall([
        0xd10103ff, 0xa9017bfd, 0xd28000e8, 0xf90017e8, 0x9100a3e9, 0xf9001be9, 0xf90003e8,
        0x94000005, 0xf94017e2, 0x94000003, 0x910103ff, 0xd65f03c0, 0xd65f03c0,
    ], secondCall: 0x24) == .immediate(7))
}
