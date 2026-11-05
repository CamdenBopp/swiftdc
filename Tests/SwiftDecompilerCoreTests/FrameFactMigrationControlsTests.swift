import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

struct FrameFactMigrationControlsTests {
    @Test func anExplicitUnknownSlotDoesNotReadUnwrittenCallerBytes() {
        let absent = Preservation.State(registers: [:], slots: [:])
        let present = Preservation.State(registers: [:], slots: [0: .unknown])
        #expect(absent.load(at: 0) == .incoming(0))
        #expect(present.load(at: 0) == .unknown)
        #expect(absent != present)
        #expect(present.merged(with: present).load(at: 0) == .unknown)
        #expect(present.merged(with: absent).load(at: 0) == .incoming(0))
        var noIncoming = absent
        noIncoming.incomingIntact = false
        #expect(noIncoming.load(at: 0) == .unknown)
    }

    @Test func copiedPreservationStatesKeepIndependentFrameFactsAndMustJoins() {
        let original = Preservation.State(registers: [:], slots: [
            -24: .entry("x19"), -8: .entry("x20"), 0: .unknown,
        ])
        var changed = original
        changed.invalidateSlots(at: -23, bytes: 1)
        changed.slots[-8] = .entry("x21")
        #expect(original.load(at: -24) == .entry("x19"))
        #expect(original.load(at: -8) == .entry("x20"))
        #expect(changed.load(at: -24) == .unknown)
        #expect(changed.load(at: -8) == .entry("x21"))
        let joined = original.merged(with: changed)
        #expect(joined.load(at: -24) == .unknown)
        #expect(joined.load(at: -8) == .unknown)
        #expect(joined.load(at: 0) == .unknown)
    }

    @Test func overlappingFrameCopiesUseNativeSourceSnapshotsIfPresent() async throws {
        let path = "Fixtures/Sample/libFrameFactStore.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(handle) }
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path)
        }
        #expect(functions.count == 6)
        for (name, expected): (String, UInt64) in [
            ("forward_overlap", 11), ("backward_overlap", 13), ("partial_overlap", 11),
        ] {
            let symbol = "frame_fact_" + name
            let pointer = try #require(dlsym(handle, symbol))
            let native = unsafeBitCast(pointer, to: (@convention(c) () -> UInt64).self)
            #expect(native() == expected)
            let function = try #require(functions.first { $0.symbol == "_" + symbol })
            let analysis = ValueTracer().analyze(function)
            let exit = try #require(function.instructions.last?.address)
            #expect(analysis.exitValues[exit] == .immediate(expected))
        }
    }

    @Test func disagreedWidthAndBankJoinsRetainTheirDeclineIfPresent() async throws {
        let path = "Fixtures/Sample/libFrameFactStore.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(handle) }
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path)
        }
        for name in ["width_join", "bank_join"] {
            let symbol = "frame_fact_" + name
            let pointer = try #require(dlsym(handle, symbol))
            let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64) -> UInt64).self)
            for input: UInt64 in [0, 1, .max] { #expect(native(input) == 7) }
            let function = try #require(functions.first { $0.symbol == "_" + symbol })
            let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
            let exit = try #require(function.instructions.last?.address)
            #expect((analysis.exitValues[exit] ?? .unknown) == .unknown)
        }
    }

    @Test func aNonzeroStateBudgetCountsEveryFrameComponentIfPresent() async throws {
        let path = "Fixtures/Sample/libFrameFactStore.dylib"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path)
        }
        let function = try #require(functions.first { $0.symbol == "_frame_fact_budget" })
        let exit = try #require(function.instructions.last?.address)
        var tracer = ValueTracer()
        tracer.stateFactBudget = 10 // entry2 + exit8 legacy components
        let acceptedRecorder = ProbeRecorder()
        let accepted = Probe.recording(acceptedRecorder) { tracer.analyze(function) }
        #expect(accepted.exitValues[exit] == .immediate(7))
        #expect(acceptedRecorder.count(of: .tracerStateBudget) == 0)
        tracer.stateFactBudget = 9
        let refusedRecorder = ProbeRecorder()
        let refused = Probe.recording(refusedRecorder) { tracer.analyze(function) }
        #expect(refused.exitValues.isEmpty && refused.callSites.isEmpty)
        #expect(refusedRecorder.count(of: .tracerStateBudget) == 1)
    }

}
