import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let asyncCallFixture = "Fixtures/Sample/libAsyncCallEffects.dylib"

/// Each adapter allocates a context for its leaf, which stores 7 to slot 16,
/// calls something, and observes slot 16. The native observations are the
/// oracle: the global, conditional and interior leaves let a call rewrite the
/// slot and observe it; the read-only leaf's call writes nothing, and the
/// snapshot leaf observes a copy taken before the call.
@Test func asyncCallLeavesRunAsDocumentedIfPresent() throws {
    guard FileManager.default.fileExists(atPath: asyncCallFixture) else { return }
    let library = try #require(dlopen(asyncCallFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Adapter = @convention(c) (UnsafeMutablePointer<UInt64>, UInt64) -> UInt64
    func run(_ name: String, flag: UInt64 = 0) throws -> (UInt64, UInt64) {
        let adapter = try unsafeBitCast(#require(dlsym(library, "async_calls_" + name)), to: Adapter.self)
        var context: [UInt64] = [0, 0, 3, 0]
        let result = context.withUnsafeMutableBufferPointer { adapter($0.baseAddress!, flag) }
        return (result, context[2])
    }
    for name in ["incoming", "global", "implicit", "interior"] {
        #expect(try run(name) == (11, 11), "\(name)")
    }
    #expect(try run("readonly") == (7, 7))
    // Loaded into x19 before the call rewrote the slot.
    #expect(try run("snapshot") == (7, 11))
    #expect(try run("conditional", flag: 0) == (7, 7))
    #expect(try run("conditional", flag: 1) == (11, 11))
    #expect(try run("rbit") == (11, 11))
    #expect(try run("savearea") == (7, 7))
    #expect(try run("saverun") == (7, 7))
    #expect(try run("branchcall", flag: 0) == (7, 7))
    #expect(try run("branchcall", flag: 1) == (7, 7))
    // The join leaf reads its flag through the pointer in x1.
    var flag: UInt64 = 0
    let flagAddress = withUnsafeMutablePointer(to: &flag) { UInt64(UInt(bitPattern: $0)) }
    #expect(try run("join", flag: flagAddress) == (11, 11))
    flag = 1
    #expect(try run("join", flag: flagAddress) == (7, 7))
}

/// A context that escaped (stored to a global) or a pointer into it handed to
/// a call may be rewritten by any later call; the observed slot is unknown.
/// The context header below an interior pointer stays known, so the return
/// through ResumeParent is still proven.
@Test func escapedAsyncContextsAreNotReadAcrossCallsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: asyncCallFixture) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: asyncCallFixture) }
    func views(_ member: String) throws -> [String] {
        let function = try #require(functions.first { $0.displayName.contains("AsyncCalls.\(member)(") }, "\(member)")
        return [function.renderStructured(), function.renderPseudo()]
    }
    for member in ["globalLeaf", "conditionalLeaf", "interiorLeaf", "rbitLeaf", "joinLeaf"] {
        for text in try views(member) {
            #expect(text.contains("AsyncCalls.observe(?)"), "\(member): \(text)")
            #expect(!text.contains("observe(7)"), "\(member): \(text)")
        }
    }
    for text in try views("interiorLeaf") {
        #expect(text.contains("return AsyncCalls.observe(?)"), Comment(rawValue: text))
    }
    for member in ["readonlyLeaf", "snapshotLeaf"] {
        for text in try views(member) {
            #expect(text.contains("AsyncCalls.observe(7)"), "\(member): \(text)")
        }
    }
    // The register save area is neither part of an escaped local nor an
    // outgoing argument: the saved context stays followed, and so do the
    // slot and the return through ResumeParent.
    for member in ["saveAreaLeaf", "saveRunLeaf", "branchCallLeaf"] {
        for text in try views(member) {
            #expect(text.contains("return AsyncCalls.observe(7)"), "\(member): \(text)")
        }
    }
}

/// At an await-return funclet x22 is the awaited callee's context, whose
/// first word is the caller's own. A call handed that context may rewrite
/// the word, so a later `ldr x8, [x22]` is not the caller's context.
@Test func aCalleeContextHandedToACallLosesItsParentHeader() throws {
    let words: [UInt32] = [
        0xaa1603e0, // mov x0, x22
        0x94000100, // bl +0x400
        0xf94002c8, // ldr x8, [x22]
        0xaa0803e0, // mov x0, x8
        0x94000200, // bl +0x800
        0xd65f03c0, // ret
    ]
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let function = DisassembledFunction(symbol: "_resume", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map { Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                                                branchTarget: $0.branchTarget, detail: $0.detail) },
        source: .address)
    func observed(passing: Bool) -> AbstractValue {
        var instructions = function.instructions
        if !passing {
            // Same body with the context kept out of x0 at the first call.
            instructions[0] = Instruction(address: 0x1000, text: "nop", controlFlow: .sequential,
                                          detail: engine.disassemble(Data([0x1f, 0x20, 0x03, 0xd5]), address: 0x1000).first?.detail)
        }
        let body = function.replacingInstructions(instructions)
        let entry = MethodEntryConvention.asyncFunclet(base: nil, seededRegisters: ["x22": .asyncCalleeContext])
        let analysis = ValueTracer().analyze(body, entry: entry)
        return analysis.callSites[0x1010]?.arguments.first ?? .unknown
    }
    #expect(observed(passing: false) == .asyncContext)
    #expect(observed(passing: true) != .asyncContext)
}
