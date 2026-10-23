import Testing
import Foundation
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

/// Two branches share a side-effecting return block, but each also has its own
/// exit. There is no shared post-dominator to hoist the common block to. The
/// second reference must transfer control explicitly, not fall through.
@Test func sharedContinuationHasAnExplicitTransferAndLabel() {
    func branch(_ address: UInt64, _ target: UInt64) -> Instruction {
        Instruction(address: address, text: "cbz x0, 0x\(String(target, radix: 16))",
                    controlFlow: .conditionalBranch, branchTarget: target)
    }
    func ret(_ address: UInt64) -> Instruction {
        Instruction(address: address, text: "ret", controlFlow: .return)
    }
    let blocks = [
        BasicBlock(startAddress: 0x100, instructions: [branch(0x100, 0x200)], successors: [0x200, 0x300]),
        BasicBlock(startAddress: 0x200, instructions: [branch(0x200, 0x400)], successors: [0x400, 0x500]),
        BasicBlock(startAddress: 0x300, instructions: [branch(0x300, 0x400)], successors: [0x400, 0x600]),
        BasicBlock(startAddress: 0x400, instructions: [
            Instruction(address: 0x400, text: "str x0, [x1]", annotation: "self.value = 7",
                facts: .init(statement: .assignment("self.value = 7"))), ret(0x404)
        ], successors: []),
        BasicBlock(startAddress: 0x500, instructions: [ret(0x500)], successors: []),
        BasicBlock(startAddress: 0x600, instructions: [ret(0x600)], successors: []),
    ]
    let text = ControlFlowStructure(blocks: blocks)
        .renderLines(header: "shared() {", objcLine: nil).joined(separator: "\n")
    #expect(text.contains("goto loc_400"), "\(text)")
    #expect(text.contains("loc_400:"), "\(text)")
    #expect(!text.contains("// continues at"), "\(text)")
    #expect(text.components(separatedBy: "self.value = 7").count == 2, "\(text)")
}

/// Every `goto loc_X` the structurer emits must have its `loc_X:` label in the
/// same function: a shared continuation now jumps instead of being a comment,
/// and a jump to nowhere would be worse than the comment was.
@Test func everyGotoHasItsLabelIfPresent() async throws {
    var checked = 0
    for path in ["Fixtures/Sample/libReconstruction.dylib", "Fixtures/Sample/libReconstruction.opt.dylib",
                 "Fixtures/Sample/libSample.dylib", "Fixtures/Sample/libSwitches.dylib"]
    where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: path)
        }
        for function in functions {
            let text = function.renderStructured()
            let gotos = Set(text.matches(of: /goto (loc_[0-9a-f]+)/).map { String($0.1) })
            let labels = Set(text.matches(of: /(?m)^\s*(loc_[0-9a-f]+):/).map { String($0.1) })
            #expect(gotos.isSubset(of: labels), "\(path) \(function.displayName): \(gotos.subtracting(labels))")
            checked += gotos.count
        }
    }
    if FileManager.default.fileExists(atPath: "Fixtures/Sample/libReconstruction.dylib") {
        #expect(checked >= 50, "only \(checked) gotos checked")
    }
}
