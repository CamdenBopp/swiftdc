import Foundation
import Testing
@testable import SwiftDecompilerCore

struct SharedFrameMemoryEffectTests {
    @Test func disjointMayRegionsKeepHalfOpenExtentsAndTheirGaps() {
        let a = FrameMemoryEffect([.finite(lower: -64, upper: -48)], arithmetic: .wrapping)
        let b = FrameMemoryEffect([.finite(lower: -24, upper: -8)], arithmetic: .wrapping)
        let joined = a.union(b)
        #expect(joined == b.union(a))
        #expect(joined.union(a) == joined)
        #expect(!joined.mayInvalidate(.init(start: -48, bytes: 8)))
        #expect(!joined.mayInvalidate(.init(start: -40, bytes: 8)))
        #expect(!joined.mayInvalidate(.init(start: -8, bytes: 8)))
        #expect(joined.mayInvalidate(.init(start: -56, bytes: 8)))
        #expect(joined.mayInvalidate(.init(start: -32, bytes: 16)))
        #expect(joined.mayInvalidate(.init(start: -49, bytes: 2)))
        #expect(joined.mayInvalidate(.init(start: -25, bytes: 2)))
        #expect(FrameMemoryEffect(arithmetic: .wrapping).isEmpty)
    }

    @Test func wrappingCheckedAndFiniteSentinelPoliciesRemainDistinct() {
        let finite = FrameMemoryEffect([.finite(lower: -16, upper: 0)], arithmetic: .wrapping)
        let checked = FrameMemoryEffect([.finite(lower: -16, upper: 0)], arithmetic: .checked)
        let overflowing = FrameMemoryExtent(start: .max - 3, bytes: 8)
        #expect(!finite.mayInvalidate(overflowing))
        #expect(checked.mayInvalidate(overflowing))
        let upperSentinel = FrameMemoryEffect([.finite(lower: .min, upper: .max)], arithmetic: .wrapping)
        let noUpperCheck = FrameMemoryEffect([.atOrAbove(.min)], arithmetic: .wrapping)
        #expect(!upperSentinel.mayInvalidate(.init(start: .max, bytes: 0)))
        #expect(noUpperCheck.mayInvalidate(.init(start: .max, bytes: 0)))
        let lowerSentinel = FrameMemoryEffect([.finite(lower: .min, upper: 0)], arithmetic: .wrapping)
        let startOnly = FrameMemoryEffect([.startsBelow(0)], arithmetic: .wrapping)
        #expect(!lowerSentinel.mayInvalidate(.init(start: .min, bytes: 0)))
        #expect(startOnly.mayInvalidate(.init(start: .min, bytes: 0)))
        // Legacy queries do not reject zero widths or normalize reversed
        // bounds. These controls are compatibility claims, not valid objects.
        #expect(finite.mayInvalidate(.init(start: -8, bytes: 0)))
        let reversed = FrameMemoryEffect([.finite(lower: 10, upper: -10)], arithmetic: .wrapping)
        #expect(reversed.mayInvalidate(.init(start: -20, bytes: 40)))
        #expect(FrameMemoryEffect(arithmetic: .wrapping, everything: true).mayInvalidate(overflowing))
        #expect(!FrameMemoryEffect(arithmetic: .checked).mayInvalidate(overflowing))
    }

    @Test func callerOwnedReachIncludesStraddlesButKeepsWhollyPrivateFacts() {
        let caller = FrameMemoryEffect([.atOrAbove(0)], arithmetic: .checked)
        for start: Int64 in [0, 16, -4, -7, .max - 3] {
            #expect(caller.mayInvalidate(.init(start: start, bytes: 8)))
        }
        for start: Int64 in [-8, -16] {
            #expect(!caller.mayInvalidate(.init(start: start, bytes: 8)))
        }
    }

    private static func decoded(_ words: [UInt32]) throws -> [Instruction] {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        return decoded.map { item in
            Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                        branchTarget: item.branchTarget, detail: item.detail,
                        callee: .kept(item.controlFlow == .call ? "frame_mutating_helper" : nil))
        }
    }

    private static func trace(factOffset: Int, escapeOffsets: [Int], storeAfterFirst: Bool = false) throws -> AbstractValue {
        // Every offset is in the fixed64-byte frame. Address-taking after
        // the calls gives layout boundaries without passing a second alias.
        var words: [UInt32] = [0xd10103ff] // sub sp,sp,#64
        func storeSeven() {
            words += [0xd28000e9, 0xf90003e9 | (UInt32(factOffset / 8) << 10)]
        }
        if !storeAfterFirst { storeSeven() }
        for (index, offset) in escapeOffsets.enumerated() {
            words.append(0x910003e0 | (UInt32(offset) << 10)) // add x0,sp,#offset
            words.append(0x94000000 | UInt32((0x3000 - (0x1000 + 4 * words.count)) / 4))
            if storeAfterFirst && index == 0 { storeSeven() }
        }
        if storeAfterFirst {
            // The later call has no new frame pointer input. Its reach must
            // come from the marker retained after the earlier call.
            words += [0xaa1f03e0]
            words.append(0x94000000 | UInt32((0x3000 - (0x1000 + 4 * words.count)) / 4))
        }
        words += [0x910003eb | (UInt32(factOffset) << 10), 0xf9400160, 0x910103ff, 0xd65f03c0]
        let body = try decoded(words)
        let function = DisassembledFunction(symbol: "_frame_effect", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .address)
        let analysis = ValueTracer().analyze(function, entry: nil)
        return analysis.exitValues[try #require(body.last?.address)] ?? .unknown
    }

    private static func preserved(factOffset: Int, escapeOffsets: [Int]) -> Preservation.Value {
        let fact = Int64(factOffset - 64)
        var state = Preservation.State(registers: ["sp": .stack(-64)],
                                       slots: [fact: .entry("x19"), -8: .entry("x29")])
        for offset in escapeOffsets {
            state.setRegister("x0", to: .stack(Int64(offset - 64)))
            Preservation.applyCall(CalleeEffect(), inputs: ["x0"], to: &state, clobbersMayAliasStack: false)
        }
        return state.load(at: fact)
    }

    // Each strict-boundary kernel mutation must fail this real tracer test
    // AND preservationUsesSharedHalfOpenEscapeEffects below.
    @Test func tracerUsesSharedHalfOpenEscapeEffects() throws {
        #expect(try Self.trace(factOffset: 16, escapeOffsets: [8]) == .immediate(7))
        #expect(try Self.trace(factOffset: 8, escapeOffsets: [16]) == .immediate(7))
        #expect(try Self.trace(factOffset: 16, escapeOffsets: [16]) == .unknown)
        #expect(try Self.trace(factOffset: 24, escapeOffsets: [8, 40]) == .immediate(7))
        #expect(try Self.trace(factOffset: 16, escapeOffsets: [16], storeAfterFirst: true) == .unknown)
    }

    @Test func preservationUsesSharedHalfOpenEscapeEffects() {
        #expect(Self.preserved(factOffset: 16, escapeOffsets: [8]) == .entry("x19"))
        #expect(Self.preserved(factOffset: 8, escapeOffsets: [16]) == .entry("x19"))
        #expect(Self.preserved(factOffset: 16, escapeOffsets: [16]) == .unknown)
        #expect(Self.preserved(factOffset: 24, escapeOffsets: [8, 40]) == .entry("x19"))
        // A non-entry snapshot does not bound the escaped object's extent;
        // the shared effect must actually erase this overlapping fact.
        var state = Preservation.State(registers: ["sp": .stack(-64)],
                                       slots: [-48: .incoming(64), -8: .entry("x29")])
        state.setRegister("x0", to: .stack(-56))
        Preservation.applyCall(CalleeEffect(), inputs: ["x0"], to: &state, clobbersMayAliasStack: false)
        #expect(state.load(at: -48) == .unknown)
    }

    @Test func preservationUnknownWritesKeepCallerOwnershipAndPersistentEscape() {
        for offset: Int64 in [0, 16, -4, -7, -8, -16, .max - 3] {
            var state = Preservation.State(registers: ["sp": .stack(-64)], slots: [offset: .entry("x19")])
            Preservation.applyCall(CalleeEffect(), inputs: [], to: &state, clobbersMayAliasStack: false)
            #expect(state.load(at: offset) == (offset <= -8 ? .entry("x19") : .unknown))
            #expect(!state.incomingIntact)
        }
        var escaped = Preservation.State(registers: ["sp": .stack(-64)], slots: [-48: .entry("x19")])
        escaped.setRegister("x0", to: .stack(-48))
        Preservation.applyCall(CalleeEffect(), inputs: ["x0"], to: &escaped, clobbersMayAliasStack: false)
        escaped.slots[-48] = .entry("x19")
        Preservation.applyCall(CalleeEffect(), inputs: [], to: &escaped, clobbersMayAliasStack: false)
        #expect(escaped.load(at: -48) == .unknown)

        // Finite reach must also survive a later call with no new alias.
        // The incoming value is not an entry-save boundary, so this does
        // not use the whole-frame escape flag exercised above.
        var finite = Preservation.State(registers: ["sp": .stack(-64)],
                                        slots: [-48: .incoming(64), -8: .entry("x29")])
        finite.setRegister("x0", to: .stack(-56))
        Preservation.applyCall(CalleeEffect(), inputs: ["x0"], to: &finite, clobbersMayAliasStack: false)
        #expect(finite.load(at: -48) == .unknown)
        finite.slots[-48] = .incoming(64)
        Preservation.applyCall(CalleeEffect(), inputs: [], to: &finite, clobbersMayAliasStack: false)
        #expect(finite.load(at: -48) == .unknown)
    }

    @Test func tracerLostSlotClosureStillFindsThePointersTarget() throws {
        // A at sp+8 holds B's address (sp+16). Escaping A loses the last
        // tracked copy of B's pointer; B must then escape in the same closure.
        let body = try Self.decoded([
            0xd10103ff, 0x910043ec, 0xf90007ec, 0xd28000e9, 0xf9000be9,
            0x910023e0, 0x940007fa,
            0x910043eb, 0xf9400160, 0x910103ff, 0xd65f03c0,
        ])
        let function = DisassembledFunction(symbol: "_lost_frame_pointer", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .address)
        #expect((ValueTracer().analyze(function, entry: nil).exitValues[0x1028] ?? .unknown) == .unknown)
    }
}
