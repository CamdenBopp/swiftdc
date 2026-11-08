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

/// A callee's name is its name, not the analysis notes after it. Notes follow
/// two spaces; only four known ones were cut, so `castOptional`'s callee was
/// named `swift_dynamicCastClass  let r0 = (? as? Reconstruction.Dog)` and a
/// `--function` search matched text from the notes.
@Test func callGraphNamesCarryNoAnalysisNotesIfPresent() async throws {
    for path in graphFixtures where FileManager.default.fileExists(atPath: path) {
        let machO = try BinaryLoader.load(path: path)
        let graph = await withStableDependencies {
            CallGraph(functions: await Disassembler(preset: .default)
                .disassembleStreaming(machO: machO, transform: CallGraph.sites(of:)))
        }
        let noted = graph.names.values.filter { $0.contains("  ") }
        #expect(noted.isEmpty, "\(path): \(noted.sorted())")
    }
    let path = "Fixtures/Sample/libReconstruction.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let graph = await withStableDependencies {
        CallGraph(functions: await Disassembler(preset: .default)
            .disassembleStreaming(machO: machO, transform: CallGraph.sites(of:)))
    }
    // The stub `castOptional` calls (`xcrun nm -m`: 0x2cb0 is its symbol stub).
    #expect(graph.name(of: 0x2cb0) == "swift_dynamicCastClass")
}

/// A `blr` through a bound GOT slot names its import: it is an external
/// call, not an unresolved one. Counting it as unresolved put 5,864 of an
/// app's sites in the "no provable target" note where 4,023 had one.
@Test func aNamedCallWithoutAnAddressIsExternalNotUnresolved() {
    let function = DisassembledFunction(
        symbol: "f", demangledName: nil, startAddress: 0x1000,
        instructions: [
            Instruction(address: 0x1000, text: "blr x8", annotation: "→ objc_retainAutorelease", controlFlow: .call),
            Instruction(address: 0x1004, text: "blr x9", controlFlow: .call),
            Instruction(address: 0x1008, text: "ret", controlFlow: .return),
        ],
        source: .symbol)
    let graph = CallGraph(functions: [function])
    #expect(graph.unresolvedCallSites == 1)
    #expect(graph.externalCallSites == 1)
}
