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
