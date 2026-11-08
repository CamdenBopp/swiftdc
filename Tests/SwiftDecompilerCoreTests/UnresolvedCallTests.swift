import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

/// An unresolved target is still a real effectful instruction. In particular,
/// authenticated block invokes can consume all the named calls above them;
/// dropping the invoke then makes a nonempty method look like a bare return.
@Test func unresolvedCallsRemainVisibleWithRecoveredOperands() throws {
    for opcode in ["blr x9", "blraa x9, x8", "bl 0x7000"] {
        let instruction = Instruction(
            address: 0x1010, text: opcode, controlFlow: .call,
            callArguments: ["[Request new]", "arg0"]
        )
        let rendered = try #require(DisassembledFunction.callStatement(of: instruction, hideRuntime: true))
        #expect(rendered.contains("unresolved call @ 0x1010"))
        #expect(rendered.contains("[Request new]"))
        #expect(rendered.contains("arg0"))
        // Register values are observations, not proof of the unknown callee's arity.
        #expect(rendered.contains("recovered_args:"))
    }
}

@Test func consumedUnresolvedCallStillHasAnEffectStatement() {
    let instruction = Instruction(
        address: 0x1020, text: "blraa x9, x8", controlFlow: .call,
        callArguments: ["arg0"], resultConsumed: true
    )
    #expect(DisassembledFunction.callStatement(of: instruction, hideRuntime: true) != nil)
}

@Test func unresolvedCallsPreventFalseLeafPseudoOutput() {
    let function = DisassembledFunction(
        symbol: "unknownInvoke", demangledName: nil, startAddress: 0x1000,
        instructions: [Instruction(address: 0x1000, text: "blr x9", controlFlow: .call)],
        source: .symbol
    )
    #expect(function.renderPseudo().contains("unresolved call"))
    #expect(!function.renderPseudo().contains("leaf / pure computation"))
}

@Test func unresolvedBranchIsNotInventedAsACall() {
    let branch = Instruction(address: 0x1000, text: "b 0x1010", controlFlow: .branch, branchTarget: 0x1010)
    #expect(DisassembledFunction.callStatement(of: branch, hideRuntime: true) == nil)
    let consumedKnown = Instruction(address: 0x1004, text: "bl _make", controlFlow: .call, resultConsumed: true)
    #expect(DisassembledFunction.callStatement(of: consumedKnown, hideRuntime: true) == nil)
}
