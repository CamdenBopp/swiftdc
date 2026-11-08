import Foundation
// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

import Testing
@testable import SwiftDecompilerCore

private func detachedBlockAnalysis(_ words: [UInt32]) throws -> FunctionAnalysis {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    #expect(decoded.count == words.count)
    let instructions = decoded.map {
        Instruction(address: $0.address, text: $0.text,
                    controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
    }
    let function = DisassembledFunction(symbol: "method", demangledName: nil, startAddress: 0x1000,
                                       instructions: instructions, source: .address)
    return ValueTracer().analyze(function, entry: .objectiveC(argumentCount: 1))
}

@Test func detachedCleanupBlockDoesNotInheritMethodEntryRegisters() throws {
    // ret; mov x19,x0; mov x0,x19; bl cleanup. The x0 delivered to an exception
    // landing pad is the exception object, not the self passed at method entry.
    let cleanup = try detachedBlockAnalysis([0xd65f03c0, 0xaa0003f3, 0xaa1303e0, 0x940003fd])
    #expect(cleanup.exitValues[0x1000] == .selfPointer)
    #expect(cleanup.callSites[0x100c]?.arguments.first != .selfPointer)
    // ret; mov x0,x2; bl cleanup — no source argument is proven there either.
    let argument = try detachedBlockAnalysis([0xd65f03c0, 0xaa0203e0, 0x940003fe])
    #expect(argument.callSites[0x1008]?.arguments.first != .argument(0))
    // ret; mov x0,sp; bl cleanup — an unknown resumed frame is not entry SP.
    let frame = try detachedBlockAnalysis([0xd65f03c0, 0x910003e0, 0x940003fe])
    #expect(frame.callSites[0x1008]?.arguments.first != .frame(0))
}

@Test func actualEntryWithBackedgeRetainsABISeed() throws {
    // cbnz x1,entry; ret. Entry has a CFG predecessor but also the real caller.
    let loop = try detachedBlockAnalysis([0xb5000001, 0xd65f03c0])
    #expect(loop.exitValues[0x1004] == .selfPointer)
}

@Test func reachableSuccessorPreservesMethodValues() throws {
    // mov x19,x0; b successor; successor: mov x0,x19; bl cleanup.
    let reachable = try detachedBlockAnalysis([0xaa0003f3, 0x14000001, 0xaa1303e0, 0x940003fd])
    #expect(reachable.callSites[0x100c]?.arguments.first == .selfPointer)
}
