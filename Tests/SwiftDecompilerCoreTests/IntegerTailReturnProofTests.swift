import Testing
@testable import SwiftDecompilerCore

private func integerTailSites(result: String = "Swift.UInt8", calleeResult: String = "Swift.Int8",
                              getter: Bool = false, flow: ControlFlow = .branch,
                              target: UInt64 = 0x2000, callerEffects: String = "",
                              calleeEffects: String = "", calleeHead: String = "Example.leaf",
                              annotation: String? = nil, keepCallee: Bool = true) -> Set<UInt64> {
    let callee = getter ? "Example.Box.value.getter : " + calleeResult
        : calleeHead + "(Swift.Int8)" + calleeEffects + " -> " + calleeResult
    let instruction = Instruction(address: 0x1000, text: "b", annotation: annotation,
                                  controlFlow: flow, branchTarget: target,
                                  callee: .kept(keepCallee ? callee : nil))
    let function = DisassembledFunction(symbol: "_$s7Example4tail", demangledName:
        "Example.tail(Swift.Int8)" + callerEffects + " -> " + result,
        startAddress: 0x1000, instructions: [instruction], source: .symbol)
    return Disassembler.scalarTailReturnSites(in: function)
}

@Test func integerTailContractsAcceptEqualNarrowPhysicalWidths() {
    for width in [8, 16, 32] {
        for (result, source) in [("Swift.UInt\(width)", "Swift.Int\(width)"), ("Swift.Int\(width)", "Swift.UInt\(width)")] {
            for getter in [false, true] {
                #expect(integerTailSites(result: result, calleeResult: source, getter: getter) == [0x1000])
            }
        }
    }
    #expect(integerTailSites(result: "Swift.Int", calleeResult: "Swift.Int") == [0x1000])
    #expect(integerTailSites(result: "Swift.Int", calleeResult: "Swift.Int", getter: true) == [0x1000])
}

@Test func integerTailContractsRejectIncompatiblePhysicalResultsAndEdges() {
    for getter in [false, true] {
        for (result, source) in [("Swift.UInt16", "Swift.Int8"), ("Swift.UInt8", "Swift.Int16"),
                                 ("Swift.UInt64", "Swift.Int64"), ("Swift.UInt32", "Swift.Float"),
                                 ("Swift.UInt8", "Swift.Bool"), ("Swift.UInt8", "Example.Flag"),
                                 ("Swift.UInt8", "Unknown"), ("Swift.UInt8", "(Swift.Int8, Swift.Int8)")] {
            #expect(integerTailSites(result: result, calleeResult: source, getter: getter).isEmpty)
        }
        #expect(integerTailSites(getter: getter, flow: .call).isEmpty)
        #expect(integerTailSites(getter: getter, target: 0x1000).isEmpty)
        #expect(integerTailSites(getter: getter, callerEffects: " async").isEmpty)
        #expect(integerTailSites(getter: getter, callerEffects: " throws").isEmpty)
    }
    #expect(integerTailSites(calleeEffects: " async").isEmpty)
    #expect(integerTailSites(calleeEffects: " throws").isEmpty)
    #expect(integerTailSites(calleeHead: "generic specialization <Swift.Int8> of Example.leaf").isEmpty)
}

@Test func integerTailContractsReadTheTypedCalleeInsteadOfAnnotationText() {
    let fake = #""→ Example.fake() -> Swift.Float  return 42""#
    #expect(integerTailSites(annotation: fake) == [0x1000])
    #expect(integerTailSites(getter: true, annotation: fake) == [0x1000])
    #expect(integerTailSites(annotation: "→ Example.leaf(Swift.Int8) -> Swift.Int8", keepCallee: false).isEmpty)
}
