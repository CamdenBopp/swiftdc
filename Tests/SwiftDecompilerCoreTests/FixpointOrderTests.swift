import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let fixpointOrderFixture = "Fixtures/Sample/libFixpointOrder.dylib"

/// The worklist starts with every block in address order. A block that
/// ran before any predecessor had, from an empty state, made entry states
/// grow after they shrank: `unsettled` never converged and claimed
/// nothing. A block no modelled edge reaches must still run, from
/// nothing: `unmodelledLoop` is entered through a branch the CFG cannot
/// follow, and waiting for its predecessors claimed the direct path's 1
/// at the join. The blocks such a block leads to wait for it: `handlerTail`
/// returns what its unreached head sets.
@Test func theTracerVisitsBlocksOnlyOnceTheyAreReachedIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixpointOrderFixture) else { return }
    let handle = try #require(dlopen(fixpointOrderFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    typealias Probe2 = @convention(c) (Int64, Int64) -> Int64
    let recorder = ProbeRecorder(filter: ProbeFilter(events: [ProbeEvent.tracerFixpointCap.id]))
    let functions = try await withStableDependencies {
        try await Probe.recording(recorder) { try await Disassembler().disassemble(path: fixpointOrderFixture) }
    }
    #expect(recorder.records.isEmpty, "\(recorder.records.map { $0.function?.name ?? "" })")
    func probe(_ member: String) throws -> (function: DisassembledFunction, native: Probe2, exit: AbstractValue?) {
        let function = try #require(functions.first { $0.displayName.contains("FixedPoint.\(member)(") }, "\(member)")
        let native = unsafeBitCast(try #require(dlsym(handle, String(function.symbol.dropFirst()))), to: Probe2.self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        let ret = try #require(function.instructions.last { $0.controlFlow == .return })
        return (function, native, analysis.exitValues[ret.address])
    }

    let unsettled = try probe("unsettled")
    let target = Int64(Int(bitPattern: try #require(dlsym(handle, "fixpoint_target"))))
    let slide = Int64(Int(bitPattern: try #require(dlsym(handle, String(unsettled.function.symbol.dropFirst())))))
        - Int64(unsettled.function.startAddress)
    for (first, second): (Int64, Int64) in [(0, 1), (0, 3), (1, 1), (5, 2)] {
        #expect(unsettled.native(first, second) == target)
    }
    guard case .address(let claimed)? = unsettled.exit else {
        Issue.record("unsettled claimed \(String(describing: unsettled.exit))")
        return
    }
    #expect(Int64(claimed) + slide == target)

    let handler = try probe("handlerTail")
    #expect(handler.native(0, 0) == 3)
    #expect(handler.exit == .immediate(3), "handlerTail claimed \(String(describing: handler.exit))")

    let loop = try probe("unmodelledLoop")
    #expect(loop.native(0, 2) == 1)
    #expect(loop.native(1, 2) == 2)
    if let claimed = loop.exit {
        for (first, second): (Int64, Int64) in [(0, 2), (1, 2)] {
            #expect(try ProbeValue.abstractValue(claimed).evaluateInteger(arguments: [UInt64(bitPattern: first), UInt64(bitPattern: second)])
                == UInt64(bitPattern: loop.native(first, second)), "unmodelledLoop claimed \(claimed)")
        }
    }
}
