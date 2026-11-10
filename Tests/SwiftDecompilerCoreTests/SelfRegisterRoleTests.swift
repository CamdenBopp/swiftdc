import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let selfRegisterRoleFixture = "Fixtures/Sample/libSelfRegisterRole.dylib"

@Test func nativeSelfRegisterRolesHaveAnABIOracleIfPresent() throws {
    guard FileManager.default.fileExists(atPath: selfRegisterRoleFixture) else { return }
    let library = try #require(dlopen(selfRegisterRoleFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Entry = @convention(c) () -> Int
    // The Swift declarations independently choose the ABI: i64 value self
    // for read, ptr swiftself for mutatingRead and forwardingRead. Each
    // assembly wrapper agrees with its compiler-generated C entry point.
    for (name, expected) in [("selfrole_native", 7), ("$s8SelfRole7wrapperSiyF", 7),
                             ("selfrole_context", 9), ("$s8SelfRole14contextWrapperSiyF", 9),
                             ("selfrole_forward", 11), ("$s8SelfRole17forwardingWrapperSiyF", 11),
                             ("selfrole_unused", 42), ("$s8SelfRole13unusedWrapperSiyF", 42)] {
        let symbol = try #require(dlsym(library, name))
        #expect(unsafeBitCast(symbol, to: Entry.self)() == expected, Comment(rawValue: name))
    }
}

@Test func mayReadSavedX20IsNotAContextSelfArgumentIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: selfRegisterRoleFixture) else { return }
    let full = try await withStableDependencies {
        try await Disassembler().disassemble(path: selfRegisterRoleFixture)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: selfRegisterRoleFixture, functionFilter: "Wrapper")
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: selfRegisterRoleFixture)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    for functions in [full, filtered, streamed] {
        let value = try #require(functions.first { $0.displayName.hasPrefix("SelfRole.wrapper(") })
        for text in [value.renderPseudo(), value.renderStructured()] {
            // The value self is x0's 7 (dev renders value-self words as
            // `self:`); no saved x20 stands in for it.
            #expect(text.contains("return SelfRole.Tiny.read(self: 7)"), Comment(rawValue: text))
            #expect(!text.contains("self: ?") && !text.contains("x20"), Comment(rawValue: text))
        }
        let unused = try #require(functions.first { $0.displayName.hasPrefix("SelfRole.unusedWrapper(") })
        for text in [unused.renderPseudo(), unused.renderStructured()] {
            #expect(text.contains("return SelfRole.Tiny.unusedContext()"), Comment(rawValue: text))
            #expect(!text.contains("29"), Comment(rawValue: text))
        }
        for (caller, callee) in [("contextWrapper", "mutatingRead"), ("forwardingWrapper", "forwardingRead")] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("SelfRole.\(caller)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("return SelfRole.Tiny.\(callee)(self: local_"), Comment(rawValue: text))
            }
        }
    }
}

@Test func savedEntrySelfStillHasAMAYReadEffectIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: selfRegisterRoleFixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: selfRegisterRoleFixture, functionFilter: "SelfRole.Tiny.read")
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("SelfRole.Tiny.read(") })
    // The standalone summary has no body/effect for its callee. A possible
    // frame read must stay conservative even though it proves no x20 self ABI.
    let summary = try #require(CalleeRegisterSummary.of(function))
    #expect(summary.readsSelfRegister)
}

// Analysis-only words independently assembled and read with llvm-objdump.
// These check proof provenance; they are not additional native ABI claims.
private func roleBody(_ words: [UInt32], at address: UInt64) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: address)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "role", demangledName: nil, startAddress: address,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

@Test func entryRegisterRolesRequireKnownUses() throws {
    // ldr x0,[x20];ret
    let direct = try #require(CalleeRegisterSummary.of(try roleBody([0xf9400280, 0xd65f03c0], at: 0x1000)))
    #expect(direct.provenEntryRegisterReads & (1 << 20) != 0)
    // Save x20, overwrite it, reload the intact save into x9, then use x9.
    let spill = try #require(CalleeRegisterSummary.of(try roleBody([
        0xd10083ff, 0xf90003f4, 0xaa0103f4, 0xf94003e9, 0xf9400120, 0x910083ff, 0xd65f03c0,
    ], at: 0x1008)))
    #expect(spill.provenEntryRegisterReads & (1 << 20) != 0)
    // Escape a saved x20, overwrite x20, call, then load through unknown x0
    // and x9. A possible overlap is a MAY read, never a known entry value.
    let unplaced = try #require(CalleeRegisterSummary.of(try roleBody([
        0xd10083ff, 0xf90003f4, 0xaa0103f4, 0x910003e0, 0x940003f3,
        0xf9400009, 0xf9400120, 0x910083ff, 0xd65f03c0,
    ], at: 0x1024), isFunction: { $0 == 0x2000 }))
    #expect(unplaced.readsSelfRegister)
    #expect(unplaced.provenEntryRegisterReads & (1 << 20) == 0)
}

@Test func entryRegisterRoleProofIsReplacedAtCFGJoins() throws {
    // One predecessor keeps entry x20; the other overwrites it. The load
    // after their join has no MUST origin. Exercise both visit orders.
    for (address, words) in [
        (UInt64(0x1048), [UInt32(0xb4000060), 0xaa0103f4, 0x14000002, 0xd503201f, 0xf9400280, 0xd65f03c0]),
        (UInt64(0x1060), [UInt32(0xb4000060), 0xd503201f, 0x14000002, 0xaa0103f4, 0xf9400280, 0xd65f03c0]),
    ] {
        let summary = try #require(CalleeRegisterSummary.of(try roleBody(words, at: address)))
        #expect(summary.readsSelfRegister)
        #expect(summary.provenEntryRegisterReads & (1 << 20) == 0)
    }
}

@Test func entryRegisterRolesFollowOnlyProvenInImageInputs() throws {
    // mov x0,x20;b 0x2000 and mov x19,x20;b 0x2000. The same entry
    // receiver can reach ordinary arguments or an outliner's x19 input.
    let cases: [(UInt64, [UInt32], [UInt32])] = [
        (0x1078, [0xaa1403e0, 0x140003e1], [0x91000400, 0xd65f03c0]),
        (0x1080, [0xaa1403f3, 0x140003df], [0xf9400260, 0xd65f03c0]),
    ]
    for (address, words, targetWords) in cases {
        let caller = try #require(CalleeRegisterSummary.of(try roleBody(words, at: address), isFunction: { $0 == 0x2000 }))
        #expect(caller.provenEntryRegisterReads & (1 << 20) == 0)
        var grounded = [address: caller, 0x2000: try #require(CalleeRegisterSummary.of(try roleBody(targetWords, at: 0x2000)))]
        CalleeRegisterSummary.closeOverProvenEntryReads(&grounded)
        #expect(grounded[address]?.provenEntryRegisterReads == 1 << 20)
        var missing = [address: caller]
        CalleeRegisterSummary.closeOverProvenEntryReads(&missing)
        #expect(missing[address]?.provenEntryRegisterReads == 0)
        var unused = [address: caller, 0x2000: try #require(CalleeRegisterSummary.of(try roleBody([0xd65f03c0], at: 0x2000)))]
        CalleeRegisterSummary.closeOverProvenEntryReads(&unused)
        #expect(unused[address]?.provenEntryRegisterReads == 0)
    }
}

@Test func entryRegisterRolesUseDirectPreservationAfterCalls() throws {
    // caller: bl 0x2000;ldr x0,[x20];ret. The callee preserves x20;
    // rebuilding with its final effects establishes the later use's origin.
    let caller = try roleBody([0x940003de, 0xf9400280, 0xd65f03c0], at: 0x1088)
    let leaf = try roleBody([0x91000400, 0xd65f03c0], at: 0x2000)
    // saved: sub sp,sp,32;str x20,[sp];mov x0,sp;bl 0x2000;
    //        ldr x20,[sp];add sp,sp,32;ret
    let saved = try roleBody([0xd10083ff, 0xf90003f4, 0x910003e0, 0x940003d8,
                              0xf94003f4, 0x910083ff, 0xd65f03c0], at: 0x1094)
    // bl saved;ldr x0,[x20];ret
    let uncertainCaller = try roleBody([0x97fffff9, 0xf9400280, 0xd65f03c0], at: 0x10b0)
    let savedSummary = try #require(CalleeRegisterSummary.of(saved))
    #expect(savedSummary.clobberedCalleeSaved.contains("x20"))
    #expect(!savedSummary.definitelyClobbered.contains("x20"))
    func closed(_ bodies: [UInt64: DisassembledFunction]) throws -> [UInt64: CalleeRegisterSummary] {
        let isFunction = { (address: UInt64) in address == 0x2000 || address == 0x1094 }
        var summaries = try bodies.mapValues { try #require(CalleeRegisterSummary.of($0, isFunction: isFunction)) }
        CalleeRegisterSummary.closeOverReads(&summaries)
        CalleeRegisterSummary.closeOverCalls(&summaries) { start, effects, reads, reusePreservation in
            bodies[start].flatMap {
                CalleeRegisterSummary.recomputingPreservation($0, retainingReadsFrom: reads, reusingPreservation: reusePreservation,
                    calleeEffects: effects, isFunction: isFunction)
            }
        }
        CalleeRegisterSummary.closeOverProvenEntryReads(&summaries)
        return summaries
    }
    let known = try closed([0x1088: caller, 0x2000: leaf])
    #expect(known[0x1088]?.provenEntryRegisterReads == 1 << 20)
    let missing = try closed([0x1088: caller])
    #expect(missing[0x1088]?.provenEntryRegisterReads == 0)
    let uncertain = try closed([0x10b0: uncertainCaller, 0x1094: saved])
    #expect(uncertain[0x10b0]?.provenEntryRegisterReads == 0)
}

@Test func entryRegisterRolesRejectUnspecifiedAccessFlags() throws {
    func unspecifiedDestination(_ function: DisassembledFunction) throws -> DisassembledFunction {
        let first = try #require(function.instructions.first)
        let detail = try #require(first.detail)
        var operands = detail.operands
        operands[0].access = 0
        let missing = StructuredInsn(id: detail.id, conditionCode: detail.conditionCode, updatesFlags: detail.updatesFlags,
                                     writeback: detail.writeback, postIndex: detail.postIndex, operands: operands)
        return DisassembledFunction(symbol: function.symbol, demangledName: nil, startAddress: function.startAddress,
            instructions: [Instruction(address: first.address, text: first.text, controlFlow: first.controlFlow,
                                       branchTarget: first.branchTarget, detail: missing)] + function.instructions.dropFirst(),
            source: .symbol)
    }
    // mov x20,#0;ldr x0,[x20];ret, with the first destination's decoder
    // flags removed. Neither that operand nor its later value proves self.
    let gapped = try unspecifiedDestination(roleBody([0xd2800014, 0xf9400280, 0xd65f03c0], at: 0x1000))
    let summary = try #require(CalleeRegisterSummary.of(gapped))
    #expect(summary.readsSelfRegister)
    #expect(summary.provenEntryRegisterReads & (1 << 20) == 0)

    // A legacy possible argument read also proves no forwarded role.
    // mov x0,#0;ret, with its destination's flags removed, still counts as
    // a conservative argument read. It must not ground a receiver proof.
    let target = try unspecifiedDestination(roleBody([0xd2800000, 0xd65f03c0], at: 0x2000))
    let targetSummary = try #require(CalleeRegisterSummary.of(target))
    #expect(targetSummary.provenArgumentReads.contains(0))
    #expect(targetSummary.provenEntryRegisterReads == 0)
    let caller = try #require(CalleeRegisterSummary.of(try roleBody([0xaa1403e0, 0x140003e1], at: 0x1078),
                                                         isFunction: { $0 == 0x2000 }))
    var summaries = [UInt64(0x1078): caller, 0x2000: targetSummary]
    CalleeRegisterSummary.closeOverProvenEntryReads(&summaries)
    #expect(summaries[0x1078]?.provenEntryRegisterReads == 0)
}

private func closeRoleBodies(
    _ bodies: [UInt64: DisassembledFunction], rebuildingEntryRoles: Bool = true
) throws -> [UInt64: CalleeRegisterSummary] {
    let isFunction = { bodies[$0] != nil }
    var summaries = try bodies.mapValues { try #require(CalleeRegisterSummary.of($0, isFunction: isFunction)) }
    CalleeRegisterSummary.closeOverReads(&summaries)
    CalleeRegisterSummary.closeOverCalls(&summaries, rebuildingEntryRoles: rebuildingEntryRoles) { start, effects, reads, reusePreservation in
        bodies[start].flatMap {
            CalleeRegisterSummary.recomputingPreservation($0, retainingReadsFrom: reads,
                reusingPreservation: reusePreservation, rebuildingEntryRoles: rebuildingEntryRoles,
                calleeEffects: effects, isFunction: isFunction)
        }
    }
    if rebuildingEntryRoles { CalleeRegisterSummary.closeOverProvenEntryReads(&summaries) }
    return summaries
}

@Test func entryRegisterRolesReplayCarriedClobbersForQueuedAndVisitedCallers() throws {
    // middle calls a leaf that writes x20. caller and above each call the
    // preceding body, then load through x20. Neither load uses entry self.
    // Both address orders matter: caller may be waiting for a role refresh,
    // or it may already have been refreshed before middle exposes its clobber.
    for (middle, caller, middleCall, callerCall, aboveCall): (UInt64, UInt64, UInt32, UInt32, UInt32) in [
        (0x1000, 0x2000, 0x94000800, 0x97fffc00, 0x97fff800),
        (0x2000, 0x1000, 0x94000400, 0x94000400, 0x97fff400),
    ] {
        let bodies = [
            middle: try roleBody([middleCall, 0xd65f03c0], at: middle),
            caller: try roleBody([callerCall, 0xf9400280, 0xd65f03c0], at: caller),
            0x3000: try roleBody([0xd2800014, 0xd65f03c0], at: 0x3000),
            0x4000: try roleBody([aboveCall, 0xf9400280, 0xd65f03c0], at: 0x4000),
        ]
        let summaries = try closeRoleBodies(bodies)
        for start in [middle, caller, 0x4000] {
            let summary = try #require(summaries[start])
            #expect(summary.clobberedCalleeSaved.contains("x20"))
            #expect(summary.effect.clobbers.contains("x20"))
            #expect(summary.provenEntryRegisterReads & (1 << 20) == 0)
        }
        #expect(summaries[caller]?.readsSelfRegister == true)
    }
}

@Test func entryRegisterRolesReplayOutlinedReloadsBeforeReusingPreservation() throws {
    // leaf reloads x20 from entry sp+8; middle tail-branches to leaf.
    // caller saves entry x20 there, overwrites it, calls middle and returns.
    // The newly discovered reload preserves caller's x20, so above's later
    // load really does consume entry self. The carried clobber set remains
    // empty while the reload appears: comparing only clobbers misses it.
    let bodies: [UInt64: DisassembledFunction] = [
        0x1000: try roleBody([0x14000800], at: 0x1000),
        0x2000: try roleBody([0xd10083ff, 0xf90007f4, 0xd2800014, 0x97fffbfd,
                              0x910083ff, 0xd65f03c0], at: 0x2000),
        0x3000: try roleBody([0xf94007f4, 0xd65f03c0], at: 0x3000),
        0x4000: try roleBody([0x97fff800, 0xf9400280, 0xd65f03c0], at: 0x4000),
    ]
    let summaries = try closeRoleBodies(bodies)
    #expect(summaries[0x1000]?.restoredFrom["x20"] == 8)
    #expect(summaries[0x1000]?.effect.clobbers.isEmpty == true)
    #expect(summaries[0x2000]?.clobberedCalleeSaved.isEmpty == true)
    #expect(summaries[0x4000]?.clobberedCalleeSaved.isEmpty == true)
    #expect(try #require(summaries[0x4000]).provenEntryRegisterReads & (1 << 20) != 0)
}

@Test func signatureOnlyReceiverProofsAreStillConsumedIfPresent() async throws {
    let path = "Fixtures/Sample/libEntryRoleConsumers.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Entry = @convention(c) () -> Int
    let native = try #require(dlsym(library, "entry_role_consumer_native"))
    #expect(unsafeBitCast(native, to: Entry.self)() == 11)
    let valueNative = try #require(dlsym(library, "entry_role_value_consumer_native"))
    #expect(unsafeBitCast(valueNative, to: Entry.self)() == 30)
    let image = try BinaryLoader.load(path: path)
    #expect(!image.sections.contains { $0.sectionName.hasPrefix("__swift") })
    #expect(!image.symbols.contains { Disassembler.isSwiftMangled($0.name) })
    let all = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let addresses = Set(all.map(\.startAddress))
    #expect(all.count == 6)
    // Signature-only images retain the positive IR facts even when the
    // current receiver layout is incomplete. Conservative MAY reads can
    // already suppress a bad trailing receiver in text; that alone does
    // not prove that the image classifier kept the requested proof graph.
    let names = Dictionary(all.map { ($0.startAddress, $0.analysisDisplayName) }, uniquingKeysWith: { a, _ in a })
    let proofs = try closeRoleBodies(
        Dictionary(all.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a }),
        rebuildingEntryRoles: Disassembler.needsEntryRegisterProofs(
            in: image, names: names, folded: [:], swiftTargets: []))
    let contextBody = try #require(all.first { $0.symbol.contains("EntryProof.Context.read(") })
    let valueBody = try #require(all.first { $0.symbol.contains("Swift.Int.roleRead(") })
    #expect(try #require(proofs[contextBody.startAddress]).provenEntryRegisterReads & (1 << 20) != 0)
    #expect(try #require(proofs[valueBody.startAddress]).provenEntryRegisterReads & (1 << 1) != 0)
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "consumer_native")
    }
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: addresses, in: image, transform: { $0 })
    }
    for functions in [all, filtered, streamed, Array(each.values)] {
        let caller = try #require(functions.first { $0.symbol == "_entry_role_consumer_native" })
        let call = try #require(caller.instructions.first { $0.controlFlow == .call })
        #expect(call.callArguments == ["7"])
        for text in [caller.renderPseudo(), caller.renderStructured()] {
            #expect(text.contains("EntryProof.Context.read(7)"), Comment(rawValue: text))
            #expect(!text.contains("29"), Comment(rawValue: text))
        }
        let valueCaller = try #require(functions.first { $0.symbol == "_entry_role_value_consumer_native" })
        let valueCall = try #require(valueCaller.instructions.first { $0.controlFlow == .call })
        // The image has no complete value-type layout for Swift.Int. Keep
        // its ordinary receiver's positive input proof above, but decline
        // that layout-dependent argument in the rendered call.
        #expect(valueCall.callArguments == ["7"])
        for text in [valueCaller.renderPseudo(), valueCaller.renderStructured()] {
            #expect(text.contains("Swift.Int.roleRead(7)"), Comment(rawValue: text))
        }
    }
}

@Test func omittingUnusedEntryRolesKeepsMAYReadsAndPreservation() throws {
    let leaf = try roleBody([0xf9400280, 0xd65f03c0], at: 0x5000)
    // An escaped save remains a possible x20 read, regardless of whether
    // any caller requests a positive entry-value role proof.
    let escaped = try roleBody([
        0xd10083ff, 0xf90003f4, 0xaa0103f4, 0x910003e0, 0x940003fc,
        0xf9400009, 0xf9400120, 0x910083ff, 0xd65f03c0,
    ], at: 0x6000)
    let graphs: [[UInt64: DisassembledFunction]] = [
        [0x1000: try roleBody([0x94000800, 0xd65f03c0], at: 0x1000),
         0x2000: try roleBody([0x97fffc00, 0xf9400280, 0xd65f03c0], at: 0x2000),
         0x3000: try roleBody([0xd2800014, 0xd65f03c0], at: 0x3000),
         0x4000: try roleBody([0x97fff800, 0xf9400280, 0xd65f03c0], at: 0x4000)],
        [0x1000: try roleBody([0x14000800], at: 0x1000),
         0x2000: try roleBody([0xd10083ff, 0xf90007f4, 0xd2800014, 0x97fffbfd,
                              0x910083ff, 0xd65f03c0], at: 0x2000),
         0x3000: try roleBody([0xf94007f4, 0xd65f03c0], at: 0x3000),
         0x4000: try roleBody([0x97fff800, 0xf9400280, 0xd65f03c0], at: 0x4000)],
    ]
    for (index, graph) in graphs.enumerated() {
        let bodies = graph.merging([0x5000: leaf, 0x6000: escaped]) { a, _ in a }
        let full = try closeRoleBodies(bodies)
        let omitted = try closeRoleBodies(bodies, rebuildingEntryRoles: false)
        #expect(full[0x5000]?.provenEntryRegisterReads == 1 << 20)
        #expect(omitted[0x6000]?.readsSelfRegister == true)
        for start in bodies.keys.sorted() {
            var expected = try #require(full[start])
            expected.provenEntryRegisterReads = 0
            expected.pendingEntryRegisterReads = []
            expected.needsEntryPreservation = false
            #expect(omitted[start] == expected, "graph \(index), function \(String(start, radix: 16))")
        }
        if index == 0 {
            #expect(omitted[0x4000]?.effect.clobbers.contains("x20") == true)
        } else {
            #expect(omitted[0x1000]?.restoredFrom["x20"] == 8)
            #expect(omitted[0x4000]?.clobberedCalleeSaved.isEmpty == true)
        }
        // Removing role work must not remove the full-preservation cap or
        // the failure fallback for an outstanding clobber/reload dependency.
        for cap in [nil, 0] as [Int?] {
            var failed = try bodies.mapValues { try #require(CalleeRegisterSummary.of($0, isFunction: { bodies[$0] != nil })) }
            CalleeRegisterSummary.closeOverReads(&failed)
            var callbacks = 0
            CalleeRegisterSummary.closeOverCalls(&failed, cap: cap, rebuildingEntryRoles: false) { _, _, _, _ in
                callbacks += 1
                return nil
            }
            #expect(cap == 0 ? callbacks == 0 : callbacks > 0)
            #expect(failed[0x4000]?.clobberedCalleeSaved == Set(Preservation.calleeSavedKeys))
            #expect(failed[0x4000]?.provenEntryRegisterReads == 0)
        }
    }
}
