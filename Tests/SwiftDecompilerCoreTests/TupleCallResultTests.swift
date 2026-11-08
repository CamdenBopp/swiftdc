import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func aTupleCallDoesNotSupplyAWholeValueInAScalarRegister() throws {
    let engine = try #require(CapstoneEngine())
    for signature in ["M.pair() -> (high: Swift.UInt64, low: Swift.UInt64)",
                      "M.floats() -> (Swift.Double, Swift.Double)"] {
        let instructions = engine.disassemble(Data([0x00, 0x04, 0x00, 0x94, 0xc0, 0x03, 0x5f, 0xd6]), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text,
                        annotation: $0.controlFlow == .call ? signature : nil,
                        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "word", demangledName: nil, startAddress: 0x1000,
                                            instructions: instructions, source: .symbol)
        let analysis = ValueTracer().analyze(function, entry: nil)
        #expect(analysis.exitValues[0x1004] == nil || analysis.exitValues[0x1004] == .unknown)
        #expect(analysis.exitFloatValues[0x1004] == nil || analysis.exitFloatValues[0x1004] == .unknown)
    }
}

@Test func nativeFullWidthTupleWordsRemainExplicitDeclinesIfPresent() async throws {
    let path = "Fixtures/Sample/libResearchOnone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    for preset in DemanglePreset.allCases {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: preset).disassemble(path: path)
        }
        for name in ["signedHigh", "unsignedHigh"] {
            let function = try #require(functions.first { $0.semanticName?.contains(".\(name)(") == true })
            for body in [function.renderPseudo(), function.renderStructured()] {
                #expect(body.contains("return ?"), "\(body)")
                #expect(body.contains("multipliedFullWidth("), "the actual call must remain: \(body)")
                #expect(!body.contains("return Swift."), "\(body)")
            }
        }
    }
}

@Test func tupleResultClassificationDoesNotReadCommasFromParametersOrClosures() {
    #expect(!DisassembledFunction.hasTupleResult("M.scalar(pair: (Swift.Int, Swift.Int)) -> Swift.Int"))
    #expect(!DisassembledFunction.hasTupleResult("M.factory() -> (Swift.Int, Swift.Int) -> Swift.Int"))
    #expect(!DisassembledFunction.hasTupleResult("M.unit() -> ()"))
    #expect(DisassembledFunction.hasTupleResult("M.pair.getter : (Swift.Int, Swift.Int)"))
    #expect(DisassembledFunction.hasTupleResult("M.nested() -> (M.Pair<Swift.Int, Swift.Int>, Swift.UInt64)"))
    #expect(DisassembledFunction.hasTupleResult("M.callbacks() -> ((Swift.Int) -> Swift.Int, Swift.UInt64)"))
    #expect(DisassembledFunction.hasTupleResult("M.callbacks.getter : ((Swift.Int) -> Swift.Int, Swift.UInt64)"))
    #expect(DisassembledFunction.hasTupleResult("M.grouped() -> ((Swift.Int, Swift.Int))"))
}
