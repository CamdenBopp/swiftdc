import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

struct FrameRegisterFactsTests {
    private static func body(_ words: [UInt32]) throws -> DisassembledFunction {
        let engine = try #require(CapstoneEngine())
        let bytes = words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
        }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        for call in decoded where call.controlFlow == .call {
            try #require(call.branchTarget == 0x3000)
        }
        let instructions = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail,
                callee: .kept($0.controlFlow == .call ? "frame_register_memory_write_helper" : nil))
        }
        return DisassembledFunction(symbol: "_frame_register_core", demangledName: nil,
            startAddress: 0x1000, instructions: instructions, source: .address)
    }

    private static func reversedSuccessors(_ blocks: [BasicBlock]) -> [BasicBlock] {
        blocks.map {
            BasicBlock(startAddress: $0.startAddress, instructions: $0.instructions,
                successors: Array($0.successors.reversed()), switchCases: $0.switchCases)
        }
    }

    @Test func physicalMachineBindingsUseTheOwnerWithoutAbsorbingFlags() {
        let state: ValueTracer.State = [
            .x(91): .frame(-16), .v(77): .unknown, .sp: .frame(0),
            .zero: .immediate(2), .nzcv: .unknown, .otherRegister(9001): .immediate(3),
            .flags: .immediate(4), .flagsWidth: .immediate(32), .contextSlot(8): .unknown,
        ]
        #expect(state.registerFacts.exactCount == 6)
        #expect(state.registerFacts[.zero] == .immediate(2))
        #expect(state.registerFacts[.nzcv] == .unknown)
        #expect(state.registerFacts[.otherRegister(9001)] == .immediate(3))
        #expect(state.registerFacts[.flags] == nil && state.registerFacts[.flagsWidth] == nil)
        #expect(state.count == 9)
        #expect(state.filter { _ in true } == state)
        var raw = Preservation.State(registers: ["raw": .unknown], slots: [:],
            stackAliases: ["sp"], aliasReach: ["orphan": .init()])
        raw.registers["other spelling"] = .stack(-24)
        #expect(raw.registerFacts["raw"] == .unknown)
        #expect(raw.registerFacts["other spelling"] == .stack(-24))
        #expect(!raw.registerFacts.mayAlias("other spelling")) // raw writes stay raw
        #expect(raw.registerFacts.finiteOrigins["orphan"] == .init())
    }

    @Test func sparseOwnerPatchesCopiesAndSelectionsKeepIndependentFields() {
        var facts = PreservationFrameRegisterFacts()
        facts.exactValues = ["x9": .unknown, "arbitrary raw key": .entry("x19")]
        facts.aliasKeys = ["sp"]
        facts.finiteOrigins = ["x9": .init(offsets: [-48]), "orphan": .init()]
        facts.patchExact("x9", .leave)
        #expect(facts["x9"] == .unknown)
        facts.copyPreservation(from: "x9", to: "x9")
        #expect(facts["x9"] == nil) // semantic MOV normalizes unknown
        #expect(!facts.mayAlias("x9"))
        #expect(facts.finiteOrigins["x9"] == .init(offsets: [-48]))
        #expect(facts.finiteOrigins["orphan"] == .init())
        let selected = Array(facts.selected(["x9", "missing", "x9"]))
        #expect(selected.map(\.key) == ["x9", "missing", "x9"])
        #expect(selected.allSatisfy { $0.value == nil })
        #expect(facts.containsSelected(["sp"]) { key, _ in facts.mayAlias(key) })
        #expect(!facts.containsSelected(["orphan"]) { key, _ in facts.mayAlias(key) })
        let original = facts
        facts.patchExact("arbitrary raw key", .erase)
        facts.finiteOrigins["orphan"] = nil
        #expect(original["arbitrary raw key"] == .entry("x19"))
        #expect(original.finiteOrigins["orphan"] == .init())
        facts.reset()
        #expect(facts.exactValues.isEmpty && facts.aliasKeys.isEmpty && facts.finiteOrigins.isEmpty)
    }

    @Test func storageSpecializationsDoNotPadEveryPreservationValue() {
        typealias LegacyColumns = ([String: Preservation.Value], Set<String>, [String: FrameRegisterOrigins])
        #expect(MemoryLayout<TraceFrameRegisterStorage>.stride == MemoryLayout<[ValueTracer.Location: AbstractValue]>.stride)
        #expect(MemoryLayout<PreservationFrameRegisterStorage>.stride == MemoryLayout<LegacyColumns>.stride)
        #expect(MemoryLayout<TraceFrameRegisterFacts>.stride == MemoryLayout<TraceFrameRegisterStorage>.stride)
        #expect(MemoryLayout<PreservationFrameRegisterFacts>.stride == MemoryLayout<PreservationFrameRegisterStorage>.stride)
    }

    @Test func commonExactMeetDeclinesConflictingRegistersInBothAnalyses() throws {
        let words: [UInt32] = [
            0xb4000060, 0xd28000e9, 0x14000002, 0xd2800169, 0xaa0903e0, 0xd65f03c0,
        ] // unseeded cbz; x9=7 or11; mov x0,x9; ret
        let function = try Self.body(words)
        let mixed = ValueTracer().analyze(function, entry: nil)
        #expect(mixed.exitValues[0x1014] == nil)
        var agreed = words
        agreed[3] = 0xd28000e9
        #expect(ValueTracer().analyze(try Self.body(agreed), entry: nil).exitValues[0x1014] == .immediate(7))

        let fragment = try Self.body([
            0xb4000040, 0x14000002, 0xaa1f03f3, 0xd65f03c0,
        ]) // one path preserves x19, one clears it; both keep x23/v11
        let addresses = Set(fragment.instructions.map(\.address))
        let blocks = fragment.basicBlocks()
        for order in [blocks, Self.reversedSuccessors(blocks)] {
            let exits = try #require(Preservation.exitValues(blocks: order, entry: 0x1000, addresses: addresses))
            #expect(exits[0x100c]?["x19"] == nil)
            #expect(exits[0x100c]?["x23"] == .entry("x23"))
            #expect(exits[0x100c]?["v11"] == .entry("v11"))
        }
    }

    @Test func lostRegisterWalkEscapesBeforeALaterTracerCall() throws {
        let words: [UInt32] = [
            0xd10083ff, 0xd28000e9, 0xf90007e9, 0x910023ea,
            0xb4000040, 0x14000002, 0xaa1f03ea, 0xaa1f03e0,
            0x940007f8, 0xf94007e0, 0x910083ff, 0xd65f03c0,
        ] // x10=&local on one predecessor only; it is not a call input
        let lost = ValueTracer().analyze(try Self.body(words), entry: nil)
        #expect((lost.exitValues[0x102c] ?? .unknown) == .unknown)
        var noPointer = words
        noPointer[3] = 0xaa1f03ea
        #expect(ValueTracer().analyze(try Self.body(noPointer), entry: nil).exitValues[0x102c] == .immediate(7))
    }

    @Test func selectedFrameInputPresenceKeepsUnknownTransformEscapes() throws {
        let words: [UInt32] = [
            0xd10083ff, 0xd28000e9, 0xf90007e9, 0x910023ea, 0x8a1f014a,
            0xaa1f03e0, 0x940007fa, 0xf94007e0, 0x910083ff, 0xd65f03c0,
        ] // AND x10,x10,xzr loses a frame-derived input to zero
        let lost = ValueTracer().analyze(try Self.body(words), entry: nil)
        #expect((lost.exitValues[0x1024] ?? .unknown) == .unknown)
        var noRead = words
        noRead[4] = 0xaa1f03ea // MOV x10,xzr has no frame input
        #expect(ValueTracer().analyze(try Self.body(noRead), entry: nil).exitValues[0x1024] == .immediate(7))
    }

    // These raw arrays are authored expectations, not an independent oracle.
    // Assemble/LLVM-check their complete words before any behavioral-red credit.
    private static let copyBodies: [[UInt32]] = [
        [0xd10083ff, 0xd280016c, 0xf9000bec, 0x910023e9, 0xaa0903ea,
         0xf8008553, 0xaa1f03f3, 0xf85f8153, 0xf9400140, 0x910083ff, 0xd65f03c0],
        [0xd10083ff, 0xd280016c, 0xf9000bec, 0x910003e9, 0xaa0903ea,
         0xf8008d53, 0xaa1f03f3, 0xf9400153, 0xf9400540, 0x910083ff, 0xd65f03c0],
        [0xd100c3ff, 0xa900d3f3, 0x910023e9, 0xaa0903ea, 0xaa1f03f3,
         0xaa1f03f4, 0xf9400153, 0xf9400554, 0xd2800160, 0x9100c3ff, 0xd65f03c0],
    ]

    @Test func copiesAndCoordinatePlansFeedRealTracerAndPreservation() throws {
        for words in Self.copyBodies {
            let function = try Self.body(words)
            let exit = try #require(function.instructions.last?.address)
            #expect(ValueTracer().analyze(function).exitValues[exit] == .immediate(11))
            let exits = try #require(Preservation.exitValues(blocks: function.basicBlocks(),
                entry: function.startAddress, addresses: Set(function.instructions.map(\.address))))
            #expect(exits[exit]?["x19"] == .entry("x19"))
            #expect(exits[exit]?["x20"] == .entry("x20"))
            #expect(exits[exit]?["x23"] == .entry("x23"))
            #expect(exits[exit]?["v11"] == .entry("v11"))
        }
    }

    @Test func coordinatePlannerKeepsCheckedAndWrappingQueriesSeparate() {
        #expect(FrameCoordinatePlanner.exactStart(.max, displacement: 1, postIndex: false) == .min)
        #expect(FrameCoordinatePlanner.exactStart(.max, displacement: 1, postIndex: true) == .max)
        #expect(FrameCoordinatePlanner.exactWriteback(.max, delta: 1) == .min)
        #expect(FrameCoordinatePlanner.belowAccess(.below(.max), displacement: 1,
            postIndex: false, writeback: true, trailingImmediate: nil) == nil)
        let post = FrameCoordinatePlanner.belowAccess(.below(.max), displacement: 17,
            postIndex: true, writeback: false, trailingImmediate: 1)
        #expect(post == .init(start: .max, after: .below(.min)))
        let negative = FrameCoordinatePlanner.belowAccess(.below(-32), displacement: -8,
            postIndex: false, writeback: true, trailingImmediate: nil)
        #expect(negative == .init(start: -32, after: .below(-32)))
    }

    @Test func nativeRegisterCopiesAndWritebackMatchAcrossFrontendsIfPresent() async throws {
        let path = "Fixtures/Sample/libFrameRegisterModel.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        let array = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "frame_register_model_")
        }
        let streamed = try await withStableDependencies {
            let image = try BinaryLoader.load(path: path)
            return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let expected: Set<String> = ["_frame_register_model_postindex_copy",
            "_frame_register_model_preindex_copy", "_frame_register_model_pair_copy"]
        for functions in [array, filtered, streamed] {
            // Authored inventory; reconcile with NM and LC_FUNCTION_STARTS
            // independently after fixture construction, before proof credit.
            try #require(functions.count == 3 && Set(functions.map(\.symbol)) == expected)
            for function in functions {
                let symbol = String(function.symbol.dropFirst())
                let native = unsafeBitCast(try #require(dlsym(library, symbol)), to: (@convention(c) () -> UInt64).self)
                #expect(native() == 11)
                let exit = try #require(function.instructions.last?.address)
                #expect(ValueTracer().analyze(function).exitValues[exit] == .immediate(11))
            }
        }
    }
}
