import Foundation
import Testing
@testable import SwiftDecompilerCore

struct SharedFrameFactStoreTests {
    @Test func fieldPatchesPreserveOrphansAndLosslessSymbolicMetadata() {
        var facts = FrameFacts<TraceFrameFact>()
        let width = AbstractValue.select(condition: .argument(0), whenTrue: .immediate(4), whenFalse: .immediate(8))
        let bank = AbstractValue.select(condition: .argument(1), whenTrue: .immediate(0), whenFalse: .immediate(64))
        facts.patch(at: -16, width: .assign(width), bank: .assign(bank), outgoing: .assign(.frame(-8)))
        #expect(facts.componentCount == 3)
        #expect(facts.valueCount == 0)
        #expect(Array(facts.components.map { $0.field.rawValue }) == [1, 2, 3])
        var lost: [AbstractValue] = []
        facts.forget(FrameMemoryEffect(arithmetic: .wrapping, everything: true),
                     removing: [.value, .width, .outgoing]) { lost.append($0) }
        #expect(lost.isEmpty)
        #expect(facts.componentCount == 3)
        #expect(facts[-16, .width] == width)
        #expect(facts[-16, .bank] == bank)
        facts.patch(at: -16, value: .assign(.unknown), bank: .erase)
        #expect(facts.valueCount == 1)
        #expect(facts.componentCount == 3)
        #expect(facts[-16] == .unknown)
        #expect(facts[-16, .outgoing] == .frame(-8))
        facts.clearValueStarts(from: -16, to: -15, removing: [.value, .width])
        #expect(facts.valueCount == 0)
        #expect(facts.componentCount == 1)
        #expect(facts[-16, .outgoing] == .frame(-8))
        facts.patch(at: -16, value: .assign(.immediate(7)), width: .assign(.immediate(8)), bank: .assign(.immediate(0)))
        #expect(facts.componentCount == 4)
        #expect(facts[-16, .outgoing] == .frame(-8))
        facts.removeComponents(.outgoing)
        #expect(facts.componentCount == 3)
        #expect(facts[-16] == .immediate(7))
    }

    @Test func rawIntersectionIsFieldwiseAndReportsOnlyActualValueLoss() {
        var lhs = FrameFacts<TraceFrameFact>()
        var rhs = FrameFacts<TraceFrameFact>()
        lhs.patch(at: -32, value: .assign(.argument(0)), width: .assign(.immediate(4)),
                  bank: .assign(.immediate(32)), outgoing: .assign(.immediate(7)))
        rhs.patch(at: -32, value: .assign(.argument(0)), width: .assign(.immediate(8)),
                  bank: .assign(.immediate(32)), outgoing: .assign(.immediate(11)))
        let raw = lhs.intersecting(with: rhs)
        #expect(raw[-32] == .argument(0))
        #expect(raw[-32, .width] == nil)
        #expect(raw[-32, .bank] == .immediate(32))
        #expect(raw[-32, .outgoing] == nil)
        #expect(raw.componentCount == 2)
        var lost: [AbstractValue] = []
        lhs.forEachLostValue(comparedWith: raw) { lost.append($0) }
        #expect(lost.isEmpty)
        var conflicts: [Int64] = []
        lhs.forEachMismatch(comparedWith: raw, fields: [.width, .bank]) { offset, _, _ in conflicts.append(offset) }
        #expect(conflicts == [-32])
        rhs[-32] = .frame(-8)
        let disagreed = lhs.intersecting(with: rhs)
        rhs.forEachLostValue(comparedWith: disagreed) { lost.append($0) }
        #expect(lost == [.frame(-8)])
    }

    @Test func anUnseededDiamondCannotRepairAWrongSharedMustIntersection() throws {
        // CBZ's operandValue is absent: branchTakenCondition returns nil, so
        // neither diamond nor switch reconstruction can hide a wrong meet.
        let words: [UInt32] = [0xd10083ff, 0xb4000080, 0xd28000e9, 0xf90007e9,
                               0x14000003, 0xd2800169, 0xf90007e9, 0xf94007e0,
                               0x910083ff, 0xd65f03c0]
        let engine = try #require(CapstoneEngine())
        func analyze(_ words: [UInt32]) throws -> FunctionAnalysis {
            let bytes = words.flatMap { word in
                (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
            }
            let decoded = engine.disassemble(Data(bytes), address: 0x1000)
            try #require(decoded.count == words.count)
            let body = decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }
            let function = DisassembledFunction(symbol: "_shared_frame_raw_meet", demangledName: nil,
                startAddress: 0x1000, instructions: body, source: .address)
            return ValueTracer().analyze(function, entry: nil)
        }
        let mixed = try analyze(words)
        #expect(mixed.exitValues[0x1024] == nil)
        var same = words
        same[5] = 0xd28000e9 // both arms store7; a drop-all meet must fail this control
        let agreed = try analyze(same)
        #expect(agreed.exitValues[0x1024] == .immediate(7))
    }

    @Test func tracerStateProjectionRoundTripsEveryIndependentComponent() throws {
        let width = AbstractValue.select(condition: .argument(0), whenTrue: .immediate(4), whenFalse: .immediate(8))
        let bank = AbstractValue.select(condition: .argument(1), whenTrue: .immediate(0), whenFalse: .immediate(64))
        var original: ValueTracer.State = [
            .x(0): .unknown, .sp: .frame(0), .stack(0): .unknown,
            .stackWidth(-16): width, .stackFile(-16): bank, .outgoing(-16): .frame(-8),
        ]
        #expect(original.count == 6)
        #expect(original.frame.componentCount == 4)
        #expect(original.frame.valueCount == 1)
        #expect(original.values.contains(width))
        #expect(original.values.contains(bank))
        let expected: Set<ValueTracer.Location> = [.x(0), .sp, .stack(0), .stackWidth(-16), .stackFile(-16), .outgoing(-16)]
        #expect(Set(original.keys) == expected)
        #expect(Array(original.values).count == 6)
        var rebuilt: ValueTracer.State = [:]
        for (key, value) in original { rebuilt[key] = value }
        #expect(rebuilt == original)
        let orphan = original.filter { element in
            switch element.key {
            case .stackWidth, .stackFile, .outgoing: return true
            default: return false
            }
        }
        #expect(orphan.count == 3)
        #expect(!orphan.isEmpty)
        #expect(orphan.frame.valueCount == 0)
        #expect(orphan[.stackWidth(-16)] == width)
        rebuilt[.stack(-16)] = .immediate(7)
        #expect(rebuilt.count == 7)
        #expect(original[.stack(-16)] == nil)
        rebuilt[.stack(-16)] = nil
        #expect(rebuilt == original)
        rebuilt[.stack(0)] = nil
        #expect(rebuilt != original)
        #expect(rebuilt.count == 5)
        original.removeAll()
        #expect(original.isEmpty)
        #expect(original.count == 0)
        var keys = original.keys.makeIterator()
        #expect(keys.next() == nil)
    }

    @Test func copiedTraceRowsAreIndependentAndProductionLayoutsStaySpecialized() {
        var original = FrameFacts<TraceFrameFact>()
        original.patch(at: -8, value: .assign(.argument(0)), width: .assign(.immediate(8)),
                       bank: .assign(.immediate(0)), outgoing: .assign(.argument(0)))
        var copied = original
        copied.patch(at: -8, value: .assign(.unknown), width: .assign(.immediate(4)), bank: .erase, outgoing: .erase)
        #expect(original[-8] == .argument(0))
        #expect(original[-8, .width] == .immediate(8))
        #expect(original[-8, .bank] == .immediate(0))
        #expect(original[-8, .outgoing] == .argument(0))
        #expect(original.componentCount == 4)
        #expect(copied[-8] == .unknown)
        #expect(copied.componentCount == 2)
        #expect(MemoryLayout<TraceFrameFact>.stride <= 4 * MemoryLayout<AbstractValue?>.stride)
        #expect(MemoryLayout<WordFrameFact<Preservation.Value>>.stride == MemoryLayout<Preservation.Value?>.stride)
    }
}
