import Foundation
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

@Test func objcArgumentABIMixedBanks() {
    // W5Engine's channel:duration:uuid:tcpDump:reply: shape. Runtime byte
    // offsets are deliberately present: they must not be used as GP indices.
    #expect(ObjCArgumentABI.locations(encoding: "v56@0:8@16d24@32B40@?48", argumentCount: 5)
        == ["x2": 0, "v0": 1, "x3": 2, "x4": 3, "x5": 4])
    #expect(ObjCArgumentABI.locations(encoding: "v32@0:8f16@20d24", argumentCount: 3)
        == ["v0": 0, "x2": 1, "v1": 2])
}

@Test func objcArgumentABIStackPackingAndIndependentExhaustion() {
    #expect(ObjCArgumentABI.locations(encoding: "v@:" + String(repeating: "i", count: 8) + "d", argumentCount: 9)
        == ["x2": 0, "x3": 1, "x4": 2, "x5": 3, "x6": 4, "x7": 5,
            "stack@0": 6, "stack@4": 7, "v0": 8])
    #expect(ObjCArgumentABI.stackSlotWidths(
        encoding: "v@:" + String(repeating: "i", count: 8) + "d", argumentCount: 9)
        == ["stack@0": 4, "stack@4": 4])
    let fpOverflow = ObjCArgumentABI.locations(encoding: "v@:" + String(repeating: "d", count: 9) + "@", argumentCount: 10)
    #expect(fpOverflow["stack@0"] == 8)
    #expect(fpOverflow["x2"] == 9)
    #expect(ObjCArgumentABI.floatingStackSlots(
        encoding: "v@:" + String(repeating: "d", count: 9) + "@", argumentCount: 10)
        == ["stack@0"])
}

@Test func objcArgumentABIConservativeParsing() {
    #expect(ObjCArgumentABI.locations(encoding: "v32@0:8r^v16@\"NSObject\"24", argumentCount: 2)
        == ["x2": 0, "x3": 1])
    #expect(ObjCArgumentABI.locations(encoding: "v@:{Pair=dd}@", argumentCount: 2).isEmpty)
    #expect(ObjCArgumentABI.locations(encoding: "v@:^", argumentCount: 1).isEmpty)
    #expect(ObjCArgumentABI.locations(encoding: "v@:@", argumentCount: 2).isEmpty)
    #expect(ObjCArgumentABI.locations(encoding: "v@:@\"Unclosed", argumentCount: 1).isEmpty)
}

@Test func objcArgumentABIMixedValuesReachBody() throws {
    // stp x2, x3, [x0, #8]; str d0, [x0, #24]; ret
    let bytes: [UInt8] = [0x02, 0x8c, 0x00, 0xa9, 0x00, 0x0c, 0x00, 0xfd, 0xc0, 0x03, 0x5f, 0xd6]
    let engine = try #require(CapstoneEngine())
    let instructions = engine.disassemble(Data(bytes), address: 0x1000).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    let function = DisassembledFunction(symbol: "-[Probe channel:duration:uuid:]", demangledName: nil,
        startAddress: 0x1000, instructions: instructions, source: .symbol)
    let locations = ObjCArgumentABI.locations(encoding: "v40@0:8@16d24@32", argumentCount: 3)
    for entry: MethodEntryConvention in [
        .objectiveC(argumentCount: 3, scalarArguments: locations),
        .objectiveCInitializer(argumentCount: 3, scalarArguments: locations),
    ] {
        let analysis = ValueTracer().analyze(function, entry: entry)
        #expect(analysis.selfFieldAccesses[0x1000]?.storedValues == [.argument(0), .argument(2)])
        #expect(analysis.selfFieldAccesses[0x1004]?.storedValue == .argument(1))
    }
}
