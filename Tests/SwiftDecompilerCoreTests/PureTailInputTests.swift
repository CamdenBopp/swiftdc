import Foundation
import Testing
@testable import SwiftDecompilerCore

// Entirely authored, analysis-only arm64 reductions. No compiler, linker,
// fixture input, installed application, runtime import, or native execution.
// Authored sub_ labels deliberately bypass the unrelated undeclared-C arity
// fallback, so the tests exercise absent snapshots as well as trailing trim.
private enum TailInputOp: Sendable {
    case word(UInt32), branch(String), call(String), interiorBranch(String), externalBranch(UInt64)
}

private struct TailInputBody: Sendable {
    let name: String
    let code: [TailInputOp]
}

private struct TailInputProgram: Sendable {
    let bodies: [TailInputBody]
    let addresses: [String: UInt64]
    let words: [String: [UInt32]]

    init(_ bodies: [TailInputBody]) {
        self.bodies = bodies
        var addresses: [String: UInt64] = [:]
        var cursor: UInt64 = 0x1000
        for body in bodies {
            addresses[body.name] = cursor
            cursor += UInt64(body.code.count * 4)
        }
        self.addresses = addresses
        var words: [String: [UInt32]] = [:]
        for body in bodies {
            let start = addresses[body.name]!
            words[body.name] = body.code.enumerated().map { index, op in
                let address = start + UInt64(index * 4)
                switch op {
                case .word(let word): return word
                case .branch(let name): return Self.branch(from: address, to: addresses[name]!, link: false)
                case .call(let name): return Self.branch(from: address, to: addresses[name]!, link: true)
                case .interiorBranch(let name): return Self.branch(from: address, to: addresses[name]! + 4, link: false)
                case .externalBranch(let target): return Self.branch(from: address, to: target, link: false)
                }
            }
        }
        self.words = words
    }

    private static func branch(from: UInt64, to: UInt64, link: Bool) -> UInt32 {
        let displacement = Int64(to) - Int64(from)
        precondition(displacement % 4 == 0 && displacement >= -(1 << 27) && displacement < (1 << 27))
        return (link ? 0x9400_0000 : 0x1400_0000)
            | (UInt32(truncatingIfNeeded: displacement >> 2) & 0x03ff_ffff)
    }

    func functions() throws -> [UInt64: DisassembledFunction] {
        let engine = try #require(CapstoneEngine())
        return Dictionary(uniqueKeysWithValues: try bodies.map { body in
            let start = addresses[body.name]!
            let decoded = engine.disassemble(Self.data(words[body.name]!), address: start)
            let instructions = decoded.map(Disassembler.instruction(decoded:))
            let function = DisassembledFunction(symbol: "sub_tail_input_" + body.name, demangledName: nil,
                startAddress: start, instructions: instructions, source: .symbol)
            try #require(!instructions.isEmpty)
            return (start, function)
        })
    }

    func summaries(_ functions: [UInt64: DisassembledFunction]) throws -> [UInt64: CalleeRegisterSummary] {
        let starts = Set(addresses.values)
        return Dictionary(uniqueKeysWithValues: try functions.keys.sorted().map { start in
            (start, try #require(CalleeRegisterSummary.of(functions[start]!, isFunction: starts.contains)))
        })
    }

    static func data(_ words: [UInt32]) -> Data {
        Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    }

    // Minimal MH_OBJECT with a __TEXT,__text section and ordinary defined
    // symbols. The object is only decoded: no executable entry or imports.
    // Adjacent symbols delimit exact bodies, including one-word B aliases.
    func image() -> Data {
        let text = Self.data(bodies.flatMap { words[$0.name]! })
        let textOffset = 0x1000
        let symbolOffset = (textOffset + text.count + 15) & ~15
        let stringOffset = symbolOffset + bodies.count * 16
        var strings = Data([0])
        var stringIndexes: [String: UInt32] = [:]
        for body in bodies {
            stringIndexes[body.name] = UInt32(strings.count)
            strings.append(Data(("sub_tail_input_" + body.name).utf8)); strings.append(0)
        }
        let fileSize = stringOffset + strings.count
        func u32(_ value: UInt32) -> Data { Self.data([value]) }
        func u64(_ value: UInt64) -> Data { u32(UInt32(truncatingIfNeeded: value)) + u32(UInt32(value >> 32)) }
        func name(_ value: String) -> Data {
            let bytes = Data(value.utf8)
            return bytes + Data(repeating: 0, count: 16 - bytes.count)
        }
        var segment = u32(0x19) + u32(152) + name("__TEXT")
        segment += u64(0) + u64(UInt64(fileSize)) + u64(0) + u64(UInt64(fileSize))
        segment += Self.data([7, 5, 1, 0])
        segment += name("__text") + name("__TEXT") + u64(UInt64(textOffset)) + u64(UInt64(text.count))
        segment += Self.data([UInt32(textOffset), 2, 0, 0, 0x8000_0400, 0, 0, 0])
        let symtab = Self.data([0x2, 24, UInt32(symbolOffset), UInt32(bodies.count), UInt32(stringOffset), UInt32(strings.count)])
        var result = Self.data([0xfeed_facf, 0x0100_000c, 0, 1, 2, UInt32(segment.count + symtab.count), 0, 0])
        result += segment + symtab
        result += Data(repeating: 0, count: textOffset - result.count)
        result += text
        result += Data(repeating: 0, count: symbolOffset - result.count)
        for body in bodies {
            result += u32(stringIndexes[body.name]!)
            result += Data([0x0f, 1, 0, 0]) // N_SECT | N_EXT, section 1, no description
            result += u64(addresses[body.name]!)
        }
        result += strings
        precondition(result.count == fileSize)
        return result
    }
}

private let tailInputRet = TailInputOp.word(0xd65f_03c0)
private let tailInputAdd = TailInputOp.word(0x9100_0400) // add x0,x0,#1
private let tailInputDouble = TailInputOp.word(0x1e60_2800) // fadd d0,d0,d0
private let tailInputFloat = TailInputOp.word(0x1e20_2800) // fadd s0,s0,s0

private func tailInputProgram() -> TailInputProgram {
    let forgetIndirectResult = TailInputOp.word(0xaa09_03e8) // mov x8,x9: no known sret snapshot
    return TailInputProgram([
        .init(name: "callerAbsent", code: [forgetIndirectResult, .call("relayA"), tailInputRet]),
        .init(name: "callerUnknown", code: [forgetIndirectResult, .word(0xf940_0100), .call("relayA"), tailInputRet]), // ldr x0,[x8]
        .init(name: "callerSnapshot", code: [forgetIndirectResult, .word(0xd280_00e1), .call("relayA"), tailInputRet]), // mov x1,#7
        .init(name: "relayA", code: [.branch("relayB")]),
        .init(name: "relayB", code: [.branch("leaf")]),
        .init(name: "leaf", code: [tailInputAdd, tailInputRet]),
        // The only reachable instruction is B; undecoded trailing data is harmless.
        .init(name: "trailingAlias", code: [.branch("leaf"), .word(0xffff_ffff)]),
        .init(name: "callerEmpty", code: [forgetIndirectResult, .call("emptyRelay"), tailInputRet]),
        .init(name: "emptyRelay", code: [.branch("emptyLeaf")]),
        .init(name: "emptyLeaf", code: [tailInputRet]),
        .init(name: "callerWrapper", code: [forgetIndirectResult, .call("wrapper"), tailInputRet]),
        .init(name: "wrapper", code: [.call("leaf"), tailInputRet]),
        .init(name: "callerDouble", code: [forgetIndirectResult, .call("doubleRelayA"), tailInputRet]),
        .init(name: "doubleRelayA", code: [.branch("doubleRelayB")]),
        .init(name: "doubleRelayB", code: [.branch("doubleLeaf")]),
        .init(name: "doubleLeaf", code: [tailInputDouble, tailInputRet]),
        .init(name: "callerFloat", code: [forgetIndirectResult, .call("floatRelay"), tailInputRet]),
        .init(name: "floatRelay", code: [.branch("floatLeaf")]),
        .init(name: "floatLeaf", code: [tailInputFloat, tailInputRet]),
        .init(name: "callerMixed", code: [forgetIndirectResult, .call("mixedRelay"), tailInputRet]),
        .init(name: "mixedRelay", code: [.branch("mixedLeaf")]),
        .init(name: "mixedLeaf", code: [tailInputAdd, tailInputDouble, tailInputRet]),
        .init(name: "ambiguousRelay", code: [.branch("ambiguousLeaf")]),
        // cbz x9,+12; fadd s0,s0,s0; ret; fadd d0,d0,d0; ret.
        .init(name: "ambiguousLeaf", code: [.word(0xb400_0069), tailInputFloat, tailInputRet, tailInputDouble, tailInputRet]),
    ])
}

@Test func exactTailAliasesInheritProvedIntegerAndFloatInputs() throws {
    let program = tailInputProgram()
    let functions = try program.functions()
    var summaries = try program.summaries(functions)
    for name in ["callerAbsent", "callerUnknown", "callerDouble", "callerFloat", "callerMixed"] {
        let function = functions[program.addresses[name]!]!
        #expect(ValueTracer().analyze(function).callSites.isEmpty, Comment(rawValue: name))
    }
    let snapshotSites = ValueTracer().analyze(functions[program.addresses["callerSnapshot"]!]!).callSites
    #expect(snapshotSites.values.contains { !$0.arguments.isEmpty })
    CalleeRegisterSummary.closeOverReads(&summaries)
    for name in ["relayA", "relayB", "trailingAlias"] {
        let summary = try #require(summaries[program.addresses[name]!])
        #expect(summary.argumentReads == [0])
        #expect(summary.provenArgumentReads == [0])
        #expect(summary.provenArgumentCount == 1)
    }
    for (relay, width) in [("doubleRelayA", 64), ("doubleRelayB", 64), ("floatRelay", 32)] {
        let summary = try #require(summaries[program.addresses[relay]!])
        #expect(summary.provenArgumentReads.isEmpty)
        #expect(summary.provenFloatArgumentReads == [0])
        #expect(summary.floatArgumentWidths == [0: width])
    }
    let mixed = try #require(summaries[program.addresses["mixedRelay"]!])
    #expect(mixed.provenArgumentCount == 1 && mixed.provenFloatArgumentCount == 1)
    #expect(mixed.floatArgumentWidths == [0: 64])
    let ambiguous = try #require(summaries[program.addresses["ambiguousRelay"]!])
    #expect(ambiguous.provenFloatArgumentReads == [0])
    #expect(ambiguous.floatArgumentWidths.isEmpty) // A width disagreement stays unknown.
    for name in ["emptyRelay", "wrapper"] {
        let summary = try #require(summaries[program.addresses[name]!])
        #expect(summary.provenArgumentReads.isEmpty && summary.provenFloatArgumentReads.isEmpty)
    }
    #expect(summaries[program.addresses["wrapper"]!]?.argumentReads == [0])
    let closed = summaries
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries == closed)
}

@Test func tailInputProofRequiresExactEntriesAndPresentFiniteTargets() throws {
    let program = TailInputProgram([
        .init(name: "leaf", code: [tailInputAdd, tailInputRet]),
        .init(name: "interior", code: [.interiorBranch("leaf")]),
        .init(name: "scratch", code: [.word(0xd280_0029), .branch("leaf")]), // mov x9,#1
        .init(name: "nopPrefix", code: [.word(0xd503_201f), .branch("leaf")]),
        .init(name: "selfCycle", code: [.branch("selfCycle")]),
        .init(name: "external", code: [.externalBranch(0x7000)]),
        .init(name: "indirect", code: [.word(0xd61f_0100)]), // br x8
        .init(name: "conditional", code: [.word(0x5400_0000)]), // b.eq to self
        .init(name: "cycleA", code: [.branch("cycleB")]),
        .init(name: "cycleB", code: [.branch("cycleA")]),
        .init(name: "missing", code: [.branch("leaf")]),
        .init(name: "skippedAlias", code: [.word(0xffff_ffff), .branch("leaf")]),
        .init(name: "aliasToSkipped", code: [.branch("skippedAlias")]),
        .init(name: "skippedLeaf", code: [.word(0xffff_ffff), tailInputAdd, tailInputRet]),
        .init(name: "aliasToSkippedLeaf", code: [.branch("skippedLeaf")]),
    ])
    let functions = try program.functions()
    var summaries = try program.summaries(functions)
    CalleeRegisterSummary.closeOverReads(&summaries)
    for name in ["interior", "scratch", "nopPrefix", "external", "indirect", "conditional", "selfCycle", "cycleA", "cycleB", "skippedAlias", "aliasToSkipped", "aliasToSkippedLeaf"] {
        let summary = try #require(summaries[program.addresses[name]!])
        #expect(summary.provenArgumentReads.isEmpty && summary.provenFloatArgumentReads.isEmpty, Comment(rawValue: name))
    }
    // A real entry whose first word was skipped must not be confused with the
    // first decoded instruction, even if its DisassembledFunction start was
    // reconstructed from that instruction. The dictionary keeps the real entry.
    let skippedStart = program.addresses["skippedAlias"]!
    let decoded = try #require(functions[skippedStart]?.instructions.first)
    #expect(decoded.address == skippedStart + 4)
    let misbased = DisassembledFunction(symbol: "_misbased", demangledName: nil,
        startAddress: decoded.address, instructions: [decoded], source: .address)
    var keyed = try program.summaries(functions)
    keyed[skippedStart] = try #require(CalleeRegisterSummary.of(misbased, isFunction: Set(program.addresses.values).contains))
    CalleeRegisterSummary.closeOverReads(&keyed)
    #expect(keyed[skippedStart]?.provenArgumentReads.isEmpty == true)
    #expect(keyed[program.addresses["aliasToSkipped"]!]?.provenArgumentReads.isEmpty == true)
    // A decoded-entry dictionary key must not overrule a conflicting declared
    // function entry. This independently guards the recognition half as well
    // as the summary-key checks exercised by the misbased function above.
    let declaredEarlier = DisassembledFunction(symbol: "_declaredEarlier", demangledName: nil,
        startAddress: skippedStart, instructions: [decoded], source: .address)
    var declaredConflict = try program.summaries(functions)
    declaredConflict[decoded.address] = try #require(CalleeRegisterSummary.of(
        declaredEarlier, isFunction: Set(program.addresses.values).contains))
    CalleeRegisterSummary.closeOverReads(&declaredConflict)
    #expect(declaredConflict[decoded.address]?.provenArgumentReads.isEmpty == true)
    // A declared target that could not be summarized (or was beyond a bounded
    // callee decode) is not an arity proof.
    var missing = try program.summaries(functions)
    missing.removeValue(forKey: program.addresses["leaf"]!)
    CalleeRegisterSummary.closeOverReads(&missing)
    #expect(missing[program.addresses["missing"]!]?.provenArgumentReads.isEmpty == true)

    let count = 520
    let chain = TailInputProgram((0..<count).map { index in
        TailInputBody(name: "long\(index)", code: index == count - 1
            ? [tailInputAdd, tailInputRet] : [.branch("long\(index + 1)")])
    })
    let chainFunctions = try chain.functions()
    var complete = try chain.summaries(chainFunctions)
    CalleeRegisterSummary.closeOverReads(&complete)
    #expect(complete[chain.addresses["long0"]!]?.provenArgumentReads == [0])
    var bounded = try chain.summaries(chainFunctions)
    bounded.removeValue(forKey: chain.addresses["long\(count - 1)"]!)
    CalleeRegisterSummary.closeOverReads(&bounded)
    #expect(bounded[chain.addresses["long0"]!]?.provenArgumentReads.isEmpty == true)
}

@Test func tailInputProofSurvivesPreservationRebuildsAndTheirCap() throws {
    let program = TailInputProgram([
        .init(name: "relayA", code: [.branch("relayB")]),
        .init(name: "relayB", code: [.branch("leaf")]),
        .init(name: "leaf", code: [.word(0xd280_00f3), tailInputAdd, tailInputRet]), // mov x19,#7
    ])
    let functions = try program.functions()
    var summaries = try program.summaries(functions)
    CalleeRegisterSummary.closeOverReads(&summaries)
    func rebuild(_ start: UInt64, _ effects: (UInt64) -> CalleeEffect,
                 _ reads: CalleeRegisterSummary) -> CalleeRegisterSummary? {
        CalleeRegisterSummary.recomputingPreservation(functions[start]!, retainingReadsFrom: reads,
            calleeEffects: effects, isFunction: Set(program.addresses.values).contains)
    }
    CalleeRegisterSummary.closeOverCalls(&summaries, recompute: rebuild)
    for cap in [false, true] {
        var copied = summaries
        if cap { CalleeRegisterSummary.closeOverCalls(&copied, cap: 0, recompute: rebuild) }
        // Reclose from the immutable body evidence, without letting a previously
        // inherited input mask hide a dropped alias/entry fact in a copy path.
        for name in ["relayA", "relayB"] { copied[program.addresses[name]!]?.provenArgumentReads = [] }
        CalleeRegisterSummary.closeOverReads(&copied)
        #expect(copied[program.addresses["relayA"]!]?.provenArgumentReads == [0])
        #expect(copied[program.addresses["relayB"]!]?.provenArgumentReads == [0])
    }
}

@Test func tailInputRequirementsRenderAcrossEveryProductionSummaryRoute() async throws {
    let program = tailInputProgram()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tail-input-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("tail-input.o")
    try program.image().write(to: file)
    let image = try BinaryLoader.load(path: file.path)
    let selected = Set(program.bodies.filter { $0.name.hasPrefix("caller") }.map { program.addresses[$0.name]! })
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let objdump = try await withStableDependencies { try await Disassembler().disassemble(path: file.path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: file.path, functionFilter: "sub_tail_input_caller")
    }
    let selectedArray = await withStableDependencies {
        await Disassembler().disassembleFunctions(at: selected, in: image, groupsAsyncFunclets: false)
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: selected, in: image, transform: { $0 })
    }
    let stream = await withStableDependencies {
        await Disassembler().disassembleStreamingRender(machO: image, render: { $0.renderPseudo() })
    }
    let expected = [
        "callerAbsent": "sub_tail_input_relayA(?)", "callerUnknown": "sub_tail_input_relayA(?)",
        "callerSnapshot": "sub_tail_input_relayA(?)", "callerEmpty": "sub_tail_input_emptyRelay()",
        "callerWrapper": "sub_tail_input_wrapper()", "callerDouble": "sub_tail_input_doubleRelayA(?)",
        "callerFloat": "sub_tail_input_floatRelay(?)", "callerMixed": "sub_tail_input_mixedRelay(?, ?)",
    ]
    for functions in [array, objdump, filtered, selectedArray, Array(each.values)] {
        for (name, call) in expected.sorted(by: { $0.key < $1.key }) {
            let function = try #require(functions.first { $0.symbol == "sub_tail_input_" + name })
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains(call), Comment(rawValue: text))
            }
        }
    }
    for (name, call) in expected.sorted(by: { $0.key < $1.key }) {
        let text = try #require(stream.first { $0.hasPrefix("sub_tail_input_" + name + " {") })
        #expect(text.contains(call), Comment(rawValue: text))
    }
    // The same proof repairs the pre-existing inner relay, not just its callers.
    for functions in [array, objdump] {
        let relay = try #require(functions.first { $0.symbol == "sub_tail_input_relayA" })
        #expect(relay.renderPseudo().contains("sub_tail_input_relayB(arg0)"), Comment(rawValue: relay.renderPseudo()))
    }
}
