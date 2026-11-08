import Foundation
import Testing
@testable import SwiftDecompilerCore

private func floatingReviewBody(_ words: [UInt32], at address: UInt64 = 0x1000) throws -> [Instruction] {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: address)
    try #require(decoded.count == words.count)
    return decoded.map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
}

/// A valid seeded AbstractValue whose Boolean conditions are source arguments.
/// This tests the public seeded-state contract, not a claim that a particular
/// compiler lowers seven source branches to this exact expression shape.
private func floatingReviewSelectedBits(levels: Int) -> AbstractValue {
    var value = AbstractValue.immediate(0x3ff0_0000_0000_0000)
    for index in 0..<levels {
        value = .select(condition: .argument(index), whenTrue: value,
                        whenFalse: .immediate(0x4000_0000_0000_0000))
    }
    return value
}

private func floatingReviewExit(words: [UInt32], seeds: [String: AbstractValue]) throws -> AbstractValue? {
    let body = try floatingReviewBody(words)
    let function = DisassembledFunction(symbol: "_floatingReview", demangledName: nil,
        startAddress: 0x1000, instructions: body, source: .symbol)
    let result = ValueTracer().analyze(function, entry: .swiftValueInstance(seededRegisters: seeds))
    return result.exitFloatValues[try #require(body.last).address]
}

@Test func selectedFloatingUnaryChecksDepthAfterNormalizingItsOperand() throws {
    for levels in [6, 7] {
        // fneg d0,d0; ret. Per-arm IEEE wrappers add one dependency level.
        let value = try floatingReviewExit(words: [0x1e614000, 0xd65f03c0],
            seeds: ["v0": floatingReviewSelectedBits(levels: levels)])
        if levels == 7 {
            #expect(value == nil || value == .unknown)
        } else {
            #expect(value != nil && value != .unknown)
        }
    }
}

@Test func selectedFloatingBinaryChecksDepthAfterNormalizingItsOperands() throws {
    for levels in [6, 7] {
        // fadd d0,d1,d2; ret. A normalized depth-8 operand cannot take a parent.
        let value = try floatingReviewExit(words: [0x1e622820, 0xd65f03c0], seeds: [
            "v1": floatingReviewSelectedBits(levels: levels),
            "v2": .immediate(0x3ff0_0000_0000_0000),
        ])
        if levels == 7 {
            #expect(value == nil || value == .unknown)
        } else {
            #expect(value != nil && value != .unknown)
        }
    }
}

/// The empty Mach-O backs the resolver; method metadata and ARM64 instructions
/// are explicit, just as in ObjCSendResultTests. No native code executes here.
private func floatingReviewObjCCallChain(
    calls: Int
) async throws -> (function: DisassembledFunction, recorder: ProbeRecorder, returnAddress: UInt64) {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("floating-probe-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    return try await withStableDependencies {
        let machO = try BinaryLoader.load(path: file.path)
        let method = ObjCMethodBinding(className: "ProbeFP", selector: "chain:",
            typeEncoding: "d24@0:8d16", isClassMethod: false,
            signature: "- (double)chain:(double)arg0;")
        let callee = "Review.next(Swift.Double) -> Swift.Double"
        let index = ObjCMetadataIndex(methods: [0x1000: [method]], fieldMaps: [:])
        let resolver = Disassembler.ReferenceResolver(names: [0x3000: callee], stringRanges: [],
            machO: machO, demangleSymbol: { _ in nil })
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [0x3000],
            objcIndex: index, fieldMaps: [:], selfIndex: SelfTypeIndex(bindings: [:]),
            vtableIndex: VTableIndex(), enumCaseIndex: EnumCaseIndex(),
            payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
            classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
        // Every BL targets 0x3000. Each fresh v0 feeds one following call; no
        // result is duplicated, so repeated-use bindings cannot flatten it.
        let words = (0..<calls).map { UInt32(0x94000800) - UInt32($0) } + [UInt32(0xd65f03c0)]
        let decoded = try floatingReviewBody(words)
        let body = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail,
                callee: .kept($0.controlFlow == .call ? callee : nil))
        }
        let function = DisassembledFunction(symbol: method.displayName, demangledName: nil,
            startAddress: 0x1000, instructions: body, source: .objcMetadata, objcMethod: method)
        let recorder = ProbeRecorder(includeNames: true)
        let analyzed = Probe.recording(recorder) { Disassembler().analyzeFunction(function, context: context) }
        return (analyzed, recorder, try #require(body.last).address)
    }
}

@Test func aPartialObjCFloatingReturnIsNotVerifiedAsComplete() async throws {
    let result = try await floatingReviewObjCCallChain(calls: 10)
    let returns = result.function.renderPseudo().split(separator: "\n").map {
        $0.trimmingCharacters(in: .whitespaces)
    }.filter { $0.hasPrefix("return ") }
    let line = try #require(returns.first)
    // Require the intended partial-expression trigger, not an empty result
    // or a wholly unknown return that would take the existing unknown path.
    #expect(returns.count == 1)
    #expect(line != "return ?" && line.contains("?"), Comment(rawValue: line))
    let outcomes = result.recorder.records.filter {
        $0.event == .returnOutcome && $0.address == result.returnAddress
    }
    #expect(outcomes.count == 1)
    #expect(outcomes.first?["status"] == .label("partial"))
    #expect(!result.recorder.records.contains {
        $0.event == .returnValue && $0.address == result.returnAddress
    })
    // A shallow complete return must still emit its existing verified claim.
    do {
        let result = try await floatingReviewObjCCallChain(calls: 1)
        let text = result.function.renderPseudo()
        #expect(text.contains("return ") && !text.contains("?"), Comment(rawValue: text))
        let outcomes = result.recorder.records.filter {
            $0.event == .returnOutcome && $0.address == result.returnAddress
        }
        #expect(outcomes.count == 1)
        #expect(outcomes.first?["status"] == .label("recovered"))
        #expect(result.recorder.records.contains {
            $0.event == .returnValue && $0.address == result.returnAddress
        })
    }
}
