import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let asyncEdgeFixture = "Fixtures/Sample/libAsyncEdgeRole.dylib"
/// The image the fixture's callees live in: the client imports them.
private let asyncEdgeProvider = "Fixtures/Sample/libAsyncEdgeRoleProvider.dylib"

/// A body decoded at 0x1000 whose calls are unresolved (no target, so no
/// callee summary) and carry `callees` as their names, in order.
private func edgeRoleBody(_ words: [UInt32], callees: [String]) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    var names = callees[...]
    let instructions = decoded.map { insn in
        Instruction(address: insn.address, text: insn.text, controlFlow: insn.controlFlow,
                    branchTarget: insn.controlFlow == .call ? nil : insn.branchTarget, detail: insn.detail,
                    callee: .kept(insn.controlFlow == .call ? names.popFirst() : nil))
    }
    try #require(names.isEmpty)
    return DisassembledFunction(symbol: "_body", demangledName: nil, startAddress: 0x1000,
                                instructions: instructions, source: .address)
}

private let observeName = "AsyncEdge.observe(Swift.Int) -> Swift.Int"
private let asyncEndpointName = "AsyncEdge.endpoint() async -> ()"
/// Synchronous: its only `async` is inside its parameter's type.
private let closureTakerName = "AsyncEdge.plain(() async -> ()) -> Swift.Int"

/// x22 is an input of a call exactly when the callee's own signature is
/// `async`. An `async` in a parameter or a result type, a name with no
/// signature and a runtime entry point leave it callee-saved state.
@Test func onlyAnAsyncSignaturePassesTheContextRegister() {
    func passes(_ callee: String) -> Bool {
        let facts = ValueTracer.CallFacts(callee: callee)
        #expect(facts.takesAsyncContext == facts.passedRegisters.contains(.x(22)), "\(callee)")
        return facts.takesAsyncContext
    }
    #expect(passes(asyncEndpointName))
    #expect(passes("AsyncEdge.load(Swift.Int) async throws -> Swift.Int"))
    #expect(passes("(1) await resume partial function for AsyncEdge.load(Swift.Int) async -> Swift.Int"))
    #expect(!passes(closureTakerName))
    #expect(!passes("AsyncEdge.make() -> () async -> Swift.Int"))
    #expect(!passes("AsyncEdge.send(value: Swift.Int, async: Swift.Bool) -> ()"))
    #expect(!passes(observeName))
    #expect(!passes("swift_task_alloc"))
    #expect(!passes("async_edge_role_c_import"))
    #expect(!passes(""))
    // The argument registers are the same either way.
    #expect(ValueTracer.CallFacts(callee: asyncEndpointName).passedRegisters.dropLast()
        == ValueTracer.CallFacts(callee: closureTakerName).passedRegisters[...])
}

/// `mov x8, #7; str x8, [x22, #16]; bl callee; ldr x0, [x22, #16]; bl
/// observe`. Across an unresolved call the slot of the function's own context
/// stays 7 unless the callee's signature gives it x22.
@Test func anUnresolvedAsyncCalleeMayWriteTheContextInX22() throws {
    let words: [UInt32] = [
        0xd28000e8, // mov x8, #7
        0xf9000ac8, // str x8, [x22, #16]
        0x94000100, // bl +0x400
        0xf9400ac0, // ldr x0, [x22, #16]
        0x94000200, // bl +0x800
        0xd65f03c0, // ret
    ]
    func observed(across callee: String) throws -> AbstractValue {
        let body = try edgeRoleBody(words, callees: [callee, observeName])
        let entry = MethodEntryConvention.asyncFunclet(base: nil, seededRegisters: ["x22": .asyncContext])
        return ValueTracer().analyze(body, entry: entry).callSites[0x1010]?.arguments.first ?? .unknown
    }
    #expect(try observed(across: asyncEndpointName) != .immediate(7))
    #expect(try observed(across: closureTakerName) == .immediate(7))
    #expect(try observed(across: "async_edge_role_c_import") == .immediate(7))
}

/// `sub sp, sp, #64; mov x22, sp; mov x8, #7; str x8, [sp, #16]; bl callee;
/// ldr x0, [sp, #16]; bl observe`. A frame address in x22 reaches only a
/// callee whose signature takes x22: around any other call it is the parked
/// stack pointer of a dynamic allocation, and the local stays known.
@Test func aFrameAddressInX22ReachesOnlyAnAsyncCallee() throws {
    let words: [UInt32] = [
        0xd10103ff, // sub sp, sp, #64
        0x910003f6, // mov x22, sp
        0xd28000e8, // mov x8, #7
        0xf9000be8, // str x8, [sp, #16]
        0x94000100, // bl +0x400
        0xf9400be0, // ldr x0, [sp, #16]
        0x94000200, // bl +0x800
        0x910103ff, // add sp, sp, #64
        0xd65f03c0, // ret
    ]
    func observed(across callee: String) throws -> AbstractValue {
        let body = try edgeRoleBody(words, callees: [callee, observeName])
        return ValueTracer().analyze(body, entry: nil).callSites[0x1018]?.arguments.first ?? .unknown
    }
    #expect(try observed(across: asyncEndpointName) != .immediate(7))
    #expect(try observed(across: closureTakerName) == .immediate(7))
    #expect(try observed(across: "async_edge_role_c_import") == .immediate(7))
}

/// The machine's answer for each fixture body: the imported `endpoint()
/// async` rewrites slot 16 through x22, of an allocated context and of a
/// frame alike; the other three callees write nothing.
@Test func asyncEdgeRoleBodiesRunAsDocumentedIfPresent() throws {
    guard FileManager.default.fileExists(atPath: asyncEdgeFixture),
          FileManager.default.fileExists(atPath: asyncEdgeProvider) else { return }
    let library = try #require(dlopen(asyncEdgeFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Adapter = @convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64
    func run(_ name: String) throws -> (UInt64, UInt64) {
        let adapter = try unsafeBitCast(#require(dlsym(library, "async_edge_role_" + name)), to: Adapter.self)
        var context: [UInt64] = [0, 0, 3, 0]
        let result = context.withUnsafeMutableBufferPointer { adapter($0.baseAddress!) }
        return (result, context[2])
    }
    #expect(try run("direct") == (11, 11))
    for name in ["closure", "untyped", "quiet"] {
        #expect(try run(name) == (7, 7), "\(name)")
    }
    typealias Entry = @convention(c) () -> UInt64
    func call(_ symbol: String) throws -> UInt64 {
        try unsafeBitCast(#require(dlsym(library, symbol)), to: Entry.self)()
    }
    #expect(try call("$s9AsyncEdge9frameLeafSiyF") == 11)
    #expect(try call("$s9AsyncEdge12frameControlSiyF") == 7)
}

/// The context slot, or the frame local, that an imported async callee can
/// write through x22 is not read across the call (native 11, where the
/// stored 7 used to print). The controls keep their 7: a synchronous import
/// that only mentions `async` in a parameter type, an import with no
/// signature, and an async callee whose body is here and never reads x22.
@Test func anImportedAsyncCalleeReachesTheContextInX22IfPresent() async throws {
    guard FileManager.default.fileExists(atPath: asyncEdgeFixture),
          FileManager.default.fileExists(atPath: asyncEdgeProvider) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: asyncEdgeFixture) }
    func views(_ member: String) throws -> [String] {
        let function = try #require(functions.first { $0.displayName.contains("AsyncEdge.\(member)(") }, "\(member)")
        return [function.renderStructured(), function.renderPseudo()]
    }
    for text in try views("directLeaf") {
        #expect(text.contains("AsyncEdge.observe(?)"), Comment(rawValue: text))
        #expect(!text.contains("observe(7)"), Comment(rawValue: text))
    }
    for text in try views("frameLeaf") {
        #expect(text.contains("AsyncEdge.observe("), Comment(rawValue: text))
        #expect(!text.contains("observe(7)"), Comment(rawValue: text))
    }
    for member in ["closureLeaf", "untypedLeaf", "quietLeaf", "frameControl"] {
        for text in try views(member) {
            #expect(text.contains("AsyncEdge.observe(7)"), "\(member): \(text)")
        }
    }
    // The edges are the ones the rule reads: the changed bodies call a
    // callee named async, and the synchronous control's name carries the
    // same word, so a looser reading of the name would have caught it.
    let callees = functions.flatMap(\.instructions).filter { $0.controlFlow == .call }
        .compactMap { DisassembledFunction.calleeName(of: $0) }
    #expect(callees.contains { $0.contains("AsyncEdge.endpoint(") && DisassembledFunction.splitSignature($0)?.isAsync == true },
            Comment(rawValue: callees.joined(separator: "\n")))
    #expect(callees.contains { $0.contains("AsyncEdge.plain(") && $0.contains(" async") },
            Comment(rawValue: callees.joined(separator: "\n")))
}

/// Every entry point decides the same thing for the two bodies the rule
/// changes and for the control beside each.
@Test func theAsyncEdgeRoleHoldsOnEveryEntryPointIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: asyncEdgeFixture),
          FileManager.default.fileExists(atPath: asyncEdgeProvider) else { return }
    let image = try BinaryLoader.load(path: asyncEdgeFixture)
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: asyncEdgeFixture, functionFilter: "Leaf")
    }
    let streamed: [DisassembledFunction] = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    for functions in [filtered, streamed] {
        func structured(_ member: String) throws -> String {
            try #require(functions.first { $0.displayName.contains("AsyncEdge.\(member)(") }, "\(member)").renderStructured()
        }
        #expect(!(try structured("directLeaf")).contains("observe(7)"))
        #expect(!(try structured("frameLeaf")).contains("observe(7)"))
        #expect(try structured("closureLeaf").contains("AsyncEdge.observe(7)"))
        #expect(try structured("quietLeaf").contains("AsyncEdge.observe(7)"))
    }
}
