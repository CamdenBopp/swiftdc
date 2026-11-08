import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Decode little-endian words at `address` into analysed-shape instructions.
private func decode(_ words: [UInt32], at address: UInt64) throws -> [Instruction] {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: address)
    try #require(decoded.count == words.count)
    return decoded.map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
}

private func fragment(_ words: [UInt32], at address: UInt64 = 0x2000) throws -> OutlinedFragment {
    try #require(OutlinedFragment(start: address, instructions: try decode(words, at: address)))
}

private func site(call: Bool, at address: UInt64 = 0x1000, to target: UInt64 = 0x2000) throws -> Instruction {
    let offset = UInt32(truncatingIfNeeded: Int64(target) - Int64(address)) >> 2 & 0x3FF_FFFF
    return try decode([(call ? 0x9400_0000 : 0x1400_0000) | offset], at: address)[0]
}

private func plan(_ fragment: OutlinedFragment, call: Bool) throws -> OutlinedFragment.Outcome {
    fragment.plan(site: try site(call: call), reachedByCall: call, annotated: fragment,
                  name: "OUTLINED_FUNCTION_0", isFragment: { _ in false })
}

private func declineReason(_ outcome: OutlinedFragment.Outcome) -> String? {
    if case .declined(let reason) = outcome { reason } else { nil }
}

private func inlinedPlan(_ outcome: OutlinedFragment.Outcome) -> OutlinedFragment.Plan? {
    if case .inlined(let plan) = outcome { plan } else { nil }
}

/// The hashValue fragments of the -Osize Reconstruction fixture, and the
/// shapes each kind of site takes.
@Test func outlinedFragmentSitesBecomeWhatTheFragmentDoesThere() throws {
    // OUTLINED_FUNCTION_36: add x8, sp, #8; mov x0, #0; b Hasher.init
    let seed = try fragment([0x9100_23E8, 0xD280_0000, 0x1400_0100])
    let call = try #require(inlinedPlan(try plan(seed, call: true)))
    #expect(call.kind == "call")
    #expect(call.visible.controlFlow == .call)
    #expect(call.visible.branchTarget == 0x2408)
    #expect(call.visible.address == 0x1000)
    #expect(call.prefix.map(\.address) == [0x1000, 0x1000])
    #expect(call.visible.inlinedFragment == Instruction.InlinedFragment(address: 0x2000, reachedByCall: true))
    // Reached by `b`, the same fragment is a tail call.
    let tail = try #require(inlinedPlan(try plan(seed, call: false)))
    #expect(tail.kind == "tail-call")
    #expect(tail.visible.controlFlow == .branch)

    // OUTLINED_FUNCTION_9: ldp x20, x19, [sp, #0x50]; add sp, sp, #0x70; ret
    let epilogue = try fragment([0xA945_4FF4, 0x9101_C3FF, 0xD65F_03C0])
    let ret = try #require(inlinedPlan(try plan(epilogue, call: false)))
    #expect(ret.kind == "return")
    #expect(ret.visible.controlFlow == .return)
    #expect(ret.prefixWrites.contains("x20") && ret.prefixWrites.contains("sp"))
    // Reached by `bl` it would load and move sp for the caller mid-body.
    #expect(declineReason(try plan(epilogue, call: true)) == "memory")

    // OUTLINED_FUNCTION_14: str x0, [x20]; ret — the store itself.
    let store = try #require(inlinedPlan(try plan(try fragment([0xF900_0280, 0xD65F_03C0]), call: true)))
    #expect(store.kind == "store")
    #expect(store.prefix.isEmpty)
    #expect(store.visible.text.hasPrefix("str"))
}

/// What a site cannot carry exactly stays a call.
@Test func anOutlinedFragmentTheModelCannotCarryStaysACall() throws {
    // A store before the call: no pass outside the tracer would see it.
    #expect(declineReason(try plan(try fragment([0xF900_0280, 0x1400_0100]), call: true)) == "memory")
    // A store before a value: `str x0, [x20]; mov x0, x1; ret`.
    #expect(declineReason(try plan(try fragment([0xF900_0280, 0xAA01_03E0, 0xD65F_03C0]), call: true)) == "memory")
    // An epilogue that sets the result: `mov x0, x1; ret` by `b`.
    #expect(declineReason(try plan(try fragment([0xAA01_03E0, 0xD65F_03C0]), call: false)) == "result-register")
    // x21, Swift's error register: `mov x21, #0; b …`.
    #expect(declineReason(try plan(try fragment([0xD280_0015, 0x1400_0100]), call: true)) == "error-or-context-register")
    // A callee-saved register written ahead of a value: `mov x29, sp; mov x1, x0; ret`.
    #expect(declineReason(try plan(try fragment([0x9100_03FD, 0xAA00_03E1, 0xD65F_03C0]), call: true)) == "callee-saved")
    // sp moved for a caller that goes on: `add sp, sp, #0x30; ret`, `add sp, sp, #16; b …`.
    #expect(declineReason(try plan(try fragment([0x9100_C3FF, 0xD65F_03C0]), call: true)) == "stack-pointer")
    #expect(declineReason(try plan(try fragment([0x9100_43FF, 0x1400_0100]), call: true)) == "stack-pointer")
    // The return address read as a value: `mov x0, x30; b …`.
    #expect(declineReason(try plan(try fragment([0xAA1E_03E0, 0x1400_0100]), call: true)) == "link-register")
    // A float argument set for the call: `fmov d0, #1.0; b …`.
    #expect(declineReason(try plan(try fragment([0x1E6E_1000, 0x1400_0100]), call: true)) == "float-argument")
    // A bare `ret` reached by `bl` does nothing a site can be.
    #expect(declineReason(try plan(try fragment([0xD65F_03C0]), call: true)) == "empty")
    // A fragment that tail-calls another fragment.
    let chained = try fragment([0xD280_0000, 0x1400_0100])
    #expect(declineReason(chained.plan(site: try site(call: true), reachedByCall: true, annotated: chained,
                                       name: "f", isFragment: { _ in true })) == "chained")
    // A body with a branch inside, or one past the bound, is no fragment.
    #expect(OutlinedFragment(start: 0x2000, instructions: try decode([0xB400_0040, 0xD65F_03C0], at: 0x2000)) == nil)
    #expect(OutlinedFragment(start: 0x2000, instructions: try decode(
        Array(repeating: 0xD280_0000, count: OutlinedFragment.maximumBody + 1) + [0xD65F_03C0], at: 0x2000)) == nil)
}

/// `ReconError.hashValue` at -Osize calls three fragments: `add x8, sp, #8;
/// mov x0, #0; b Hasher.init`, `add x20, sp, #8; b Hasher._finalize`, and
/// the epilogue `ldp x20, x19, [sp, #0x50]; add sp, sp, #0x70; ret` it
/// tail-branches to. It read `OUTLINED_FUNCTION_36(); Hasher._combine(0);
/// OUTLINED_FUNCTION_9(OUTLINED_FUNCTION_35())`; the source is
/// `Hasher(_seed: 0)`, `_combine`, `_finalize`. Stripped, the fragments are
/// nameless `sub_…` and only their bodies say what they are.
@Test func outlinedFragmentsReadAsTheCodeTheyReplaceIfPresent() async throws {
    for path in ["Fixtures/Sample/libReconstruction.osize.dylib", "Fixtures/Sample/libReconstruction.osize.stripped.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: path)
        }
        let getter = try #require(functions.first { $0.displayName.hasPrefix("Reconstruction.ReconError.hashValue.getter") })
        let rendered = getter.renderStructured()
        #expect(rendered.contains("Swift.Hasher.init(_seed:)(0)\n"), "\(path)\n\(rendered)")
        #expect(rendered.contains("Swift.Hasher._combine(self: local_68, 0)\n"), "\(path)\n\(rendered)")
        #expect(rendered.contains("return Swift.Hasher._finalize(self: local_68)\n"), "\(path)\n\(rendered)")
        #expect(!rendered.contains("OUTLINED_FUNCTION") && !rendered.contains("sub_"), "\(path)\n\(rendered)")
    }
}

/// In the binary the sites are still a `bl` and a `b` to the fragments:
/// `xrefs` lists them as callers, and the listing says what was inlined.
@Test func anInlinedSiteStaysACallToItsFragmentInTheCallGraphIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.osize.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let getter = try #require(functions.first { $0.displayName.hasPrefix("Reconstruction.ReconError.hashValue.getter") })
    let seed = try #require(functions.first { $0.symbol == "_OUTLINED_FUNCTION_36" }).startAddress
    let epilogue = try #require(functions.first { $0.symbol == "_OUTLINED_FUNCTION_9" }).startAddress
    for graph in [CallGraph(functions: functions), CallGraph(functions: functions.map(CallGraph.sites(of:)))] {
        let edges = graph.edges.filter { $0.caller == getter.startAddress }
        #expect(edges.contains { $0.callee == seed && !$0.isTailCall }, "\(edges)")
        #expect(edges.contains { $0.callee == epilogue && $0.isTailCall }, "\(edges)")
    }
    // A site that became the fragment's last instruction (`bl
    // OUTLINED_FUNCTION_7`, a `csinc` now) keeps its edge in the slimmed
    // per-function sites `xrefs` streams.
    let width = try #require(functions.first { $0.symbol == "_OUTLINED_FUNCTION_7" }).startAddress
    let store = try #require(functions.first { $0.displayName.hasPrefix("storeEnumTagSinglePayload value witness for Reconstruction.Direction") })
    #expect(store.instructions.contains { $0.inlinedFragment?.address == width && $0.controlFlow != .call })
    #expect(CallGraph(functions: [CallGraph.sites(of: store)]).edges.contains { $0.callee == width })
    let exit = try #require(getter.instructions.last)
    #expect(exit.controlFlow == .return)
    #expect(exit.annotation?.contains("inlined b OUTLINED_FUNCTION_9") == true, "\(exit.annotation ?? "")")
}

/// A pass that reads instructions rather than the tracer's states learns
/// from `clobbers(atCall:)` that `bl OUTLINED_FUNCTION_35`, now `bl
/// Hasher._finalize`, rewrote x20 before the call.
@Test func anInlinedPrefixsWritesCountAsTheCallsClobbers() throws {
    let prefix = try decode([0x9100_23F4], at: 0x1000)  // add x20, sp, #8
    let call = try site(call: true)
    var tracer = ValueTracer()
    #expect(!tracer.clobbers(atCall: call).contains("x20"))
    tracer.inlinedPrefixes[call.address] = prefix
    #expect(tracer.clobbers(atCall: call).contains("x20"))
}

/// `bl OUTLINED_FUNCTION_0` renders as `bl swift_retain`, its `add x29,
/// sp, #8` run by the tracer alone. The saved-register proof that follows
/// -Onone's x21 spill through x29 reads the instructions, and with x29
/// taken as unchanged it proved `thing`'s reload of the spill the entry's
/// zero: a normal return the binary does not make (`outlined_frame.s`).
@Test func anInlinedFragmentThatMovesTheFramePointerProvesNoReturnIfPresent() async throws {
    let path = "Fixtures/Sample/libOutlinedFrame.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }).renderStructured()
    }
    let thing = try render("Test.thing()")
    #expect(thing.contains(DisassembledFunction.unresolvedSwiftExitStatement), "\(thing)")
    #expect(!thing.contains("    return\n"), "\(thing)")
    // The control's fragment leaves x29 alone: its spill comes back.
    let control = try render("Test.control()")
    #expect(control.contains("    return\n"), "\(control)")
    let site = try #require(functions.first { $0.displayName.hasPrefix("Test.thing()") }?
        .instructions.first { $0.inlinedFragment != nil })
    #expect(site.controlFlow == .call)
}

/// An async throwing function's error is x20 at its return, and a fragment
/// can rewrite it (`add x20, sp, #8; b swift_retain`) with the site reading
/// `bl swift_retain`. `cleared`'s `mov x20, #0` proves nothing past the
/// fragment, and `relay`'s `cbz x20` guards no rethrow past it: read as a
/// call that keeps x20, they rendered `return` and `throw`.
@Test func anInlinedFragmentThatRewritesTheAsyncErrorRegisterProvesNoExitIfPresent() async throws {
    let path = "Fixtures/Sample/libOutlinedFrame.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }).renderStructured()
    }
    let cleared = try render("Test.cleared()")
    #expect(cleared.contains(DisassembledFunction.unresolvedSwiftExitStatement), "\(cleared)")
    #expect(!cleared.contains("    return\n"), "\(cleared)")
    let relay = try render("Test.relay()")
    #expect(relay.contains(DisassembledFunction.unresolvedSwiftExitStatement), "\(relay)")
    #expect(!relay.contains("throw "), "\(relay)")
}

/// A stripped binary keeps no `OUTLINED_FUNCTION_n` name: the body must do
/// what no function does on entry.
@Test func onlyABodyThatBreaksTheCallingConventionIsAnUnnamedFragment() throws {
    // add x8, sp, #8; …: the caller's frame.
    #expect(try fragment([0x9100_23E8, 0xD280_0000, 0x1400_0100]).breaksCallingConvention)
    // add x20, sp, #8; b …
    #expect(try fragment([0x9100_23F4, 0x1400_0100]).breaksCallingConvention)
    // mov x19, x0; ret: a callee-saved register written, never saved.
    #expect(try fragment([0xAA00_03F3, 0xD65F_03C0]).breaksCallingConvention)
    // mov x0, x9; ret: x9 has no incoming value.
    #expect(try fragment([0xAA09_03E0, 0xD65F_03C0]).breaksCallingConvention)
    // Ordinary leaves: str x0, [x20]; ret. mov x0, x1; ret. mov x2, #0x21; b …
    #expect(try !fragment([0xF900_0280, 0xD65F_03C0]).breaksCallingConvention)
    #expect(try !fragment([0xAA01_03E0, 0xD65F_03C0]).breaksCallingConvention)
    #expect(try !fragment([0xD280_0422, 0x1400_0100]).breaksCallingConvention)
    // A frame of its own: sub sp, sp, #16; add x0, sp, #8; add sp, sp, #16; ret.
    #expect(try !fragment([0xD100_43FF, 0x9100_23E0, 0x9100_43FF, 0xD65F_03C0]).breaksCallingConvention)
}
