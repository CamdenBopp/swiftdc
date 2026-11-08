import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The value tracer's result for single instructions, exported for the z3
/// equivalence check in Tools/semantics (see its README). Runs only when
/// `SWIFTDC_SEMANTICS_WORDS` names a file of instruction words, one hex word
/// per line; each is traced alone as `insn; ret` with x0–x3 holding
/// arguments 0–3, and x0 at the `ret` is written to `SWIFTDC_SEMANTICS_OUT`
/// as one JSON line: `{"word", "text", "value"}`, `value` null when the
/// tracer claims nothing.
@Test func exportTracerSemanticsIfRequested() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let wordsPath = environment["SWIFTDC_SEMANTICS_WORDS"] else { return }
    let outPath = try #require(environment["SWIFTDC_SEMANTICS_OUT"])
    let words = try String(contentsOfFile: wordsPath, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map { line in try #require(UInt32(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "0x", with: ""), radix: 16)) }
    let engine = try #require(CapstoneEngine())
    let recorder = ProbeRecorder(includeNames: true)
    let ret: UInt32 = 0xd65f03c0
    var lines: [String] = []
    lines.reserveCapacity(words.count)
    for word in words {
        let bytes = [word, ret].flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        let hex = "\"0x" + String(word, radix: 16) + "\""
        guard decoded.count == 2 else {
            lines.append("{\"word\":\(hex),\"text\":null,\"value\":null}")
            continue
        }
        let function = DisassembledFunction(symbol: "_insn", demangledName: nil, startAddress: 0x1000,
            instructions: decoded.map { insn in
                Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                            branchTarget: insn.branchTarget, detail: insn.detail)
            }, source: .symbol)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1, "x2": 2, "x3": 3]))
        let text = recorder.jsonValue(.label(decoded[0].text))
        let value = analysis.exitValues[decoded[1].address].flatMap { $0 == .unknown ? nil : $0 }
        let exported = value.map { recorder.jsonValue(ProbeValue.abstractValue($0)) } ?? "null"
        lines.append("{\"word\":\(hex),\"text\":\(text),\"value\":\(exported)}")
    }
    try (lines.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
}

/// The structurer's text-path branch condition for short sequences, exported
/// for the same z3 check (Tools/semantics/conditions.py). Runs only when
/// `SWIFTDC_CONDITIONS_WORDS` names a file whose lines are hex words, the
/// last a conditional branch to +8; each line is laid out as `words…; ret;
/// ret` and the condition under which the branch is taken is written to
/// `SWIFTDC_CONDITIONS_OUT` as `{"words", "texts", "condition"}`.
@Test func exportTextConditionsIfRequested() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let wordsPath = environment["SWIFTDC_CONDITIONS_WORDS"] else { return }
    let outPath = try #require(environment["SWIFTDC_CONDITIONS_OUT"])
    let engine = try #require(CapstoneEngine())
    let recorder = ProbeRecorder(includeNames: true)
    let ret: UInt32 = 0xd65f03c0
    var lines: [String] = []
    for line in try String(contentsOfFile: wordsPath, encoding: .utf8).split(whereSeparator: \.isNewline) {
        let words = try line.split(separator: " ").map { try #require(UInt32($0, radix: 16)) }
        let all = words + [ret, ret]
        let bytes = all.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        let wordList = words.map { "\"" + String($0, radix: 16) + "\"" }.joined(separator: ",")
        guard decoded.count == all.count else {
            lines.append("{\"words\":[\(wordList)],\"texts\":null,\"condition\":null}")
            continue
        }
        let function = DisassembledFunction(symbol: "_condition", demangledName: nil, startAddress: 0x1000,
            instructions: decoded.map { insn in
                Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                            branchTarget: insn.branchTarget, detail: insn.detail)
            }, source: .symbol)
        let blocks = function.basicBlocks()
        let condition = ControlFlowStructure(blocks: blocks).condition(of: blocks[0]).text
        let texts = decoded.prefix(words.count).map { recorder.jsonValue(.label($0.text)) }.joined(separator: ",")
        lines.append("{\"words\":[\(wordList)],\"texts\":[\(texts)],\"condition\":\(recorder.jsonValue(.label(condition)))}")
    }
    try (lines.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
}
