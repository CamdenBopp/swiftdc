import Foundation
import Testing
@testable import SwiftDecompilerCore

private let bodyArityImages = [
    "Fixtures/Sample/libBodyArity.O0.dylib", "Fixtures/Sample/libBodyArity.O0.stripped.dylib",
    "Fixtures/Sample/libBodyArity.O2.dylib", "Fixtures/Sample/libBodyArity.O2.stripped.dylib",
    "Fixtures/Sample/libBodyArity.Os.dylib", "Fixtures/Sample/libBodyArity.Os.stripped.dylib",
]

private func bodyArityPipelines(_ path: String) async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    let listed = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "body_arity_call_") }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies { await Disassembler().analyzeEachFunction(at: Set(listed.map(\.startAddress)), in: image, transform: { $0 }) }
    return [listed, array, filtered, streamed, Array(each.values)]
}

private func bodyArityCall(_ group: [DisassembledFunction], _ name: String) throws -> (DisassembledFunction, Instruction) {
    let function = try #require(group.first { $0.displayName.hasSuffix("body_arity_call_" + name) })
    let call = try #require(function.instructions.first {
        $0.controlFlow == .call && DisassembledFunction.calleeName(of: $0)?.hasSuffix("body_arity_" + name) == true
    })
    return (function, call)
}

@Test func possibleBodyReadsNeverTurnLiveCallerWordsIntoArgumentsIfPresent() async throws {
    for path in bodyArityImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for group in try await bodyArityPipelines(path) {
            for (name, expected) in [("one", ["?", "…"]), ("zero", ["…"])] {
                let (function, call) = try bodyArityCall(group, name)
                #expect(call.callArguments == expected, Comment(rawValue: path + "\n" + function.renderStructured()))
                for text in [function.renderStructured(), function.renderPseudo()] {
                    #expect(!text.contains("37"), Comment(rawValue: text))
                    #expect(text.contains("body_arity_" + name + "(" + expected.joined(separator: ", ") + ")"), Comment(rawValue: text))
                }
            }
        }
    }
}

@Test func possibleBodyReadsCannotFillUnprovedHolesBelowAProvedInputIfPresent() async throws {
    for path in bodyArityImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for group in try await bodyArityPipelines(path) {
            let (function, call) = try bodyArityCall(group, "third")
            #expect(call.callArguments == ["?", "?", "arg0", "…"], Comment(rawValue: path + "\n" + function.renderStructured()))
        }
    }
}

@Test func possibleGPInputsCannotPlaceAFloatingFormalOrInflateMixedArityIfPresent() async throws {
    for path in bodyArityImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for group in try await bodyArityPipelines(path) {
            for (name, expected) in [("float", ["?", "…"]), ("mixed", ["?", "?", "…"])] {
                let (function, call) = try bodyArityCall(group, name)
                #expect(call.callArguments == expected, Comment(rawValue: path + "\n" + function.renderStructured()))
            }
        }
    }
}

@Test func closedBodyAndExactAliasInputsKeepTheirKnownArgumentsIfPresent() async throws {
    for path in bodyArityImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for group in try await bodyArityPipelines(path) {
            for (name, expected) in [("closed_one", ["11"]), ("closed_float", ["1.0"]), ("alias", ["11"])] {
                let (function, call) = try bodyArityCall(group, name)
                #expect(call.callArguments == expected, Comment(rawValue: path + "\n" + function.renderStructured()))
            }
        }
    }
}

@Test func canonicalFrameForwardersKeepProvedGPAndFPInputsIfPresent() async throws {
    for path in bodyArityImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        for group in try await bodyArityPipelines(path) {
            for (name, expected) in [("framed_one", ["11"]), ("framed_float", ["1.0"])] {
                let (function, call) = try bodyArityCall(group, name)
                #expect(call.callArguments == expected, Comment(rawValue: path + "\n" + function.renderStructured()))
            }
        }
    }
}

private func bodyArityRaw(_ words: [UInt32], at start: UInt64) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(bytes, address: start)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "probe", demangledName: nil, startAddress: start,
        instructions: decoded.map { Instruction(address: $0.address, text: $0.text,
            controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }, source: .address)
}

private func bodyArityFrameWords(at start: UInt64, target: UInt64) -> [UInt32] {
    let offset = UInt32(truncatingIfNeeded: (Int64(target) - Int64(start + 8)) / 4) & 0x03ffffff
    return [0xa9bf7bfd, 0x910003fd, 0x94000000 | offset, 0xa8c17bfd, 0xd65f03c0]
}

@Test func packedForwardingTargetsKeepTheirKindAndSignedOffset() {
    let entry: UInt64 = 0x100000000
    for offset in [Int64(Int32.min), -4096, 0, 4096, Int64(Int32.max)] {
        let target = entry &+ UInt64(bitPattern: offset)
        var tail = CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [],
            inputProofEntry: entry, pureTailTarget: target)
        #expect(tail.pureTailTarget == target && tail.framedCallTarget == nil)
        tail.framedCallTarget = nil
        #expect(tail.pureTailTarget == target)
        #expect(tail.claimingNothing().pureTailTarget == target)
        tail.pureTailTarget = nil
        #expect(tail.pureTailTarget == nil && tail.framedCallTarget == nil)
        var frame = CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [],
            inputProofEntry: entry, framedCallTarget: target)
        #expect(frame.framedCallTarget == target && frame.pureTailTarget == nil)
        frame.pureTailTarget = nil
        #expect(frame.framedCallTarget == target)
        #expect(frame.claimingNothing().framedCallTarget == target)
        frame.framedCallTarget = nil
        #expect(frame.framedCallTarget == nil && frame.pureTailTarget == nil)
    }
    let conflict = CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [], inputProofEntry: entry,
        pureTailTarget: entry + 4, framedCallTarget: entry + 8)
    #expect(conflict.pureTailTarget == nil && conflict.framedCallTarget == nil)
    var outOfRange = CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [], inputProofEntry: entry)
    outOfRange.framedCallTarget = entry + UInt64(Int32.max) + 1
    #expect(outOfRange.framedCallTarget == nil)
}

@Test func framedInputProofNeedsAnExactABIFrameAndAnIndependentProvider() throws {
    let words = bodyArityFrameWords(at: 0x1000, target: 0x2000)
    let frame = try bodyArityRaw(words, at: 0x1000)
    let provider = try bodyArityRaw([0x91002400, 0xd65f03c0], at: 0x2000) // add x0,x0,#9; ret
    let makeSummary = { (body: DisassembledFunction) throws -> CalleeRegisterSummary in
        try #require(CalleeRegisterSummary.of(body, isFunction: { (address: UInt64) in
            [UInt64(0x1000), 0x2000, 0x3000].contains(address)
        }))
    }
    let initial = try makeSummary(frame)
    #expect(initial.framedCallTarget == 0x2000 && initial.pureTailTarget == nil)
    var summaries: [UInt64: CalleeRegisterSummary] = [0x1000: initial, 0x2000: try makeSummary(provider)]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[0x1000]?.provenArgumentReads == RegisterSet([0]))

    // Changed input, narrowed frame pointer, mismatched allocation/restore and a wrong
    // return register each break a different part of the forwarding contract.
    for (index, replacement) in [(0, UInt32(0xa9be7bfd)), (1, 0xd28000e0),
                                 (1, 0x110003fd), (3, 0xa8c17bfc),
                                 (3, 0xa8c27bfd), (4, 0xd65f0260), (2, 0x940003ff)] {
        var bad = words; bad[index] = replacement
        #expect(try makeSummary(bodyArityRaw(bad, at: 0x1000)).framedCallTarget == nil)
    }
    let shifted = DisassembledFunction(symbol: "shifted", demangledName: nil, startAddress: 0xffc,
        instructions: frame.instructions, source: .address)
    #expect(CalleeRegisterSummary.framedCallTarget(of: shifted, isFunction: { $0 == 0x2000 }) == nil)
    #expect(CalleeRegisterSummary.of(shifted, isFunction: { $0 == 0x2000 })?.framedCallTarget == nil)
    let gap = DisassembledFunction(symbol: "gap", demangledName: nil, startAddress: 0x1000,
        instructions: frame.instructions.enumerated().map { index, instruction in
            Instruction(address: instruction.address + (index >= 3 ? 4 : 0), text: instruction.text,
                controlFlow: instruction.controlFlow, branchTarget: instruction.branchTarget, detail: instruction.detail)
        }, source: .address)
    #expect(CalleeRegisterSummary.framedCallTarget(of: gap, isFunction: { $0 == 0x2000 }) == nil)

    let floatProvider = try bodyArityRaw([0x1e6e1001, 0x1e612800, 0xd65f03c0], at: 0x2000)
    summaries = [0x1000: initial, 0x2000: try makeSummary(floatProvider)]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[0x1000]?.provenFloatArgumentReads == RegisterSet([0]))
    #expect(summaries[0x1000]?.floatArgumentWidths[0] == 64)

    // Framed and tail forwarders can compose; an alias is not a provider
    // until it reaches an independently decoded body with its own reads.
    let alias = try bodyArityRaw([0x14000400], at: 0x2000) // b 0x3000
    let leaf = try bodyArityRaw([0x91002400, 0xd65f03c0], at: 0x3000)
    summaries = [0x1000: initial, 0x2000: try makeSummary(alias), 0x3000: try makeSummary(leaf)]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[0x1000]?.provenArgumentReads == RegisterSet([0]))

    // A declared target without decoded evidence supplies no positive proof.
    var missing = initial; missing.provenArgumentReads = [0]
    summaries = [0x1000: missing]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[0x1000]?.provenArgumentReads.isEmpty == true)
    var partial = try makeSummary(provider); partial.inputProofEntry = 0x2004
    summaries = [0x1000: initial, 0x2000: partial]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[0x1000]?.provenArgumentReads.isEmpty == true)
    var wrongEntry = initial; wrongEntry.inputProofEntry = 0x1004; wrongEntry.framedCallTarget = 0x2000
    summaries = [0x1000: wrongEntry, 0x2000: try makeSummary(provider)]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[0x1000]?.provenArgumentReads.isEmpty == true)

    // A cycle cannot promote stale GP or FP facts into an independent seed.
    var first = initial
    var second = try makeSummary(bodyArityRaw(bodyArityFrameWords(at: 0x2000, target: 0x1000), at: 0x2000))
    first.provenArgumentReads = [0]; second.provenArgumentReads = [0]
    first.provenFloatArgumentReads = [0]; second.provenFloatArgumentReads = [0]
    first.floatArgumentWidths = [0:64]; second.floatArgumentWidths = [0:64]
    summaries = [0x1000: first, 0x2000: second]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries.values.allSatisfy { $0.provenArgumentReads.isEmpty && $0.provenFloatArgumentReads.isEmpty && $0.floatArgumentWidths.isEmpty })
}

#if arch(arm64)
@Test func bodyArityBoundsAgreeWithNativeCContractsIfPresent() throws {
    for path in ["Fixtures/Sample/body-arity-O0-oracle", "Fixtures/Sample/body-arity-O2-oracle", "Fixtures/Sample/body-arity-Os-oracle"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.standardOutput = pipe; process.standardError = pipe
        try process.run(); let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: output))
        #expect(output.contains("PASS 84 native body-arity observations and 49 opaque effects"), Comment(rawValue: output))
    }
}
#endif
