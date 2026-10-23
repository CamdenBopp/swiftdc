import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A callee clobbers the callee-saved registers its own callees clobber,
/// through a call or a tail branch, unless it restores them itself
/// (`preserve_calls.s`). The summaries judged each body alone, so a caller
/// keeping arg0 in x19 across `nested_outer` (which calls a fragment that
/// writes x19) or `tail_outer` (which tail-branches to it) rendered
/// `return arg0`, where native execution returns arg1.
///
/// A callee that uses the caller's x29 as a pointer can write the save slot
/// x29 points at: `x29_fragment` rendered `return arg0`, native 2.
///
/// A restore can be outlined too: GoodLinks' assertion paths save x19 and
/// x20, call a fragment that rewrites them and tail-branch to a fragment
/// that reloads them from the frame. Read as a clobber, that reload lost
/// `self` in about 160 of their callers' lines. It restores only what the
/// slot holds: a slot holding arg1, or one written before the reload, hands
/// back something else.
@Test func clobbersReachThroughNestedAndTailCallsIfPresent() async throws {
    let path = "Fixtures/Sample/libPreserveCalls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Caller = @convention(c) (Int, Int) -> Int
    func native(_ name: String) throws -> Int {
        let symbol = try #require(dlsym(library, "$s8Preserve\(name)yS2i_SitF"))
        return unsafeBitCast(symbol, to: Caller.self)(1, 2)
    }
    #expect(try native("6nested") == 2 && native("4tail") == 2 && native("5saved") == 1
        && native("7guarded") == 1 && native("7control") == 1)
    #expect(try native("8epilogue") == 1 && native("6direct") == 1 && native("8reloaded") == 1
        && native("6forged") == 2 && native("9scribbled") == 2 && native("7smudged") == 2)
    #expect(try native("3x29") == 2 && native("8x29relay") == 2 && native("8x29local") == 2
        && native("8x29below") == 2)

    let full = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "Preserve")
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let expected = [
        "Preserve.nested(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
        "Preserve.tail(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
        // Restores x19 around the same call: preserved.
        "Preserve.saved(Swift.Int, Swift.Int) -> Swift.Int": "return arg0",
        // Two calls down, a body saves x19 but passes a stack address on, so
        // its save is not provably intact: clobbered for its direct caller,
        // not carried further.
        "Preserve.guarded(Swift.Int, Swift.Int) -> Swift.Int": "return arg0",
        "Preserve.control(Swift.Int, Swift.Int) -> Swift.Int": "return arg0",
        // An outlined epilogue reached by a tail branch or a call reloads
        // what the helper saved, after a fragment or the helper itself
        // rewrote it.
        "Preserve.epilogue(Swift.Int, Swift.Int) -> Swift.Int": "return arg0",
        "Preserve.direct(Swift.Int, Swift.Int) -> Swift.Int": "return arg0",
        "Preserve.reloaded(Swift.Int, Swift.Int) -> Swift.Int": "return arg0",
        // The reloaded slot holds arg1, or was written before the reload.
        "Preserve.forged(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
        "Preserve.scribbled(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
        "Preserve.smudged(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
        // A callee writes through the frame pointer the fragment set to its
        // save slot, directly or through a tail branch.
        "Preserve.x29(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
        "Preserve.x29relay(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
        // The same callee shape writes the caller's own local through x29.
        "Preserve.x29local(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
        "Preserve.x29below(Swift.Int, Swift.Int) -> Swift.Int": "return ?",
    ]
    for (path, functions) in [("array", full), ("filtered", filtered), ("streaming", streamed)] {
        for (name, statement) in expected.sorted(by: { $0.key < $1.key }) {
            let function = try #require(functions.first { $0.displayName == name }, "\(path): no \(name)")
            let text = function.renderPseudo()
            #expect(text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.contains(statement),
                    "\(path) \(name):\n\(text)")
        }
    }
}

private func fragment(_ words: [UInt32]) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "_fragment", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

/// A reload is a load from entry sp or above that every exit agrees on and
/// nothing written since entry can have reached. Words from
/// `xcrun clang -arch arm64 -c`.
@Test func anOutlinedEpilogueReloadsItsCallersSaves() throws {
    // ldp x20, x19, [sp, #0x20]; ldp x22, x21, [sp, #0x10];
    // ldp x24, x23, [sp], #0x40; ret
    let epilogue = try #require(CalleeRegisterSummary.of(fragment([0xa9424ff4, 0xa94157f6, 0xa8c45ff8, 0xd65f03c0])))
    #expect(epilogue.clobberedCalleeSaved == ["x19", "x20", "x21", "x22", "x23", "x24"])
    // x21 is not carried through calls, reloaded or not.
    #expect(epilogue.effect == CalleeEffect(
        clobbers: [], restores: ["x19": 0x28, "x20": 0x20, "x22": 0x10, "x23": 0x8, "x24": 0x0]))
    // sturb w1, [sp, #-8]; ldur x19, [sp, #-8]; ret: below entry sp is this
    // body's own frame, which it has just written.
    let below = try #require(CalleeRegisterSummary.of(fragment([0x381f83e1, 0xf85f83f3, 0xd65f03c0])))
    #expect(below.effect == CalleeEffect(clobbers: ["x19"]))
    // cbz x0, 1f; ldr x19, [sp]; ret; 1: ldr x19, [sp, #8]; ret: two exits
    // reload different slots.
    let split = try #require(CalleeRegisterSummary.of(fragment([0xb4000060, 0xf94003f3, 0xd65f03c0, 0xf94007f3, 0xd65f03c0])))
    #expect(split.effect == CalleeEffect(clobbers: ["x19"]))
}

/// The closure over calls claims nothing where it cannot finish: a function
/// still waiting at the cap, every function that calls one, directly or not,
/// and a function whose body cannot be summarised again.
@Test func anUnfinishedClosureClaimsNothingUpTheCallGraph() {
    let all: Set<String> = Set((19...29).map { "x\($0)" })
    // 0x10 clobbers x19 itself; 0x20 calls it, 0x30 calls 0x20, 0x40 calls 0x30.
    func graph() -> [UInt64: CalleeRegisterSummary] {
        [
            0x10: CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: ["x19"], definitelyClobbered: ["x19"]),
            0x20: CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [], callees: [0x10]),
            0x30: CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [], callees: [0x20]),
            0x40: CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: [], callees: [0x30]),
        ]
    }
    // A body inherits its callees' clobbers.
    func rebuild(_ summaries: [UInt64: CalleeRegisterSummary], _ start: UInt64, _ effects: (UInt64) -> CalleeEffect) -> CalleeRegisterSummary? {
        let callees = summaries[start]?.callees ?? []
        let clobbers = callees.reduce(into: Set<String>()) { $0.formUnion(effects($1).clobbers) }
        return CalleeRegisterSummary(argumentReads: [], clobberedCalleeSaved: clobbers, definitelyClobbered: clobbers, callees: callees)
    }

    var settled = graph()
    let original = settled
    CalleeRegisterSummary.closeOverCalls(&settled) { rebuild(original, $0, $1) }
    #expect(settled[0x40]?.clobberedCalleeSaved == ["x19"])

    // One rebuild (0x20) fits under the cap; 0x30 waits. 0x40 was summarised
    // before 0x20 was known to clobber x19, so it claims nothing either.
    var capped = graph()
    CalleeRegisterSummary.closeOverCalls(&capped, cap: 1) { rebuild(original, $0, $1) }
    #expect(capped[0x20]?.clobberedCalleeSaved == ["x19"])
    #expect(capped[0x30]?.clobberedCalleeSaved == all)
    #expect(capped[0x40]?.clobberedCalleeSaved == all)
    #expect(capped[0x40]?.definitelyClobbered == all)

    // 0x20 cannot be rebuilt: it claims nothing, and its callers carry that.
    var failed = graph()
    CalleeRegisterSummary.closeOverCalls(&failed) { start, effects in
        start == 0x20 ? nil : rebuild(original, start, effects)
    }
    #expect(failed[0x20]?.clobberedCalleeSaved == all)
    #expect(failed[0x40]?.definitelyClobbered == all)
}
