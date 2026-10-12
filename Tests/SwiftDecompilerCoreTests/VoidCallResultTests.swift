import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func swiftSetterDoesNotProduceAValue() throws {
    let engine = try #require(CapstoneEngine())
    let body = engine.disassemble(Data([0x00, 0x04, 0x00, 0x94, 0xc0, 0x03, 0x5f, 0xd6]), address: 0x1000).map {
        Instruction(address: $0.address, text: $0.text,
                    annotation: $0.controlFlow == .call ? "M.Counter.value.setter : Swift.Int" : nil,
                    controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
    }
    let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000, instructions: body, source: .symbol)
    let result = ValueTracer().analyze(function, entry: nil)
    #expect(result.exitValues[0x1004] == nil || result.exitValues[0x1004] == .unknown)
    #expect(result.exitFloatValues[0x1004] == nil || result.exitFloatValues[0x1004] == .unknown)

    let declared = ObjCMethodBinding(className: "Base", selector: "write:", typeEncoding: "v@:q", isClassMethod: false, signature: "")
    let override = ObjCMethodBinding(className: "Subclass", selector: "write:", typeEncoding: "q@:q", isClassMethod: false, signature: "")
    let exact = ObjCMetadataIndex(methods: [1: [declared]], fieldMaps: [:])
    #expect(exact.outgoingReturnsVoid(selector: "write:", className: "Base", isClassMethod: false))
    #expect(!exact.outgoingReturnsVoid(selector: "write:", className: "Unknown", isClassMethod: false))
    #expect(!exact.outgoingReturnsVoid(selector: "write:", className: "Base", isClassMethod: true))
    let conflicting = ObjCMetadataIndex(methods: [1: [declared], 2: [override]], fieldMaps: [:])
    #expect(!conflicting.outgoingReturnsVoid(selector: "write:", className: "Base", isClassMethod: false))
}

@Test func objectiveCVoidReturnIsProvenByItsEncodingIfPresent() async throws {
    let path = "Fixtures/Sample/libAuditVoid.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "captureVoidResult")
    }
    let function = try #require(functions.first)
    for text in [function.renderPseudo(), function.renderStructured()] {
        #expect(text.contains("[self write:7]"), Comment(rawValue: text))
        #expect(!text.contains("return [self write:"), Comment(rawValue: text))
        #expect(text.contains("return ?"), Comment(rawValue: text))
    }
}
