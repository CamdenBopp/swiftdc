import Testing
@testable import SwiftDecompilerCore

/// Observable controls run against the pre-migration implementation first.
/// These protect state identity and evidence timing, not mathematical range
/// normalization or new claims about accepted machine-code addresses.
struct FrameReachMigrationControlsTests {
    @Test func rawMarkerPayloadsSurviveProjectionCopiesIntersectionAndReset() {
        let original: ValueTracer.State = [
            .frameEscaped(-48): .immediate(9),
            .frameBelow(-64): .unknown,
            .frameEscapedAll: .immediate(7),
            .frameDynamic(-80): .immediate(3),
            .contextEscaped(8): .immediate(2),
            .calleeContextEscaped: .unknown,
            .stack(-16): .immediate(11),
            .x(0): .immediate(13),
        ]
        #expect(original.count == 8)
        let projected = Dictionary(uniqueKeysWithValues: original.map { ($0.key, $0.value) })
        #expect(projected.count == 8)
        #expect(projected[.frameBelow(-64)] == .unknown)
        #expect(projected[.frameDynamic(-80)] == .immediate(3))
        #expect(original.filter { _ in true } == original)
        var changed = original
        changed[.frameEscaped(-48)] = .immediate(99)
        changed[.frameDynamic(-96)] = .unknown
        let common = original.intersecting(with: changed)
        #expect(common.count == 7)
        #expect(common[.frameEscaped(-48)] == nil)
        #expect(common[.frameBelow(-64)] == .unknown)
        #expect(common[.frameEscapedAll] == .immediate(7))
        #expect(original[.frameEscaped(-48)] == .immediate(9))
        changed.frame.removeAll()
        #expect(changed.count == 8)
        #expect(changed[.frameDynamic(-96)] == .unknown)
        changed.removeAll()
        #expect(changed.isEmpty && Array(changed).isEmpty)
        #expect(original.count == 8)
    }

    @Test func preservationFreezesLegacyDynamicBoundsBeforeEntrySavesChange() {
        var state = Preservation.State(
            registers: ["x0": .below(-32)],
            slots: [-32: .entry("x19"), -8: .entry("x20")])
        state.markEscape(["x0"])
        #expect(state.escapedRanges == [.init(floor: .min, bound: -32)])
        state.slots[-32] = nil
        state.slots[-40] = .entry("x21")
        state.invalidateSlotsForUnknownWrite(throughStackAlias: false)
        #expect(state.slots[-40] == nil)
        #expect(state.slots[-8] == .entry("x20"))
        #expect(state.escapedRanges == [.init(floor: .min, bound: -32)])
        #expect(!state.stackAddressEscaped)
    }

    @Test func anUnboundedAlternativeDoesNotCommitPartiallyResolvedRanges() {
        let prior: Set<Preservation.EscapeRange> = [.init(floor: -96, bound: -80)]
        var state = Preservation.State(
            registers: [:], slots: [-32: .entry("x19"), -8: .entry("x20")],
            escapedRanges: prior,
            aliasReach: ["x0": .init(offsets: [-48, -31])])
        state.markEscape(["x0"])
        #expect(state.stackAddressEscaped)
        #expect(state.escapedRanges == prior)
    }

    @Test func selectedDefaultOriginsRemainAnyWhileFiniteEmptyRemainsEmpty() {
        let original = Preservation.State(
            registers: ["x2": .entry("x19")], slots: [-32: .entry("x20")],
            aliasReach: ["x0": .init()])
        var finiteEmpty = original
        finiteEmpty.markEscape(["x0"])
        #expect(!finiteEmpty.stackAddressEscaped && finiteEmpty.escapedRanges.isEmpty)
        var absent = original
        absent.markEscape(["x1"])
        #expect(absent.stackAddressEscaped)
        var selectedEntry = original
        selectedEntry.markEscape(["x2"])
        #expect(selectedEntry.stackAddressEscaped)
        #expect(!original.stackAddressEscaped)
    }

    @Test func joinsRetainFiniteRangesBesideWholeFrameAndCopiesStayIndependent() {
        var left = Preservation.State(
            registers: [:], slots: [-16: .entry("x19")],
            escapedRanges: [.init(floor: -80, bound: -64)])
        let right = Preservation.State(
            registers: [:], slots: [-16: .entry("x19")],
            stackAddressEscaped: true,
            escapedRanges: [.init(floor: -48, bound: -32)],
            incomingIntact: false)
        let joined = left.merged(with: right)
        #expect(joined.stackAddressEscaped && !joined.incomingIntact)
        #expect(joined.escapedRanges == [
            .init(floor: -80, bound: -64), .init(floor: -48, bound: -32),
        ])
        left.escapedRanges.insert(.init(floor: -128, bound: -112))
        #expect(joined.escapedRanges.count == 2)
        #expect(!left.stackAddressEscaped && left.incomingIntact)
    }

    @Test func belowBoundsAndCallerOwnedQueriesDoNotPolluteDurableEvidence() {
        var state = Preservation.State(
            registers: ["x0": .below(-64)],
            slots: [-80: .entry("x19"), -32: .entry("x20"), 0: .entry("x21")])
        state.markEscape(["x0"])
        let frozen: Set<Preservation.EscapeRange> = [.init(floor: .min, bound: -64)]
        #expect(state.escapedRanges == frozen && !state.stackAddressEscaped)
        state.invalidateSlotsForUnknownWrite(throughStackAlias: false)
        #expect(state.slots[-80] == nil && state.slots[0] == nil)
        #expect(state.slots[-32] == .entry("x20"))
        #expect(state.escapedRanges == frozen && !state.stackAddressEscaped)
        #expect(!state.incomingIntact)
        var noQualifyingSave = Preservation.State(
            registers: ["x0": .below(-16)], slots: [-32: .entry("x20")])
        noQualifyingSave.markEscape(["x0"])
        #expect(noQualifyingSave.stackAddressEscaped && noQualifyingSave.escapedRanges.isEmpty)
    }
}
