import Foundation
import Testing
@testable import SwiftDecompilerCore

private func loopSwitchBranch(_ address: UInt64, to target: UInt64) -> Instruction {
    Instruction(address: address, text: "b 0x\(String(target, radix: 16))",
                controlFlow: .branch, branchTarget: target)
}

private func loopSwitchTest(_ address: UInt64, to target: UInt64) -> Instruction {
    Instruction(address: address, text: "cbz x0, 0x\(String(target, radix: 16))",
                controlFlow: .conditionalBranch, branchTarget: target)
}

private func loopSwitchDispatch(_ address: UInt64, cases: [UInt64]) -> BasicBlock {
    BasicBlock(startAddress: address,
               instructions: [Instruction(address: address, text: "br x16", controlFlow: .branch)],
               successors: Array(Set(cases)).sorted(), switchCases: cases)
}

private func loopSwitchExit(_ address: UInt64 = 0x400) -> BasicBlock {
    BasicBlock(startAddress: address, instructions: [
        Instruction(address: address, text: "str x0, [x1]", annotation: "self.finished = 1"),
        Instruction(address: address + 4, text: "ret", controlFlow: .return),
    ], successors: [])
}

private func renderLoopSwitch(_ blocks: [BasicBlock], maxDepth: Int = ControlFlowStructure.defaultMaxDepth) -> String {
    ControlFlowStructure(blocks: blocks, maxDepth: maxDepth)
        .renderLines(header: "loopSwitch() {", objcLine: nil).joined(separator: "\n")
}

/// Case 0 leaves the enclosing loop; case 1 takes its back edge. A bare break
/// in case 0 exits only the switch, then reaches the end of while(true) and
/// repeats forever instead of running the exit's side effect and returning.
@Test func switchCaseTransfersToTheEnclosingLoopExit() {
    let text = renderLoopSwitch([
        BasicBlock(startAddress: 0x100, instructions: [loopSwitchBranch(0x100, to: 0x200)], successors: [0x200]),
        loopSwitchDispatch(0x200, cases: [0x400, 0x300]),
        BasicBlock(startAddress: 0x300, instructions: [loopSwitchBranch(0x300, to: 0x100)], successors: [0x100]),
        loopSwitchExit(),
    ])
    #expect(text.contains("case 0:\n            goto loc_400"), "\(text)")
    #expect(text.contains("loc_400:"), "\(text)")
    #expect(text.contains("case 1:\n            continue"), "\(text)")
    #expect(text.components(separatedBy: "self.finished = 1").count == 2, "\(text)")
}

/// The switch's scope must persist through a conditional case body: leaving
/// the loop from that nested if still cannot use the switch's bare break.
@Test func branchInsideSwitchCaseTransfersToTheEnclosingLoopExit() {
    let text = renderLoopSwitch([
        BasicBlock(startAddress: 0x100, instructions: [loopSwitchBranch(0x100, to: 0x200)], successors: [0x200]),
        loopSwitchDispatch(0x200, cases: [0x250, 0x300]),
        BasicBlock(startAddress: 0x250, instructions: [loopSwitchTest(0x250, to: 0x400)], successors: [0x400, 0x300]),
        BasicBlock(startAddress: 0x300, instructions: [loopSwitchBranch(0x300, to: 0x100)], successors: [0x100]),
        loopSwitchExit(),
    ])
    #expect(text.contains("if (x0 == 0) {\n                goto loc_400"), "\(text)")
    #expect(text.contains("loc_400:"), "\(text)")
    #expect(!text.contains("                break"), "\(text)")
}

/// An ordinary (non-switch) loop exit keeps the concise break spelling.
@Test func ordinaryLoopExitStillUsesBreak() {
    let text = renderLoopSwitch([
        BasicBlock(startAddress: 0x100, instructions: [
            Instruction(address: 0x100, text: "str x0, [x1]", annotation: "self.headVisits += 1"),
            loopSwitchTest(0x104, to: 0x400),
        ], successors: [0x400, 0x200]),
        BasicBlock(startAddress: 0x200, instructions: [
            Instruction(address: 0x200, text: "str x0, [x1]", annotation: "self.visited += 1"),
            loopSwitchBranch(0x204, to: 0x100),
        ], successors: [0x100]),
        loopSwitchExit(),
    ])
    #expect(text.contains("while (true)"), "\(text)")
    #expect(text.contains("if (x0 == 0) {\n            break"), "\(text)")
    #expect(!text.contains("goto loc_400"), "\(text)")
}

/// A loop introduced inside a case is now the nearest break target. Its own
/// exit must stay a break; after that loop ends, an outer-loop exit still needs
/// to cross the enclosing switch explicitly.
@Test func innerLoopInsideSwitchKeepsItsOwnBreakTarget() {
    let text = renderLoopSwitch([
        BasicBlock(startAddress: 0x100, instructions: [loopSwitchBranch(0x100, to: 0x200)], successors: [0x200]),
        loopSwitchDispatch(0x200, cases: [0x250, 0x300]),
        BasicBlock(startAddress: 0x250, instructions: [
            Instruction(address: 0x250, text: "str x0, [x1]", annotation: "self.innerVisits += 1"),
            loopSwitchTest(0x254, to: 0x270),
        ], successors: [0x270, 0x260]),
        BasicBlock(startAddress: 0x260, instructions: [loopSwitchBranch(0x260, to: 0x250)], successors: [0x250]),
        BasicBlock(startAddress: 0x270, instructions: [loopSwitchTest(0x270, to: 0x400)], successors: [0x400, 0x300]),
        BasicBlock(startAddress: 0x300, instructions: [loopSwitchBranch(0x300, to: 0x100)], successors: [0x100]),
        loopSwitchExit(),
    ])
    #expect(text.components(separatedBy: "while (true)").count == 3, "\(text)")
    #expect(text.contains("                    break"), "\(text)")
    #expect(!text.contains("goto loc_270"), "\(text)")
    #expect(text.contains("goto loc_400"), "\(text)")
    #expect(text.contains("loc_400:"), "\(text)")
}

/// A second switch in the case still crosses a switch on the way to the loop.
@Test func nestedSwitchCaseTransfersToTheEnclosingLoopExit() {
    let text = renderLoopSwitch([
        BasicBlock(startAddress: 0x100, instructions: [loopSwitchBranch(0x100, to: 0x200)], successors: [0x200]),
        loopSwitchDispatch(0x200, cases: [0x250, 0x300]),
        loopSwitchDispatch(0x250, cases: [0x400, 0x300]),
        BasicBlock(startAddress: 0x300, instructions: [loopSwitchBranch(0x300, to: 0x100)], successors: [0x100]),
        loopSwitchExit(),
    ])
    #expect(text.contains("case 0:\n            switch (?) {\n            case 0:\n                goto loc_400"), "\(text)")
    #expect(text.contains("loc_400:"), "\(text)")
}

/// Native LLVM-style byte-table decoding must carry the same loop transfer
/// through the CFG and public structured rendering paths.
@Test func nativeSwitchCaseTransfersToTheEnclosingLoopExitIfPresent() async throws {
    let path = "Fixtures/Sample/libLoopSwitch.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "loopSwitchExit")
    }
    let function = try #require(functions.first { $0.symbol == "_loopSwitchExit" })
    let table = try #require(function.switchTargets.values.first)
    #expect(table.count == 10)
    #expect(Set(table).count == 2)
    let text = function.renderStructured()
    let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let caseIndex = try #require(lines.firstIndex(of: "case 0:"))
    let target = "loc_\(String(table[0], radix: 16))"
    #expect(lines[caseIndex + 1] == "goto \(target)", "\(text)")
    #expect(lines.contains("\(target):"), "\(text)")
    #expect(text.components(separatedBy: "finished()").count == 2, "\(text)")
}
