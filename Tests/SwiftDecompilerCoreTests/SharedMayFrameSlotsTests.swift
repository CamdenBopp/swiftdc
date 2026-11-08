import Testing
@testable import SwiftDecompilerCore

struct SharedMayFrameSlotsTests {
    @Test func mayUnionAndMustIntersectionKeepDifferentJoinRules() {
        var left = MayFrameSlots()
        left.formUnion([-32, -16])
        var right = MayFrameSlots()
        right.formUnion([-24, -16])
        for joined in [left.mayUnion(with: right), right.mayUnion(with: left)] {
            #expect(Set(joined.keys) == [-32, -24, -16])
            #expect(joined.count == 3)
            #expect(joined.componentCount == 3)
            #expect(joined.mayUnion(with: joined) == joined)
        }
        let must = FrameFacts<WordFrameFact<Int>>([-32: 7, -16: 11])
            .intersecting(with: FrameFacts<WordFrameFact<Int>>([-24: 7, -16: 11]))
        #expect(Set(must.keys) == [-16])
        #expect(must[-16] == 11)
    }

    @Test func setBackedPresenceSharesInstallationRemovalAndCopyIsolation() {
        var original = MayFrameSlots()
        original.formUnion([-24, -16, -16])
        var copy = original
        copy.remove(-24)
        copy.insert(-8)
        #expect(Set(original.keys) == [-24, -16])
        #expect(Set(copy.keys) == [-16, -8])
        #expect(original.componentCount == 2 && copy.valueCount == 2)
        copy.clearValueStarts(from: -16, to: -8, removing: .value)
        #expect(Set(copy.keys) == [-8])
        copy.removeAll(keepingCapacity: true)
        #expect(copy.isEmpty && copy.count == 0 && copy.componentCount == 0)
        #expect(MemoryLayout<MayFrameSlotStorage>.stride == MemoryLayout<Set<Int64>>.stride)
        #expect(MemoryLayout<DictionaryFrameFactStorage<TraceFrameFact>>.stride
            == MemoryLayout<[Int64: TraceFrameFact]>.stride)
    }

    @Test func readQueriesUsePresentFactExtentsAndPreserveWrappingPolicy() {
        var slots = MayFrameSlots()
        slots.insert(-16)
        #expect(slots.containsValue(affectedBy: FrameMemoryEffect(.finite(lower: -9, upper: -8), arithmetic: .wrapping)))
        #expect(!slots.containsValue(affectedBy: FrameMemoryEffect(.finite(lower: -8, upper: 0), arithmetic: .wrapping)))
        #expect(slots.containsValue(affectedBy: .legacySelfRead(start: -9, bytes: 1)))
        #expect(!slots.containsValue(affectedBy: .legacySelfRead(start: -8, bytes: 8)))
        let overflowingRead = FrameMemoryEffect.legacySelfRead(start: .max - 3, bytes: 8)
        #expect(slots.containsValue(affectedBy: overflowingRead))
        #expect(!MayFrameSlots().containsValue(affectedBy: overflowingRead))
        var wrapped = MayFrameSlots()
        wrapped.insert(.max - 3)
        let region = FrameMemoryEffect(.finite(lower: 0, upper: .max), arithmetic: .wrapping)
        #expect(!wrapped.containsValue(affectedBy: region))
        #expect(wrapped.containsValue(affectedBy: FrameMemoryEffect(arithmetic: .wrapping, everything: true)))
        slots.forget(FrameMemoryEffect(.finite(lower: -12, upper: -8), arithmetic: .wrapping), removing: .value)
        #expect(slots.isEmpty && slots.valueCount == 0)

        var metadata = FrameFacts<TraceFrameFact>()
        metadata.patch(at: 0, width: .assign(.immediate(8)))
        // This effect traps if queried. An orphan is not a memory snapshot.
        #expect(!metadata.containsValue(affectedBy: .legacyTracerExactWrite(start: .max, bytes: 8)))
        metadata[0] = .unknown
        #expect(metadata.containsValue(affectedBy: FrameMemoryEffect(.finite(lower: 4, upper: 8), arithmetic: .wrapping)))
    }
}
