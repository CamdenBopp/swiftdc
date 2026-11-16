import Foundation
import Testing
import Demangling
@testable import SwiftDecompilerCore

// Entirely authored, analysis-only arm64 reductions. No application body,
// native fixture, compiler/linker, LLVM invocation, or target execution.
private enum BranchOrderOp: Sendable {
    case word(UInt32), call(String)
}
private struct BranchOrderBody: Sendable {
    let key: String
    let symbol: String
    let code: [BranchOrderOp]
}
private struct BranchOrderProgram: Sendable {
    let bodies: [BranchOrderBody]
    let addresses: [String: UInt64]
    let words: [String: [UInt32]]

    init(_ bodies: [BranchOrderBody]) {
        self.bodies = bodies
        var addresses: [String: UInt64] = [:]
        var cursor: UInt64 = 0x2000
        for body in bodies {
            precondition(addresses[body.key] == nil)
            addresses[body.key] = cursor
            cursor += UInt64(body.code.count * 4)
        }
        self.addresses = addresses
        var words: [String: [UInt32]] = [:]
        for body in bodies {
            words[body.key] = body.code.enumerated().map { index, op in
                switch op {
                case .word(let word): return word
                case .call(let target):
                    let from = addresses[body.key]! + UInt64(index * 4)
                    let displacement = Int64(addresses[target]!) - Int64(from)
                    precondition(displacement % 4 == 0 && displacement >= -(1 << 27) && displacement < (1 << 27))
                    return 0x9400_0000 | (UInt32(truncatingIfNeeded: displacement >> 2) & 0x03ff_ffff)
                }
            }
        }
        self.words = words
    }

    static func bytes(_ words: [UInt32]) -> Data {
        Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    }
    func functions() throws -> [UInt64: DisassembledFunction] {
        let engine = try #require(CapstoneEngine())
        return Dictionary(uniqueKeysWithValues: try bodies.map { body in
            let start = addresses[body.key]!
            let decoded = engine.disassemble(Self.bytes(words[body.key]!), address: start)
            let instructions = decoded.map(Disassembler.instruction(decoded:))
            let mangled = body.symbol.hasPrefix("_$s") ? String(body.symbol.dropFirst()) : body.symbol
            let demangled: String?
            if body.symbol.hasPrefix("_$s") {
                demangled = try demangleAsNode(mangled).print(using: .default)
            } else {
                demangled = nil
            }
            let function = DisassembledFunction(symbol: body.symbol, demangledName: demangled,
                startAddress: start, instructions: instructions, source: .symbol)
            try #require(instructions.count == body.code.count)
            return (start, function)
        })
    }
    // A minimal ordinary-symbol MH_OBJECT. It is never linked or executed.
    func image() -> Data {
        let textOffset = 0x2000
        let text = Self.bytes(bodies.flatMap { words[$0.key]! })
        let symbolOffset = (textOffset + text.count + 15) & ~15
        let stringOffset = symbolOffset + bodies.count * 16
        var strings = Data([0]), indexes: [String: UInt32] = [:]
        for body in bodies {
            indexes[body.key] = UInt32(strings.count)
            strings.append(Data(body.symbol.utf8)); strings.append(0)
        }
        let size = stringOffset + strings.count
        func u32(_ value: UInt32) -> Data { Self.bytes([value]) }
        func u64(_ value: UInt64) -> Data { u32(UInt32(truncatingIfNeeded: value)) + u32(UInt32(value >> 32)) }
        func name(_ text: String) -> Data {
            let data = Data(text.utf8)
            return data + Data(repeating: 0, count: 16 - data.count)
        }
        var segment = u32(0x19) + u32(152) + name("__TEXT")
        segment += u64(0) + u64(UInt64(size)) + u64(0) + u64(UInt64(size))
        segment += Self.bytes([7, 5, 1, 0])
        segment += name("__text") + name("__TEXT") + u64(UInt64(textOffset)) + u64(UInt64(text.count))
        segment += Self.bytes([UInt32(textOffset), 2, 0, 0, 0x8000_0400, 0, 0, 0])
        let symtab = Self.bytes([2, 24, UInt32(symbolOffset), UInt32(bodies.count), UInt32(stringOffset), UInt32(strings.count)])
        var image = Self.bytes([0xfeed_facf, 0x0100_000c, 0, 1, 2, UInt32(segment.count + symtab.count), 0, 0])
        image += segment + symtab
        image += Data(repeating: 0, count: textOffset - image.count)
        image += text
        image += Data(repeating: 0, count: symbolOffset - image.count)
        for body in bodies {
            image += u32(indexes[body.key]!)
            image += Data([0x0f, 1, 0, 0])
            image += u64(addresses[body.key]!)
        }
        image += strings
        precondition(image.count == size)
        return image
    }
}

private let branchOrderModes = ["call", "store", "none", "known"]
private let branchOrderRet = BranchOrderOp.word(0xd65f_03c0)
private let branchOrderProducerName = "branch_order_producer"
private let branchOrderEffectName = "branch_order_effect"

private func branchOrderProgram() -> BranchOrderProgram {
    var bodies: [BranchOrderBody] = []
    for mode in branchOrderModes {
        var code: [BranchOrderOp] = [
            .word(0xaa09_03e8), // mov x8,x9: no default indirect-result fact
            .call("producer"),
            .word(0xaa00_03f7), // mov x23,x0: preserve exact producer identity
        ]
        if mode == "call" || mode == "known" { code.append(.call("effect")) }
        if mode == "store" { code.append(.word(0xf900_027f)) } // str xzr,[x19]: not frame / not producer
        if mode == "call" || mode == "store" {
            code.append(.word(0xf940_0269)) // ldr x9,[x19]: unknown, ordinary load is NOT an ordering barrier
        } else if mode == "known" {
            code.append(.word(0xd280_00a9)) // mov x9,#5: full condition remains known
        }
        code += [
            .word(0xeb17_013f), // cmp x9,x23: raw flags retain unknown vs exact call result
            .word(0x5400_0061), // b.ne +12
            .word(0x5280_0020), branchOrderRet, // mov w0,#1;ret
            .word(0x5280_0040), branchOrderRet, // mov w0,#2;ret
        ]
        bodies.append(.init(key: "caller_" + mode,
            symbol: "sub_branch_order_case_" + mode, code: code))
    }
    bodies.append(.init(key: "producer", symbol: "_" + branchOrderProducerName,
        code: [.word(0xd280_0120), branchOrderRet])) // mov x0,#9;ret
    bodies.append(.init(key: "effect", symbol: "_" + branchOrderEffectName, code: [branchOrderRet]))
    return BranchOrderProgram(bodies)
}

private func branchOrderSites(
    _ function: DisassembledFunction, program: BranchOrderProgram
) throws -> (producer: Instruction, branch: Instruction) {
    let producer = try #require(function.instructions.first {
        $0.controlFlow == .call && $0.branchTarget == program.addresses["producer"]
    })
    let branch = try #require(function.instructions.first { $0.controlFlow == .conditionalBranch })
    return (producer, branch)
}

@Test func declinedBranchConditionsHaveIndependentProducerAndEffectPremises() throws {
    let program = branchOrderProgram(), functions = try program.functions()
    let starts = Set(program.addresses.values)
    let target = try #require(functions[program.addresses["producer"]!])
    let producerSummary = try #require(CalleeRegisterSummary.of(target, isFunction: starts.contains))
    try #require(producerSummary.provenArgumentReads.isEmpty && producerSummary.provenFloatArgumentReads.isEmpty)
    try #require(!producerSummary.clobberedCalleeSaved.contains("x23"))
    let effect = try #require(functions[program.addresses["effect"]!])
    let effectSummary = try #require(CalleeRegisterSummary.of(effect, isFunction: starts.contains))
    try #require(effectSummary.argumentReads.isEmpty && effectSummary.provenArgumentReads.isEmpty)
    try #require(!effectSummary.clobberedCalleeSaved.contains("x23"))
    for mode in branchOrderModes {
        let function = try #require(functions[program.addresses["caller_" + mode]!])
        let sites = try branchOrderSites(function, program: program)
        let block = try #require(function.basicBlocks().first {
            $0.instructions.contains { $0.address == sites.branch.address }
        })
        try #require(block.instructions.contains { $0.address == sites.producer.address })
        let beforeBranch = function.instructions.filter { $0.address < sites.branch.address }
        let state = ValueTracer().finalState(of: beforeBranch)
        try #require(state["x23"] == .callResult(sites.producer.address))
        let lhs: AbstractValue = mode == "known" ? .immediate(5) : .unknown
        try #require(state["nzcv.flags"] == .binary(.subtract, lhs, .callResult(sites.producer.address)))
        let analysis = ValueTracer().analyze(function)
        if mode == "known" {
            try #require(analysis.branchConditions[sites.branch.address] != nil)
        } else {
            try #require(analysis.branchConditions[sites.branch.address] == nil)
        }
        let between = block.instructions.filter {
            $0.address > sites.producer.address && $0.address < sites.branch.address
        }
        let barriers = between.filter(Disassembler.isOrderingEffect)
        try #require(barriers.count == (mode == "none" ? 0 : 1))
        if mode == "store" {
            let store = try #require(barriers.first)
            let detail = try #require(store.detail)
            try #require(detail.operands.contains {
                if case .memory(let base?, _, _) = $0.operand { return base.key == "x19" }
                return false
            })
        } else if mode == "call" || mode == "known" {
            try #require(barriers.first?.branchTarget == program.addresses["effect"])
        }
    }
}

private func branchOrderRenderClaims(_ function: DisassembledFunction) -> String {
    let producer = function.instructions.first { DisassembledFunction.calleeName(of: $0) == branchOrderProducerName }
    return function.renderStructured()
        + "\n// branch-order-producer: " + (producer.flatMap(DisassembledFunction.calleeName(of:)) ?? "<unresolved>")
        + "\n// branch-order-bound: " + (producer?.binding == nil ? "false" : "true")
}

private func branchOrderRequireRenderedOrder(_ text: String, mode: String) throws {
    let producer = try #require(text.range(of: branchOrderProducerName + "("))
    let condition = try #require(text.range(of: "if ("))
    #expect(text.components(separatedBy: branchOrderProducerName + "(").count - 1 == 1,
            Comment(rawValue: text))
    if mode == "none" {
        #expect(condition.lowerBound < producer.lowerBound, Comment(rawValue: text))
    } else {
        #expect(producer.lowerBound < condition.lowerBound, Comment(rawValue: text))
        if mode == "call" || mode == "known" {
            let effect = try #require(text.range(of: branchOrderEffectName + "("))
            #expect(producer.lowerBound < effect.lowerBound, Comment(rawValue: text))
        }
    }
}

@Test func declinedBranchProducerStaysBeforeEffectsAcrossProductionRoutes() async throws {
    let program = branchOrderProgram()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("branch-order-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("branch-order.o")
    try program.image().write(to: file)
    let image = try BinaryLoader.load(path: file.path)
    let selected = Set(branchOrderModes.map { program.addresses["caller_" + $0]! })
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let path = try await withStableDependencies { try await Disassembler().disassemble(path: file.path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: file.path, functionFilter: "sub_branch_order_case_")
    }
    let selectedArray = await withStableDependencies {
        await Disassembler().disassembleFunctions(at: selected, in: image, groupsAsyncFunclets: false)
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: selected, in: image, transform: { $0 })
    }
    let streaming = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let rendered = await withStableDependencies {
        await Disassembler().disassembleStreamingRender(machO: image, render: branchOrderRenderClaims)
    }
    for functions in [array, path, filtered, selectedArray, Array(each.values), streaming] {
        for mode in branchOrderModes {
            let function = try #require(functions.first { $0.symbol == "sub_branch_order_case_" + mode })
            let sites = try branchOrderSites(function, program: program)
            try #require(DisassembledFunction.calleeName(of: sites.producer) == branchOrderProducerName)
            try #require(sites.branch.condition == nil) // no fabricated complete condition
            if mode == "call" || mode == "known" {
                let effect = try #require(function.instructions.first {
                    $0.controlFlow == .call && $0.branchTarget == program.addresses["effect"]
                })
                try #require(DisassembledFunction.calleeName(of: effect) == branchOrderEffectName)
                try #require(effect.callArguments == nil) // producer has no other counted consumer
            }
            #expect((sites.producer.binding != nil) == (mode != "none"), Comment(rawValue: function.renderStructured()))
            try branchOrderRequireRenderedOrder(function.renderStructured(), mode: mode)
        }
    }
    for mode in branchOrderModes {
        let text = try #require(rendered.first { $0.hasPrefix("sub_branch_order_case_" + mode + " {") })
        try #require(text.contains("// branch-order-producer: " + branchOrderProducerName))
        #expect(text.contains("// branch-order-bound: " + (mode == "none" ? "false" : "true")), Comment(rawValue: text))
        try branchOrderRequireRenderedOrder(text, mode: mode)
    }
}

// POST-FIX ONLY: append after FunctionAnalysis gains the exact typed field.
// Do not include this append in the initial current9e compiled-red attempt.
@Test func declinedBranchesKeepOnlyTheirUnresolvedProducerIdentities() throws {
    let program = branchOrderProgram(), functions = try program.functions()
    for mode in branchOrderModes {
        let function = try #require(functions[program.addresses["caller_" + mode]!])
        let sites = try branchOrderSites(function, program: program)
        let analysis = ValueTracer().analyze(function)
        if mode == "known" {
            try #require(analysis.branchConditions[sites.branch.address] != nil)
            #expect(analysis.unresolvedBranchCallResults[sites.branch.address] == nil)
        } else {
            try #require(analysis.branchConditions[sites.branch.address] == nil)
            // Even the no-effect control retains identity; the consumer alone
            // decides whether moving evaluation crosses an existing barrier.
            let expected: Set<UInt64> = [sites.producer.address]
            #expect(analysis.unresolvedBranchCallResults[sites.branch.address] == expected)
        }
    }
}
