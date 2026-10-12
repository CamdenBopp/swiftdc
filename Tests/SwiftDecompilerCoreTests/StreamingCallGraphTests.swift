import Foundation
import Testing
@testable import SwiftDecompilerCore

private let graphFixtures = [
    "Fixtures/Sample/libSample.dylib",
    "Fixtures/Sample/libReconstruction.opt.dylib",
    "Fixtures/Sample/libAsyncFns.opt.dylib",
    "Fixtures/Sample/libIndirect.dylib",
    "Fixtures/Sample/libObjCNonselfOutgoing.dylib",
]

/// `xrefs` streams the image and keeps only call sites per function
/// (`CallGraph.sites(of:)`), because holding every instruction put
/// Swiftcord's past 8 GB. The graph must not notice: same names, same edges,
/// same function set, same unresolved count as the graph over every
/// instruction of the whole-image decode.
@Test func aStreamedCallGraphMatchesTheWholeImageGraphIfPresent() async throws {
    for path in graphFixtures where FileManager.default.fileExists(atPath: path) {
        let machO = try BinaryLoader.load(path: path)
        let (whole, streamed) = await withStableDependencies {
            let disassembler = Disassembler(preset: .default)
            return (
                CallGraph(functions: await disassembler.disassemble(machO: machO)),
                CallGraph(functions: await disassembler.disassembleStreaming(machO: machO, transform: CallGraph.sites(of:)))
            )
        }
        #expect(!whole.edges.isEmpty, "\(path): no edges")
        #expect(Set(streamed.edges) == Set(whole.edges), "\(path)")
        #expect(streamed.names == whole.names, "\(path)")
        #expect(streamed.functionAddresses == whole.functionAddresses, "\(path)")
        #expect(streamed.unresolvedCallSites == whole.unresolvedCallSites, "\(path)")
    }
}

/// The slimmed function keeps its last instruction because the graph reads
/// spans from it: a `b` into the middle of another function is a shared
/// tail, not a call, and only the span says the target is inside one. No
/// fixture has such a branch, so this one is built by hand.
@Test func aSitesOnlyFunctionKeepsItsSpan() {
    let caller = DisassembledFunction(
        symbol: "caller", demangledName: nil, startAddress: 0x1000,
        instructions: [
            Instruction(address: 0x1000, text: "mov x0, #1"),
            Instruction(address: 0x1004, text: "b 0x2008", annotation: "→ callee",
                        controlFlow: .branch, branchTarget: 0x2008),
        ],
        source: .symbol)
    let callee = DisassembledFunction(
        symbol: "callee", demangledName: nil, startAddress: 0x2000,
        instructions: (0..<5).map { Instruction(address: 0x2000 + UInt64($0 * 4), text: "nop") }
            + [Instruction(address: 0x2014, text: "ret", controlFlow: .return)],
        source: .symbol)
    let whole = CallGraph(functions: [caller, callee])
    let slim = CallGraph(functions: [caller, callee].map(CallGraph.sites(of:)))
    #expect(whole.edges.isEmpty, "a branch into callee's body is a shared tail")
    #expect(Set(slim.edges) == Set(whole.edges))
}
