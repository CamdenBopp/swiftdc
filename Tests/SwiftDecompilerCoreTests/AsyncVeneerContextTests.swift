import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let veneerFixture = "Fixtures/Sample/libAsyncEdgeRole.dylib"
/// The image the fixture's imports live in.
private let veneerProvider = "Fixtures/Sample/libAsyncEdgeRoleProvider.dylib"

/// The import stub every synthetic body here leaves to.
private let stub: UInt64 = 0x2000
private let contextBit: UInt32 = 1 << 22

/// A body decoded at `address`.
private func veneerBody(_ words: [UInt32], at address: UInt64 = 0x1000) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(bytes, address: address)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_body", demangledName: nil, startAddress: address,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

/// `b stub`
private let tailVeneer: [UInt32] = [0x14000400]
/// `str x30, [sp, #-16]!; bl stub; ldr x30, [sp], #16; ret`
private let callWrapper: [UInt32] = [0xf81f0ffe, 0x940003ff, 0xf84107fe, 0xd65f03c0]
/// `mov x22, x1; b stub`
private let rewritingVeneer: [UInt32] = [0xaa0103f6, 0x140003ff]
/// `stp x22, x30, [sp, #-16]!; mov x22, x1; bl stub; ldp x22, x30, [sp], #16; ret`
private let ownContextWrapper: [UInt32] = [0xa9bf7bf6, 0xaa0103f6, 0x940003fe, 0xa8c17bf6, 0xd65f03c0]

/// A body that leaves to an import stub of unknown arity with the x22 it
/// was entered with records that, and claims no context read of its own:
/// whether the import takes x22 is the import's role. A body that writes
/// x22 on every path to the stub hands the import its own value, and a
/// target that is no stub, or one of known arity, is not such an edge.
@Test func aBodyReachingAnImportWithItsCallersX22WaitsForTheImportsRole() throws {
    func summary(_ words: [UInt32], stub isStub: Bool = true, arity: Int? = nil) throws -> CalleeRegisterSummary {
        try #require(CalleeRegisterSummary.of(
            veneerBody(words), calleeArity: { _ in arity }, isImportStub: { $0 == stub && isStub }))
    }
    for words in [tailVeneer, callWrapper] {
        let waiting = try summary(words)
        #expect(waiting.handsContextToImport)
        #expect(!waiting.readsContextRegister)
        #expect(waiting.mayReadRegisters & contextBit == 0)
        #expect(waiting.callees == [stub])
    }
    #expect(try !summary(rewritingVeneer).handsContextToImport)
    #expect(try !summary(ownContextWrapper).handsContextToImport)
    #expect(try !summary(ownContextWrapper).readsContextRegister)
    #expect(try !summary(tailVeneer, stub: false).handsContextToImport)
    #expect(try !summary(tailVeneer, arity: 1).handsContextToImport)
}

/// The closure resolves the edge with the import's role. Through an import
/// that takes its async context in x22 the body reads the context register,
/// and so does a caller that reaches the body with its own x22; a caller
/// that wrote x22 first does not. Through any other import nobody does.
@Test func aVeneerToAnAsyncImportReadsItsCallersContext() throws {
    // str x30, [sp, #-16]!; bl 0x1000; ldr x30, [sp], #16; ret
    let caller = try veneerBody([0xf81f0ffe, 0x940001ff, 0xf84107fe, 0xd65f03c0], at: 0x800)
    // stp x22, x30, [sp, #-16]!; mov x22, x1; bl 0x1000; ldp x22, x30, [sp], #16; ret
    let rewriting = try veneerBody([0xa9bf7bf6, 0xaa0103f6, 0x940001be, 0xa8c17bf6, 0xd65f03c0], at: 0x900)
    func closed(_ words: [UInt32], role: ((UInt64) -> Bool)?) throws -> [UInt64: CalleeRegisterSummary] {
        var summaries: [UInt64: CalleeRegisterSummary] = [:]
        summaries[0x1000] = try #require(CalleeRegisterSummary.of(veneerBody(words), isImportStub: { $0 == stub }))
        for function in [caller, rewriting] {
            summaries[function.startAddress] = try #require(CalleeRegisterSummary.of(
                function, isFunction: { $0 == 0x1000 }, isImportStub: { $0 == stub }))
        }
        try #require(summaries[0x800]?.pendingReads.first.map { $0.unwritten & contextBit != 0 } == true)
        try #require(summaries[0x900]?.pendingReads.first.map { $0.unwritten & contextBit == 0 } == true)
        if let role {
            CalleeRegisterSummary.closeOverReads(&summaries, takesAsyncContext: role)
        } else {
            CalleeRegisterSummary.closeOverReads(&summaries)
        }
        return summaries
    }
    for words in [tailVeneer, callWrapper] {
        let async = try closed(words, role: { $0 == stub })
        #expect(async[0x1000]?.readsContextRegister == true)
        #expect((async[0x1000]?.mayReadRegisters ?? 0) & contextBit != 0)
        #expect(async[0x800]?.readsContextRegister == true)
        #expect(async[0x900]?.readsContextRegister == false)
        // Resolved, as the pending calls are.
        #expect(async.values.allSatisfy { !$0.handsContextToImport && $0.pendingReads.isEmpty })

        // A synchronous import, a role that belongs to another stub, and
        // no role at all.
        let otherRoles: [((UInt64) -> Bool)?] = [{ _ in false }, { $0 == 0x2100 }, nil]
        for role in otherRoles {
            let plain = try closed(words, role: role)
            #expect(plain[0x1000]?.readsContextRegister == false)
            #expect((plain[0x1000]?.mayReadRegisters ?? contextBit) & contextBit == 0)
            #expect(plain[0x800]?.readsContextRegister == false)
            #expect(plain.values.allSatisfy { !$0.handsContextToImport })
        }
    }
    // A body that wrote x22 on the way to the same async import handed it
    // nothing of its caller's.
    for words in [rewritingVeneer, ownContextWrapper] {
        let own = try closed(words, role: { $0 == stub })
        #expect(own[0x1000]?.readsContextRegister == false)
        #expect(own[0x800]?.readsContextRegister == false)
    }
}

/// A summary that gives up its claims about callee-saved registers still
/// says its body reached an import with the caller's x22.
@Test func aSummaryClaimingNothingKeepsTheEdgeToAnImport() throws {
    let summary = try #require(CalleeRegisterSummary.of(veneerBody(tailVeneer), isImportStub: { $0 == stub }))
    let kept = summary.claimingNothing()
    #expect(kept.handsContextToImport)
    #expect(kept.callees == [stub])
    var summaries = [UInt64(0x1000): kept]
    CalleeRegisterSummary.closeOverReads(&summaries, takesAsyncContext: { $0 == stub })
    #expect(summaries[0x1000]?.readsContextRegister == true)
}

/// The role is the bound function's own `async` effect, nothing looser.
@Test func anImportsRoleIsItsOwnAsyncEffect() {
    #expect(CalleeRegisterSummary.isAsyncSignature("AsyncEdge.endpoint() async -> ()"))
    #expect(CalleeRegisterSummary.isAsyncSignature("AsyncEdge.load(Swift.Int) async throws -> Swift.Int"))
    #expect(!CalleeRegisterSummary.isAsyncSignature("AsyncEdge.plain(() async -> ()) -> Swift.Int"))
    #expect(!CalleeRegisterSummary.isAsyncSignature("AsyncEdge.make() -> () async -> Swift.Int"))
    #expect(!CalleeRegisterSummary.isAsyncSignature("async_edge_role_c_import"))
    #expect(!CalleeRegisterSummary.isAsyncSignature("swift_task_alloc"))
    #expect(!CalleeRegisterSummary.isAsyncSignature(nil))
}

/// The machine's answer for each veneer body: the imported `endpoint()
/// async` rewrites slot 16 of the caller's context, or of the caller's
/// frame, through a veneer or a wrapper that leaves x22 alone. A veneer to
/// the synchronous import writes nothing, and the wrapper with a context of
/// its own has the import write that one.
@Test func asyncVeneerBodiesRunAsDocumentedIfPresent() throws {
    guard FileManager.default.fileExists(atPath: veneerFixture),
          FileManager.default.fileExists(atPath: veneerProvider) else { return }
    let library = try #require(dlopen(veneerFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Adapter = @convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64
    func run(_ name: String) throws -> (UInt64, UInt64) {
        let adapter = try unsafeBitCast(#require(dlsym(library, "async_edge_role_" + name)), to: Adapter.self)
        var context: [UInt64] = [0, 0, 3, 0]
        let result = context.withUnsafeMutableBufferPointer { adapter($0.baseAddress!) }
        return (result, context[2])
    }
    for name in ["veneer", "wrapper"] {
        #expect(try run(name) == (11, 11), "\(name)")
    }
    for name in ["plainveneer", "owncontext"] {
        #expect(try run(name) == (7, 7), "\(name)")
    }
    typealias Entry = @convention(c) () -> UInt64
    let frame = try unsafeBitCast(#require(dlsym(library, "$s9AsyncEdge15frameVeneerLeafSiyF")), to: Entry.self)
    #expect(frame() == 11)
}

/// The bodies an async import writes through a veneer, and the controls
/// that keep their stored 7.
private let reachedThroughVeneer = ["veneerLeaf", "wrapperLeaf", "frameVeneerLeaf"]
private let keptAcrossVeneer = ["plainVeneerLeaf", "ownContextLeaf"]

/// A context slot, or a frame local, that an imported async function can
/// write through x22 is not read across a call to the in-image body that
/// hands it that x22 (native 11, where the stored 7 printed). The controls
/// keep their 7: the same veneer to a synchronous import, and a wrapper
/// that gives the async import a context of its own. Every way in decides
/// the same: the whole image, a filter, the streamed image and one function
/// at a time.
@Test func aCallersContextIsNotKeptAcrossAVeneerToAnAsyncImportIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: veneerFixture),
          FileManager.default.fileExists(atPath: veneerProvider) else { return }
    let image = try BinaryLoader.load(path: veneerFixture)
    let listing = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: veneerFixture)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: veneerFixture, functionFilter: "Leaf")
    }
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler(preset: .default).analyzeEachFunction(
            at: Set(listing.map(\.startAddress)), in: image, transform: { $0 })
    }
    for (way, functions) in [("listing", listing), ("filtered", filtered), ("streamed", streamed), ("each", Array(each.values))] {
        func views(_ member: String) throws -> [String] {
            let function = try #require(
                functions.first { $0.displayName.contains("AsyncEdge.\(member)(") }, "\(way): \(member)")
            return [function.renderStructured(), function.renderPseudo()]
        }
        for member in reachedThroughVeneer {
            for text in try views(member) {
                #expect(text.contains("AsyncEdge.observe("), "\(way): \(member): \(text)")
                #expect(!text.contains("observe(7)"), "\(way): \(member): \(text)")
            }
        }
        // `analyzeEachFunction` prints `observe(?)` for both controls with
        // or without the role (measured with the role turned off at its
        // call site): it forgets a context slot across any call from an
        // async body into the image. That is a decline, so the controls
        // are held on the other three ways and only kept from the false
        // value on this one.
        for member in keptAcrossVeneer {
            for text in try views(member) {
                if way == "each" {
                    #expect(text.contains("AsyncEdge.observe("), "\(way): \(member): \(text)")
                } else {
                    #expect(text.contains("AsyncEdge.observe(7)"), "\(way): \(member): \(text)")
                }
            }
        }
    }
}
