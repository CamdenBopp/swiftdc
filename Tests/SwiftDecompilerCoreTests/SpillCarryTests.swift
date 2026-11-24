import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A general callee-saved register a body stores is left out of the
/// clobbers carried past its direct callers: the store may be a save whose
/// reload the analysis could not prove. That holds only when something can
/// load the register back. A body that stores x19, overwrites it and never
/// reloads it keeps no convention that preserves x19, and reached through a
/// second body it still read as preserved: a caller keeping arg0 in x19
/// across `spill_relay` rendered `return arg0`, where the machine returns
/// arg1. spill_carry.s states each body's true behaviour.
private let spillCarryPath = "Fixtures/Sample/libSpillCarry.dylib"

private func spillCarryName(_ function: String) -> String {
    "SpillCarry.\(function)(Swift.Int, Swift.Int) -> Swift.Int"
}

private func statements(of function: DisassembledFunction) -> [String] {
    function.renderPseudo().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
}

/// Every view path of the image: the whole-image array, a filtered run and
/// the streaming one.
private func spillCarryViews() async throws -> [(view: String, functions: [DisassembledFunction])]? {
    guard FileManager.default.fileExists(atPath: spillCarryPath) else { return nil }
    let full = try await withStableDependencies { try await Disassembler().disassemble(path: spillCarryPath) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: spillCarryPath, functionFilter: "SpillCarry")
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: spillCarryPath)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    return [("array", full), ("filtered", filtered), ("streaming", streamed)]
}

/// The summaries of every body in the image, closed over calls, by symbol.
private func spillCarrySummaries() throws -> ((String) throws -> CalleeRegisterSummary)? {
    guard FileManager.default.fileExists(atPath: spillCarryPath) else { return nil }
    let image = try BinaryLoader.load(path: spillCarryPath)
    let disassembler = Disassembler()
    let boundaries = disassembler.functionStarts(of: image).sorted()
    let starts = Set(boundaries)
    var bodies: [UInt64: DisassembledFunction] = [:]
    for start in boundaries {
        let instructions = disassembler.decodeFunction(at: start, boundaries: boundaries, in: image)
        guard !instructions.isEmpty else { continue }
        bodies[start] = DisassembledFunction(symbol: "body", demangledName: nil,
            startAddress: start, instructions: instructions, source: .address)
    }
    var summaries = try bodies.mapValues { try #require(CalleeRegisterSummary.of($0, isFunction: starts.contains)) }
    CalleeRegisterSummary.closeOverCalls(&summaries, rebuildingEntryRoles: false) { address, effects, reads, reuse in
        guard let body = bodies[address] else { return nil }
        return CalleeRegisterSummary.recomputingPreservation(body, retainingReadsFrom: reads,
            reusingPreservation: reuse, rebuildingEntryRoles: false,
            calleeEffects: effects, isFunction: starts.contains)
    }
    let closed = summaries
    return { name in
        let entry = UInt64(try #require(image.symbols.first { $0.name == name }, "no \(name)").offset)
        return try #require(closed[entry], "no summary for \(name)")
    }
}

/// What the machine returns: the oracle the renders below are held to.
@Test func spilledRegistersRunAsTheFixtureSaysIfPresent() throws {
    guard FileManager.default.fileExists(atPath: spillCarryPath) else { return }
    let library = try #require(dlopen(spillCarryPath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Caller = @convention(c) (Int, Int) -> Int
    func native(_ name: String) throws -> Int {
        let symbol = try #require(dlsym(library, "$s10SpillCarry\(name)yS2i_SitF"), "no \(name)")
        return unsafeBitCast(symbol, to: Caller.self)(1, 2)
    }
    #expect(try native("6direct") == 2)
    #expect(try native("7relayed") == 2)
    #expect(try native("6tailed") == 2)
    #expect(try native("6parked") == 2)
    #expect(try native("5fixed") == 11)
    #expect(try native("5saved") == 1)
    #expect(try native("8reloaded") == 1)
    #expect(try native("6handed") == 1)
    #expect(try native("8restored") == 1)
    #expect(try native("12nearReloaded") == 1)
    #expect(try native("10nearHanded") == 1)
    #expect(try native("12nearRestored") == 1)
}

/// A register stored and never loaded back is not handed back, one call
/// away or two: through a framed body, a tail branch, and when the store
/// writes the new value.
@Test func aSpilledRegisterNeverReloadedIsClobberedThroughARelayIfPresent() async throws {
    guard let views = try await spillCarryViews() else { return }
    for (view, functions) in views {
        for name in ["direct", "relayed", "tailed", "parked", "fixed"] {
            let function = try #require(functions.first { $0.displayName == spillCarryName(name) }, "\(view): no \(name)")
            let lines = statements(of: function)
            #expect(lines.contains("return ?"), "\(view) \(name): \(lines)")
            // The value x19 held before the call is not the result.
            #expect(!lines.contains("return arg0") && !lines.contains("return 7"), "\(view) \(name): \(lines)")
        }
    }
}

/// The controls: a register some instruction or callee can load back keeps
/// its place outside the carried clobbers, so a body two calls up still
/// reads it as preserved. Each of these returns arg0 on the machine.
@Test func aStoredRegisterSomethingReloadsIsStillPreservedThroughARelayIfPresent() async throws {
    guard let views = try await spillCarryViews() else { return }
    for (view, functions) in views {
        for name in ["saved", "reloaded", "handed", "restored"] {
            let function = try #require(functions.first { $0.displayName == spillCarryName(name) }, "\(view): no \(name)")
            let lines = statements(of: function)
            #expect(lines.contains("return arg0"), "\(view) \(name): \(lines)")
        }
        // Not vacuous: one call away the same bodies are not proved to
        // restore x19, so the controls above rest on the carry rule alone.
        for name in ["nearReloaded", "nearHanded", "nearRestored"] {
            let function = try #require(functions.first { $0.displayName == spillCarryName(name) }, "\(view): no \(name)")
            let lines = statements(of: function)
            #expect(lines.contains("return ?"), "\(view) \(name): \(lines)")
        }
    }
}

/// The same facts where they are decided. A spill with no reload carries;
/// each way a stored register can come back keeps it from carrying, and
/// each control's body is one the analysis cannot prove restores it.
@Test func carriedClobbersNeedAStoreWithNoReloadIfPresent() throws {
    guard let summary = try spillCarrySummaries() else { return }
    // Stored, overwritten, never loaded: clobbered and carried.
    for leaf in ["_spill_leaf", "_park_leaf", "_fixed_leaf"] {
        let facts = try summary(leaf)
        #expect(facts.clobberedCalleeSaved == ["x19"], "\(leaf)")
        #expect(facts.definitelyClobbered == ["x19"], "\(leaf)")
    }
    for relay in ["_spill_relay", "_spill_tail", "_park_relay", "_fixed_relay"] {
        #expect(try summary(relay).clobberedCalleeSaved.contains("x19"), "\(relay)")
    }
    // A reload the analysis proves: nothing is clobbered.
    #expect(try summary("_saved_leaf").clobberedCalleeSaved.isEmpty)
    // Its own instruction reloads x19 from a slot the analysis cannot prove
    // intact: clobbered for a direct caller, not carried.
    let veiled = try summary("_veiled_leaf")
    #expect(veiled.clobberedCalleeSaved.contains("x19"))
    #expect(!veiled.definitelyClobbered.contains("x19"))
    // A callee's clobber that is a reload of this body's saves.
    let handed = try summary("_handed_helper")
    #expect(handed.clobberedCalleeSaved.isSuperset(of: ["x19", "x20"]))
    #expect(handed.definitelyClobbered.isDisjoint(with: ["x19", "x20"]))
    // A callee's proven reload of a slot this body may have overwritten.
    #expect(try summary("_clean_reload").restoredFrom == ["x19": 0x18, "x20": 0x10])
    let escaped = try summary("_escaped_helper")
    #expect(escaped.clobberedCalleeSaved.isSuperset(of: ["x19", "x20"]))
    #expect(escaped.definitelyClobbered.isDisjoint(with: ["x19", "x20"]))
    for relay in ["_saved_relay", "_veiled_relay", "_handed_relay", "_escaped_relay"] {
        #expect(try !summary(relay).clobberedCalleeSaved.contains("x19"), "\(relay)")
    }
}
