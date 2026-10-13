import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func returnPathProbesSelectNativeExitsAcrossLayoutsIfPresent() async throws {
    let path = "Fixtures/Sample/libReturnPaths.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    #expect(functions.count == 8)
    for name in ["split", "shuffled", "nested", "joined", "detached"] {
        let function = try #require(functions.first { $0.symbol == "_returnpath_\(name)" })
        let pointer = try #require(dlsym(handle, "returnpath_\(name)"))
        let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64) -> UInt64).self)
        let inputs: [UInt64] = [0, 1, 6, 7, 15, 16, 18, 19, 1 << 32, 1 << 63, .max]
        let cases = ReturnExpectation.samples(in: function.startAddress, inputs: inputs) { native($0) }
        let score = try ProbeScore(cases, mode: .rawRegister)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        Probe.recording(score.recorder) { Probe.observe(analysis, of: function) }
        #expect(try score.report().counts["verified"] == inputs.count, "\(name)")
    }
    for name in ["cycle", "external"] {
        let function = try #require(functions.first { $0.symbol == "_returnpath_\(name)" })
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        let paths = Probe.returnPathConditions(analysis, of: function)
        for insn in function.instructions where insn.controlFlow == .return {
            #expect(paths[insn.address] == .unknown, "\(name)")
        }
    }
}

@Test func unsupportedForksAndPathBlockCapsDecline() {
    let instructions = [Instruction(address: 0, text: "br x8", controlFlow: .branch),
                        Instruction(address: 4, text: "ret", controlFlow: .return),
                        Instruction(address: 8, text: "ret", controlFlow: .return)]
    let function = DisassembledFunction(symbol: "_fork", demangledName: "fork", startAddress: 0,
                                        instructions: instructions, source: .symbol, switchTargets: [0: [4, 8]])
    #expect(Probe.returnPathConditions(FunctionAnalysis(), of: function) == [4: .unknown, 8: .unknown])
    let unresolved = DisassembledFunction(symbol: "_indirect", demangledName: "indirect", startAddress: 0,
                                          instructions: Array(instructions.prefix(2)), source: .symbol)
    #expect(Probe.returnPathConditions(FunctionAnalysis(), of: unresolved)[4] == .unknown)
    let oversized = DisassembledFunction(symbol: "_cap", demangledName: "cap", startAddress: 0,
        instructions: (0..<257).map { Instruction(address: UInt64($0 * 4), text: "ret", controlFlow: .return) }, source: .symbol)
    #expect(Probe.returnPathConditions(FunctionAnalysis(), of: oversized).isEmpty)
}

@Test func returnPathExpressionDepthAndNodeCapsDiscardFacts() {
    var chainAnalysis = FunctionAnalysis()
    let chainLength = 26, sharedReturn = UInt64((chainLength + 1) * 4)
    var chain: [Instruction] = []
    for index in 0..<chainLength {
        let address = UInt64(index * 4)
        chain.append(Instruction(address: address, text: "b.eq", controlFlow: .conditionalBranch, branchTarget: sharedReturn))
        chainAnalysis.branchConditions[address] = .binary(.equal, .argument(0), .immediate(UInt64(index)))
    }
    let deepReturn = UInt64(chainLength * 4)
    chain.append(Instruction(address: deepReturn, text: "ret", controlFlow: .return))
    chain.append(Instruction(address: sharedReturn, text: "ret", controlFlow: .return))
    let deep = DisassembledFunction(symbol: "_depth", demangledName: "depth", startAddress: 0,
                                    instructions: chain, source: .symbol)
    #expect(Probe.returnPathConditions(chainAnalysis, of: deep)[deepReturn] == .unknown)

    var joinAnalysis = FunctionAnalysis(), joins: [Instruction] = []
    for index in 0..<6 {
        let address = UInt64(index * 12)
        joins.append(Instruction(address: address, text: "b.eq", controlFlow: .conditionalBranch, branchTarget: address + 8))
        joins.append(Instruction(address: address + 4, text: "b", controlFlow: .branch, branchTarget: address + 12))
        joins.append(Instruction(address: address + 8, text: "b", controlFlow: .branch, branchTarget: address + 12))
        joinAnalysis.branchConditions[address] = .binary(.equal, .argument(0), .immediate(UInt64(index)))
    }
    joins.append(Instruction(address: 72, text: "ret", controlFlow: .return))
    let wide = DisassembledFunction(symbol: "_nodes", demangledName: "nodes", startAddress: 0,
                                    instructions: joins, source: .symbol)
    #expect(Probe.returnPathConditions(joinAnalysis, of: wide)[72] == .unknown)
}

@Test func guardedReturnPathsSurviveSavedTraceReplayIfPresent() async throws {
    let path = "Fixtures/Sample/libReturnPaths.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let recorder = ProbeRecorder()
    let function = try #require(try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "returnpath_shuffled").first
    })
    let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
    Probe.recording(recorder) { Probe.observe(analysis, of: function) }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-returnpaths-\(UUID()).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    let trace = recorder.records.map { $0.jsonLine() }.joined(separator: "\n") + "\n" + recorder.summaryLine() + "\n"
    try Data(trace.utf8).write(to: file)
    let score = try ProbeScore([.init(7, in: function.startAddress, arguments: [0]),
                                .init(8, in: function.startAddress, arguments: [.max])], mode: .rawRegister)
    try score.readTrace(at: file)
    #expect(try score.report().counts["verified"] == 2)
}
