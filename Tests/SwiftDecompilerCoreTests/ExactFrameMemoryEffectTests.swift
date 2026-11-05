import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Authored source draft. Core matrices deliberately contain no calls or
/// escapes: an unknown-write effect cannot supply their mutation failures.
struct ExactFrameMemoryEffectTests {
    private static func function(_ words: [UInt32], callee: String? = nil) throws -> DisassembledFunction {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
        }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        try #require(decoded.last?.controlFlow == .return)
        if callee == nil { try #require(!decoded.contains { $0.controlFlow == .call }) }
        let body = decoded.map { item in
            Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                        branchTarget: item.branchTarget, detail: item.detail,
                        callee: .kept(item.controlFlow == .call ? callee : nil))
        }
        return DisassembledFunction(symbol: "_exact_frame_core", demangledName: nil,
            startAddress: 0x1000, instructions: body, source: .address)
    }

    private static func trace(
        _ words: [UInt32], entry: MethodEntryConvention = .swiftFunction(scalarArguments: ["x2": 0, "x3": 1]),
        callee: String? = nil
    ) throws -> (integer: AbstractValue, floating: AbstractValue, analysis: FunctionAnalysis) {
        let function = try function(words, callee: callee)
        let analysis = ValueTracer().analyze(function, entry: entry)
        let exit = try #require(function.instructions.last?.address)
        return (analysis.exitValues[exit] ?? .unknown, analysis.exitFloatValues[exit] ?? .unknown, analysis)
    }

    private static func overwritten(
        by word: UInt32, facts: [Int] = [16, 24]
    ) throws -> [AbstractValue] {
        var prefix: [UInt32] = [0xd10103ff, 0xd28000e9] // sub sp,#64; mov x9,#7
        prefix.append(0xf90003e9 | (UInt32(facts[0] / 8) << 10))
        if facts.count == 2 {
            prefix.append(0xd280016a) // mov x10,#11
            prefix.append(0xf90003ea | (UInt32(facts[1] / 8) << 10))
        }
        prefix.append(word)
        var values: [AbstractValue] = []
        for offset in facts {
            var body = prefix
            body += [0xf94003e0 | (UInt32(offset / 8) << 10), 0x910103ff, 0xd65f03c0]
            values.append(try trace(body).integer)
        }
        return values
    }

    @Test func inlineRegionConstructionAndMayUnionsAreCanonicalValues() {
        let region = FrameMemoryEffect.Region.finite(lower: -16, upper: -8)
        let direct = FrameMemoryEffect(region, arithmetic: .checked)
        let fromSet = FrameMemoryEffect(Set([region]), arithmetic: .checked)
        let empty = FrameMemoryEffect(arithmetic: .checked)
        #expect(direct == fromSet)
        #expect(empty.union(direct) == direct)
        #expect(direct.union(empty) == direct)
        #expect(direct.union(direct) == direct)
        let other = FrameMemoryEffect(.finite(lower: 8, upper: 16), arithmetic: .checked)
        let joined = direct.union(other)
        let expected = FrameMemoryEffect([region, .finite(lower: 8, upper: 16)], arithmetic: .checked)
        #expect(joined == expected)
        #expect(joined == other.union(direct))
        #expect(joined.union(direct) == joined)
        #expect(!joined.mayInvalidate(.init(start: -8, bytes: 8)))
        #expect(joined.mayInvalidate(.init(start: 8, bytes: 8)))
    }

    @Test func sharedEndpointComparisonKeepsOrderAndShortCircuiting() {
        var observed: [String] = []
        func endpoint(_ name: String, _ value: Int64) -> Int64 {
            observed.append(name)
            return value
        }
        let upperFalse = FrameMemoryEffect.strictlyOverlaps(lower: -16, upper: endpoint("upper", 8),
            factStart: 8, factEnd: endpoint("fact-end", 16), order: .upperFirst)
        #expect(!upperFalse)
        #expect(observed == ["upper"])
        observed.removeAll()
        let upperThenLower = FrameMemoryEffect.strictlyOverlaps(lower: -16, upper: endpoint("upper", 8),
            factStart: 0, factEnd: endpoint("fact-end", 8), order: .upperFirst)
        #expect(upperThenLower)
        #expect(observed == ["upper", "fact-end"])
        observed.removeAll()
        let lowerFalse = FrameMemoryEffect.strictlyOverlaps(lower: 8, upper: endpoint("upper", 16),
            factStart: 0, factEnd: endpoint("fact-end", 8), order: .lowerFirst)
        #expect(!lowerFalse)
        #expect(observed == ["fact-end"])
        observed.removeAll()
        let lowerThenUpper = FrameMemoryEffect.strictlyOverlaps(lower: -16, upper: endpoint("upper", 8),
            factStart: 0, factEnd: endpoint("fact-end", 8), order: .lowerFirst)
        #expect(lowerThenUpper)
        #expect(observed == ["fact-end", "upper"])
    }

    @Test func exactTracerConstructionDoesNotEvaluateAnyEndpoint() {
        // Neither effect is queried: these endpoints would overflow on a
        // trapping addition. Construction/equality must only carry operands.
        let above = FrameMemoryEffect.legacyTracerExactWrite(start: .max - 3, bytes: 8)
        let below = FrameMemoryEffect.legacyTracerExactWrite(start: .min + 3, bytes: -8)
        #expect(!above.isEmpty)
        #expect(!below.isEmpty)
        #expect(above == FrameMemoryEffect.legacyTracerExactWrite(start: .max - 3, bytes: 8))
    }

    @Test func exactTracerFirstFalseDoesNotEvaluateOverflowingFactEnd() {
        let effect = FrameMemoryEffect.legacyTracerExactWrite(start: -16, bytes: 8)
        let overflowingFact = FrameMemoryExtent(start: .max - 3, bytes: 8)
        #expect(!effect.mayInvalidate(overflowingFact))
        let touchingUpper = FrameMemoryEffect.legacyTracerExactWrite(start: 0, bytes: 8)
        #expect(!touchingUpper.mayInvalidate(.init(start: 8, bytes: .max)))
    }

    @Test func checkedFactOverflowInvalidatesBeforeAnUpperBoundVeto() {
        let effect = FrameMemoryEffect(.finite(lower: -16, upper: -8), arithmetic: .checked)
        #expect(effect.mayInvalidate(.init(start: .max - 3, bytes: 8)))
        var state = Preservation.State(registers: [:], slots: [.max - 3: .entry("x19")])
        state.invalidateSlots(at: -16, bytes: 8)
        #expect(state.slots.isEmpty)
    }

    @Test func tracerNoOldFactsDoesNotEvaluateTheWriteEnd() throws {
        // API-boundary compatibility only, not a valid native frame claim.
        // str x0,[x9]; ldr x0,[x9]; ret. The store has no old stack facts to query.
        let entry = MethodEntryConvention.swiftValueInstance(seededRegisters: [
            "x9": .frame(.max - 3), "x0": .immediate(7),
        ])
        let result = try Self.trace([0xf9000120, 0xf9400120, 0xd65f03c0], entry: entry)
        #expect(result.integer == .immediate(7))
    }

    @Test func exactTracerStrictBoundariesAndGapUseTheSharedKernel() throws {
        // The initial store is the only old fact, so a boundary mutation
        // cannot be killed just by an adjacent setup store.
        let endsAtStart = try Self.overwritten(by: 0x39003fe2, facts: [16]) // strb w2,[sp,#15]
        let startsAtEnd = try Self.overwritten(by: 0x390063e2, facts: [16]) // strb w2,[sp,#24]
        #expect(endsAtStart == [.immediate(7)])
        #expect(startsAtEnd == [.immediate(7)])
        // One eight-byte write fits exactly between both saved words.
        let gap = try Self.overwritten(by: 0xf9000fe2, facts: [16, 32]) // str x2,[sp,#24]
        #expect(gap == [.immediate(7), .immediate(11)])
    }

    @Test func exactPreservationStrictBoundariesAndGapUseTheSharedKernel() {
        for (address, bytes) in [(Int64(-49), 1), (Int64(-40), 1)] {
            var state = Preservation.State(registers: [:], slots: [-48: .entry("x19")])
            state.invalidateSlots(at: address, bytes: bytes)
            #expect(state.load(at: -48) == .entry("x19"))
        }
        var gap = Preservation.State(registers: [:], slots: [-48: .entry("x19"), -32: .entry("x20")])
        gap.invalidateSlots(at: -40, bytes: 8)
        #expect(gap.load(at: -48) == .entry("x19"))
        #expect(gap.load(at: -32) == .entry("x20"))
        #expect(gap.incomingIntact)
    }

    private struct StoreCase {
        let word: UInt32
        let values: [AbstractValue]
        let clobbers: Set<String>
        let assembly: String
    }

    private static let stores: [StoreCase] = [
        .init(word: 0x39004fe2, values: [.unknown, .immediate(11)], clobbers: ["x19"], assembly: "strb w2,[sp,#19]"),
        .init(word: 0x79002fe2, values: [.unknown, .immediate(11)], clobbers: ["x19"], assembly: "strh w2,[sp,#22]"),
        .init(word: 0x780173e2, values: [.unknown, .unknown], clobbers: ["x19", "x20"], assembly: "sturh w2,[sp,#23]"),
        .init(word: 0xb90017e2, values: [.unknown, .immediate(11)], clobbers: ["x19"], assembly: "str w2,[sp,#20]"),
        .init(word: 0xf80143e2, values: [.unknown, .unknown], clobbers: ["x19", "x20"], assembly: "stur x2,[sp,#20]"),
        .init(word: 0xfd000be2, values: [.unknown, .immediate(11)], clobbers: ["x19"], assembly: "str d2,[sp,#16]"),
        .init(word: 0x3d8007e0, values: [.unknown, .unknown], clobbers: ["x19", "x20"], assembly: "str q0,[sp,#16]"),
        .init(word: 0x29018fe2, values: [.unknown, .immediate(11)], clobbers: ["x19"], assembly: "stp w2,w3,[sp,#12]"),
        .init(word: 0xa9010fe2, values: [.argument(0), .argument(1)], clobbers: ["x19", "x20"], assembly: "stp x2,x3,[sp,#16]"),
        .init(word: 0xad0007e0, values: [.unknown, .unknown], clobbers: ["x19", "x20"], assembly: "stp q0,q1,[sp]"),
        .init(word: 0xa8010fe2, values: [.argument(0), .argument(1)], clobbers: ["x19", "x20"], assembly: "stnp x2,x3,[sp,#16]"),
    ]

    @Test func tracerExactWidthsAndPairStridesRetainOnlySupportedValues() throws {
        for store in Self.stores {
            let values = try Self.overwritten(by: store.word)
            #expect(values == store.values, Comment(rawValue: store.assembly))
        }
    }

    @Test func preservationExactWidthsAndPairStridesLoseOnlyOverlappingSaves() throws {
        for store in Self.stores {
            let function = try Self.function([
                0xd100c3ff, 0xa90153f3, 0xaa0003f3, 0xaa0103f4,
                store.word, 0xa94153f3, 0x9100c3ff, 0xd65f03c0,
            ])
            let summary = try #require(CalleeRegisterSummary.of(function))
            #expect(summary.clobberedCalleeSaved == store.clobbers, Comment(rawValue: store.assembly))
        }
    }

    @Test func exactPreservationKeepsOwnershipAndInvalidExtentPoliciesSeparate() {
        for (address, bytes, intact) in [(Int64(-8), 8, true), (Int64(-4), 8, false), (Int64(0), 1, false)] {
            var state = Preservation.State(registers: [:], slots: [-32: .entry("x19")])
            state.invalidateSlots(at: address, bytes: bytes)
            #expect(state.incomingIntact == intact)
            #expect(state.load(at: -32) == .entry("x19"))
        }
        for (address, bytes) in [(Int64(0), 0), (Int64(-16), -1), (Int64.max - 3, 8)] {
            var state = Preservation.State(registers: [:], slots: [-32: .entry("x19")])
            state.invalidateSlots(at: address, bytes: bytes)
            #expect(state.slots.isEmpty)
            #expect(!state.incomingIntact)
        }
    }

    @Test func exactTracerOutgoingMetadataTracksTheLastWholeSnapshot() throws {
        // A call-site snapshot observes outgoing metadata before any call
        // invalidation. Neither input carries a frame pointer.
        for partial in [false, true] {
            let replacement: UInt32 = partial ? 0x39000fe3 : 0xd503201f // strb w3,[sp,#3] / nop
            let result = try Self.trace([
                0xd10083ff, 0xf90003e2, replacement, 0xaa1f03e0,
                0x940007fc, 0x910083ff, 0xd65f03c0,
            ], callee: "__swift_project_boxed_opaque_existential_1")
            let site = try #require(result.analysis.callSites[0x1010])
            #expect(site.stackArguments == (partial ? [] : [.argument(0)]))
            #expect(site.stackArgumentWidths == (partial ? [] : [8]))
        }
    }

    @Test func exactTracerStackFilesKeepReinterpretationAndNarrowDeclines() throws {
        let entry = MethodEntryConvention.swiftFunction(scalarArguments: ["v0": 0, "x0": 1, "x2": 2])
        let toInteger = try Self.trace([0xfd0007e0, 0xf94007e0, 0xd65f03c0], entry: entry)
        #expect(toInteger.integer == .unary(.bitPattern(bits: 64), .argument(0)))
        let toFloating = try Self.trace([0xf90007e0, 0xfd4007e0, 0xd65f03c0], entry: entry)
        #expect(toFloating.floating == .unary(.floatFromBits(bits: 64), .argument(1)))
        let narrow = try Self.trace([0xfd0007e0, 0xb9000be2, 0xfd4007e0, 0xd65f03c0], entry: entry)
        #expect(narrow.floating == .unknown)
    }

    @Test func exactTracerQReloadKeepsUnknownLowAndKnownHighWordsSeparate() throws {
        let entry = MethodEntryConvention.swiftValueInstance(seededRegisters: [
            "v8": .aggregate([.unknown, .immediate(23)]), "x10": .immediate(99),
        ])
        // A partial low write must not become a full word after Q reload/spill.
        let prefix: [UInt32] = [0x3d8003e8, 0xb90003ea, 0x3dc003e9, 0x3d800be9]
        let low = try Self.trace(prefix + [0xf94013e0, 0xd65f03c0], entry: entry)
        let high = try Self.trace(prefix + [0xf94017e0, 0xd65f03c0], entry: entry)
        #expect(low.integer == .unknown)
        #expect(high.integer == .immediate(23))
    }
}
