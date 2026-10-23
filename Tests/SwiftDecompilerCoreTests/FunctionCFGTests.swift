import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `FunctionCFG` took over the block recovery `basicBlocks()` did, and
/// `basicBlocks()` became a view of it. Every consumer of the old block list
/// must see the same blocks, so the old algorithm is kept here, verbatim, as
/// the oracle: same leaders, same instructions, and the same successors in the
/// same order and multiplicity (a conditional branch to the next instruction
/// lists it twice; a jump table lists its cases once each).
struct FunctionCFGTests {
    /// `basicBlocks()` as it was at 13fe3d5, before `FunctionCFG`.
    static func legacyBasicBlocks(_ function: DisassembledFunction) -> [BasicBlock] {
        let instructions = function.instructions, switchTargets = function.switchTargets
        guard !instructions.isEmpty else { return [] }
        let internalAddresses = Set(instructions.map(\.address))
        var leaders: Set<UInt64> = [instructions[0].address]
        for (index, insn) in instructions.enumerated() {
            if insn.isTrap, index + 1 < instructions.count {
                leaders.insert(instructions[index + 1].address)
            }
            switch insn.controlFlow {
            case .branch, .conditionalBranch, .return:
                if index + 1 < instructions.count {
                    leaders.insert(instructions[index + 1].address)
                }
                if let target = insn.branchTarget, internalAddresses.contains(target) {
                    leaders.insert(target)
                }
                for target in switchTargets[insn.address] ?? [] where internalAddresses.contains(target) {
                    leaders.insert(target)
                }
            case .call, .sequential, .none:
                break
            }
        }
        func successors(of last: Instruction, fallthrough next: UInt64?) -> [UInt64] {
            switch last.controlFlow {
            case .return: return []
            case .branch: return last.branchTarget.map { [$0] } ?? []
            case .conditionalBranch: return [last.branchTarget, next].compactMap { $0 }
            case .call, .sequential, .none:
                if last.isTrap { return [] }
                return next.map { [$0] } ?? []
            }
        }
        var blocks: [BasicBlock] = []
        var current: [Instruction] = []
        func flush(fallthrough next: UInt64?) {
            guard let first = current.first, let last = current.last else { return }
            let cases = switchTargets[last.address]
            var unique: [UInt64] = []
            for target in cases ?? [] where !unique.contains(target) { unique.append(target) }
            blocks.append(BasicBlock(
                startAddress: first.address, instructions: current,
                successors: cases == nil ? successors(of: last, fallthrough: next) : unique,
                switchCases: cases))
            current = []
        }
        for insn in instructions {
            if !current.isEmpty, leaders.contains(insn.address) { flush(fallthrough: insn.address) }
            current.append(insn)
        }
        flush(fallthrough: nil)
        return blocks
    }

    /// The first difference between two block lists, or nil when they match
    /// in every field a consumer reads.
    static func difference(_ expected: [BasicBlock], _ actual: [BasicBlock]) -> String? {
        guard expected.count == actual.count else { return "block count \(expected.count) vs \(actual.count)" }
        for (index, (old, new)) in zip(expected, actual).enumerated() {
            let at = "block \(index) @ 0x\(String(old.startAddress, radix: 16))"
            if old.startAddress != new.startAddress { return "\(at): start 0x\(String(new.startAddress, radix: 16))" }
            if old.instructions.map(\.address) != new.instructions.map(\.address)
                || old.instructions.map(\.text) != new.instructions.map(\.text)
                || old.instructions.map(\.annotation) != new.instructions.map(\.annotation) {
                return "\(at): instructions differ"
            }
            if old.successors != new.successors { return "\(at): successors \(old.successors) vs \(new.successors)" }
            if old.switchCases != new.switchCases { return "\(at): switch cases differ" }
        }
        return nil
    }

    /// The graph's own invariants: the blocks partition the instructions in
    /// order, each id resolves to its block, and the predecessor lists are the
    /// successor lists inverted, edge for edge.
    static func inconsistency(_ cfg: FunctionCFG, of function: DisassembledFunction) -> String? {
        let instructions = function.instructions
        guard cfg.instructionCount == instructions.count else { return "instruction count" }
        guard cfg.entry == (instructions.isEmpty ? nil : 0) else { return "entry" }
        guard cfg.blockOfInstruction.count == instructions.count else { return "block-of-instruction count" }
        var next = 0
        var firstAt: [UInt64: Int] = [:]
        var predecessors = [[Int]](repeating: [], count: cfg.blocks.count)
        for (id, block) in cfg.blocks.enumerated() {
            guard block.range.lowerBound == next, !block.range.isEmpty else { return "block \(id) range" }
            next = block.range.upperBound
            guard block.startAddress == instructions[block.range.lowerBound].address else { return "block \(id) start" }
            guard block.terminator == block.range.upperBound - 1 else { return "block \(id) terminator" }
            guard block.range.allSatisfy({ cfg.blockOfInstruction[$0] == id }) else { return "block \(id) membership" }
            if firstAt[block.startAddress] == nil { firstAt[block.startAddress] = id }
        }
        guard next == instructions.count else { return "blocks do not cover the instructions" }
        for (id, block) in cfg.blocks.enumerated() {
            guard cfg.block(startingAt: block.startAddress) == firstAt[block.startAddress] else { return "block \(id) lookup" }
            let expected = block.successorAddresses.compactMap { firstAt[$0] }
            guard block.successorIDs == expected else { return "block \(id) successor ids \(block.successorIDs) vs \(expected)" }
            for successor in block.successorIDs { predecessors[successor].append(id) }
        }
        for (id, block) in cfg.blocks.enumerated() where block.predecessorIDs != predecessors[id] {
            return "block \(id) predecessors \(block.predecessorIDs) vs \(predecessors[id])"
        }
        return nil
    }

    /// Shapes the comparison must have met for it to say anything about
    /// order and multiplicity.
    struct Coverage {
        var functions = 0, blocks = 0
        var repeatedSuccessor = 0, switchBlocks = 0, repeatedCase = 0
        var externalSuccessor = 0, trapEnds = 0, multiplePredecessors = 0

        mutating func count(_ cfg: FunctionCFG, of function: DisassembledFunction) {
            functions += 1
            blocks += cfg.blocks.count
            for block in cfg.blocks {
                if Set(block.successorAddresses).count < block.successorAddresses.count { repeatedSuccessor += 1 }
                if let cases = block.switchCases {
                    switchBlocks += 1
                    if Set(cases).count < cases.count { repeatedCase += 1 }
                }
                if block.successorIDs.count < block.successorAddresses.count { externalSuccessor += 1 }
                if function.instructions[block.terminator].isTrap { trapEnds += 1 }
                if block.predecessorIDs.count > 1 { multiplePredecessors += 1 }
            }
        }
    }

    /// Compare the view with the oracle, and check the graph, on `function`
    /// and on the same function before jump tables were recognised (the input
    /// the register summaries see today).
    static func check(_ function: DisassembledFunction, coverage: inout Coverage) -> String? {
        let variants = function.switchTargets.isEmpty ? [function] : [
            function,
            DisassembledFunction(symbol: function.symbol, demangledName: function.demangledName,
                                 startAddress: function.startAddress, instructions: function.instructions,
                                 source: function.source),
        ]
        for variant in variants {
            let cfg = FunctionCFG(variant)
            if let problem = difference(legacyBasicBlocks(variant), variant.basicBlocks())
                ?? difference(legacyBasicBlocks(variant), cfg.basicBlocks(of: variant))
                ?? inconsistency(cfg, of: variant) {
                return "\(variant.symbol)\(variant.switchTargets.isEmpty && !function.switchTargets.isEmpty ? " (no tables)" : ""): \(problem)"
            }
            coverage.count(cfg, of: variant)
        }
        return nil
    }

    /// Every function of every fixture `Fixtures/Sample/build.sh` builds,
    /// whole-file decode.
    @Test func blocksMatchTheLegacyAlgorithmOnEveryFixtureIfPresent() async throws {
        let missing = FixturePresenceTests.requiredFixtures.filter { !FileManager.default.fileExists(atPath: $0) }
        #expect(missing.isEmpty || !FixturePresenceTests.enforcingFixturePresence,
                "Build \(missing) with Fixtures/Sample/build.sh")
        let directory = "Fixtures/Sample"
        let paths = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.hasSuffix(".dylib") || ["sample.debug", "sample.release", "sample.stripped"].contains($0) }
            .sorted().map { "\(directory)/\($0)" }
        var coverage = Coverage()
        var fixtures = 0
        for path in paths {
            let functions = try await withStableDependencies {
                try await Disassembler(preset: .default).disassemble(path: path)
            }
            fixtures += 1
            for function in functions {
                if let problem = Self.check(function, coverage: &coverage) {
                    Issue.record("\(path): \(problem)")
                    return
                }
            }
        }
        guard fixtures > 0 else { return }
        // The corpus must exercise each shape whose order or multiplicity the
        // view has to keep, or a pass here proves nothing about it. On
        // 2026-10-22: 113 fixtures, 8,137 functions, 17,837 blocks, 11 jump
        // tables (3 with a repeated case), 908 out-of-function successors,
        // 656 trap ends, 1,756 joins. No fixture has a conditional branch to
        // the next instruction; the hand-built test below holds that shape.
        #expect(coverage.functions > 5000, "\(coverage)")
        #expect(coverage.switchBlocks > 0, "\(coverage)")
        #expect(coverage.repeatedCase > 0, "\(coverage)")
        #expect(coverage.externalSuccessor > 0, "\(coverage)")
        #expect(coverage.trapEnds > 0, "\(coverage)")
        #expect(coverage.multiplePredecessors > 0, "\(coverage)")
    }

    /// The shapes the fixtures may not hold: a conditional branch to the next
    /// instruction (one successor twice, two predecessor entries), a jump table
    /// with a repeated case, an out-of-function branch, code after a trap, and
    /// two instructions at one address.
    @Test func blocksKeepOrderAndMultiplicityOnHandBuiltShapes() {
        let body: [Instruction] = [
            Instruction(address: 0x1000, text: "cmp x0, #3", controlFlow: .sequential),
            Instruction(address: 0x1004, text: "b.eq 0x1008", controlFlow: .conditionalBranch, branchTarget: 0x1008),
            Instruction(address: 0x1008, text: "br x9", controlFlow: .branch),
            Instruction(address: 0x100c, text: "b 0x9000", controlFlow: .branch, branchTarget: 0x9000),
            Instruction(address: 0x1010, text: "brk #1", controlFlow: .sequential),
            Instruction(address: 0x1014, text: "bl _effect", controlFlow: .call),
            Instruction(address: 0x1018, text: "ret", controlFlow: .return),
        ]
        let function = DisassembledFunction(
            symbol: "_shapes", demangledName: nil, startAddress: 0x1000, instructions: body, source: .symbol,
            switchTargets: [0x1008: [0x1014, 0x100c, 0x1014, 0x1018]])
        var coverage = Coverage()
        #expect(Self.check(function, coverage: &coverage) == nil)
        let cfg = FunctionCFG(function)
        #expect(cfg.blocks.map(\.startAddress) == [0x1000, 0x1008, 0x100c, 0x1010, 0x1014, 0x1018])
        #expect(cfg.blocks[0].successorAddresses == [0x1008, 0x1008])
        #expect(cfg.blocks[0].successorIDs == [1, 1])
        #expect(cfg.blocks[1].predecessorIDs == [0, 0])
        #expect(cfg.blocks[1].successorAddresses == [0x1014, 0x100c, 0x1018])
        #expect(cfg.blocks[1].switchCases == [0x1014, 0x100c, 0x1014, 0x1018])
        #expect(cfg.blocks[2].successorAddresses == [0x9000])
        #expect(cfg.blocks[2].successorIDs == [])
        #expect(cfg.blocks[3].successorAddresses == [])
        #expect(cfg.blocks[4].predecessorIDs == [1])
        #expect(cfg.blocks[5].predecessorIDs == [1, 4])

        let repeated = DisassembledFunction(
            symbol: "_repeated", demangledName: nil, startAddress: 0x2000, instructions: [
                Instruction(address: 0x2000, text: "cbz x0, 0x2008", controlFlow: .conditionalBranch, branchTarget: 0x2008),
                Instruction(address: 0x2004, text: "nop", controlFlow: .sequential),
                Instruction(address: 0x2008, text: "b 0x2004", controlFlow: .branch, branchTarget: 0x2004),
                Instruction(address: 0x2004, text: "ret", controlFlow: .return),
            ], source: .symbol)
        #expect(Self.check(repeated, coverage: &coverage) == nil)
        let empty = DisassembledFunction(symbol: "_empty", demangledName: nil, startAddress: 0x3000,
                                         instructions: [], source: .symbol)
        #expect(Self.check(empty, coverage: &coverage) == nil)
        #expect(FunctionCFG(empty).blocks.isEmpty && FunctionCFG(empty).entry == nil)
    }
}
