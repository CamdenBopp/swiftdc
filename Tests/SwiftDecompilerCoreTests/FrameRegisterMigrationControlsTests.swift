import Testing
@testable import SwiftDecompilerCore

/// Pin existing observable State contracts before moving the register stores.
/// These are representation controls, not claims about new native defects.
struct FrameRegisterMigrationControlsTests {
    @Test func rawMachineBindingsKeepEveryKeyPayloadAndComponentCount() {
        let expected: [ValueTracer.Location: AbstractValue] = [
            .x(0): .unknown, .v(1): .frame(-16), .sp: .frame(0),
            .zero: .immediate(0), .nzcv: .immediate(1), .otherRegister(-37): .unknown,
            .flags: .immediate(2), .flagsWidth: .immediate(64),
            .stack(-8): .immediate(7), .frameEscaped(-16): .immediate(3),
            .contextSlot(0): .unknown, .result(offset: 0, bytes: 8): .frame(-24),
            .contextEscaped(8): .immediate(1), .calleeContextEscaped: .unknown,
        ]
        var original = ValueTracer.State()
        for (key, value) in expected { original[key] = value }
        #expect(original.count == 14)
        #expect(Dictionary(uniqueKeysWithValues: original.map { ($0.key, $0.value) }) == expected)
        #expect(original.filter { _ in true } == original)
        var changed = original
        changed[.x(0)] = nil
        changed[.otherRegister(-37)] = nil
        changed[.zero] = .immediate(99)
        #expect(changed.count == 12)
        #expect(original[.x(0)] == .unknown)
        #expect(original[.otherRegister(-37)] == .unknown)
        #expect(original[.zero] == .immediate(0))
        let common = original.intersecting(with: changed)
        #expect(common.count == 11)
        #expect(common[.zero] == nil && common[.x(0)] == nil)
        #expect(common[.flagsWidth] == .immediate(64))
        #expect(common[.frameEscaped(-16)] == .immediate(3))
        changed.removeAll()
        #expect(changed.isEmpty && Array(changed).isEmpty)
        #expect(original.count == 14)
    }

    @Test func preservationRawFieldsStayIndependentUntilASemanticSetter() throws {
        let original = Preservation.State(
            registers: ["arbitrary-key": .unknown, "x4": .entry("x19")], slots: [:],
            stackAliases: ["sp", "finite-empty", "alias-only"],
            aliasReach: ["orphan": .init(offsets: [-24]), "finite-empty": .init()])
        #expect(original.registers.count == 2)
        #expect(original.registers["arbitrary-key"] == .unknown)
        #expect(original.stackAliases.contains("sp"))
        #expect(original.value("sp") == .unknown)
        let orphan = try #require(original.frameReach("orphan"))
        #expect(orphan.offsets == [-24])
        #expect(!original.stackAliases.contains("orphan"))
        let empty = try #require(original.frameReach("finite-empty"))
        #expect(empty.offsets.isEmpty && empty.below == nil)
        #expect(original.frameReach("alias-only") == nil)
        var changed = original
        changed.setRegister("arbitrary-key", to: .unknown, mayAliasStack: true)
        changed.setRegister("orphan", to: .entry("x20"))
        #expect(changed.registers["arbitrary-key"] == nil)
        #expect(changed.stackAliases.contains("arbitrary-key"))
        #expect(changed.frameReach("arbitrary-key") == nil)
        #expect(changed.aliasReach["orphan"] == nil)
        #expect(original.registers["arbitrary-key"] == .unknown)
        #expect(original.aliasReach["orphan"] != nil)
    }

    @Test func anEmptyFiniteAliasJoinKeepsItsLegacyWideningToAny() throws {
        let original = Preservation.State(
            registers: [:], slots: [:], stackAliases: ["empty"],
            aliasReach: ["empty": .init(), "orphan": .init(offsets: [-8])])
        let before = try #require(original.frameReach("empty"))
        #expect(before.offsets.isEmpty && before.below == nil)
        let joined = original.merged(with: original)
        #expect(Set(joined.stackAliases) == ["empty"])
        #expect(joined.aliasReach.isEmpty)
        #expect(joined.frameReach("empty") == nil)
        let orphan = try #require(joined.frameReach("orphan"))
        #expect(orphan.offsets.isEmpty && orphan.below == nil)
        #expect(joined != original)
        #expect(original.aliasReach.count == 2)
    }

    @Test func belowRepairPrecedesFiniteAliasDerivation() throws {
        let left = Preservation.State(registers: ["x0": .below(-64)], slots: [:], stackAliases: ["x0"])
        let right = Preservation.State(registers: ["x0": .below(-32)], slots: [:], stackAliases: ["x0"])
        let joined = left.merged(with: right)
        #expect(joined.value("x0") == .below(-32))
        #expect(joined.aliasReach["x0"] == nil)
        let reach = try #require(joined.frameReach("x0"))
        #expect(reach.offsets.isEmpty && reach.below == -32)
        #expect(left.value("x0") == .below(-64))
    }

    @Test func differentSelectedInputsKeepTheirSeparateEscapeTransactions() {
        var state = Preservation.State(
            registers: ["x0": .stack(-48), "x1": .unknown],
            slots: [-32: .entry("x19"), -8: .entry("x20")], stackAliases: ["x0", "x1"])
        state.markEscape(["x0", "x1"])
        #expect(state.stackAddressEscaped)
        #expect(state.escapedRanges == [.init(floor: -48, bound: -32)])
    }
}
