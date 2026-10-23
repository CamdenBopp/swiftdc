import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

/// The pseudo text of every function in `path`, joined, on the array path
/// and on the streaming path.
private func pseudo(_ path: String) async throws -> (array: String, streamed: String) {
    let array = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }.map { $0.renderPseudo() }.joined(separator: "\n")
    let machO = try BinaryLoader.load(path: path)
    let streamed = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreamingRender(machO: machO) { $0.renderPseudo() }
    }.joined(separator: "\n")
    return (array, streamed)
}

/// A call inside a body to another in-image function counted as reading
/// every argument register the body had not written, so a fragment whose
/// only call reaches a function that reads nothing took its caller's
/// registers: `control_save_fragment(arg0, arg1)` (it calls
/// `ordinary_noop`, which is `ret`) and `epilogue_fragment(setup_fragment())`
/// (it tail-branches to `stack_sink`, also `ret`). A call now reads what its
/// target reads, so those take nothing, and `epilogue_helper`, whose only
/// reads are its call to `setup_fragment` (x0 and x1), still takes two.
@Test func aCallReadsOnlyWhatItsInImageTargetReadsIfPresent() async throws {
    let saves = "Fixtures/Sample/libABIEscapedSaves.dylib"
    let preserve = "Fixtures/Sample/libPreserveCalls.dylib"
    guard FileManager.default.fileExists(atPath: saves), FileManager.default.fileExists(atPath: preserve)
    else { return }
    for (path, lines) in [(saves, ["control_save_fragment()"]),
                          (preserve, ["epilogue_fragment()", "epilogue_helper(arg0, arg1)"])] {
        let (array, streamed) = try await pseudo(path)
        for line in lines {
            #expect(array.contains(line), "array path \(path): \(line)")
            #expect(streamed.contains(line), "streaming path \(path): \(line)")
        }
    }
}

/// `mov x0, #5; bl +0x100; ret` with the target an in-image function: the
/// body reads nothing itself, and the call waits on its target with every
/// argument register but x0 (which the body wrote), and x29, still
/// unwritten.
@Test func aCallToAnInImageFunctionWaitsForItsTargetsReads() throws {
    let engine = try #require(CapstoneEngine())
    let words: [UInt32] = [0xd28000a0, 0x94000040, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let function = DisassembledFunction(symbol: "_caller", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
    let summary = try #require(CalleeRegisterSummary.of(function, isFunction: { $0 == 0x1104 }))
    #expect(summary.argumentReads.isEmpty)
    // x29 is unwritten there too.
    #expect(summary.pendingReads == [.init(target: 0x1104, unwritten: 0b1111_1110 | 1 << 29)])
    // Not an in-image function: the call may read every unwritten register.
    let unknown = try #require(CalleeRegisterSummary.of(function))
    #expect(unknown.argumentReads == Set(1...7))
}

/// The reads fixpoint over a hand-built call graph: a call reads its
/// target's reads among the registers unwritten at it, through any depth and
/// around a cycle, and every register of a target with no summary.
@Test func pendingReadsCloseToTheLeastFixpoint() {
    func summary(_ reads: Set<Int>, _ pending: [(UInt64, UInt32)] = []) -> CalleeRegisterSummary {
        CalleeRegisterSummary(argumentReads: reads, pendingReads: pending.map { .init(target: $0.0, unwritten: $0.1) },
                              clobberedCalleeSaved: [])
    }
    var summaries: [UInt64: CalleeRegisterSummary] = [
        0x10: summary([2]),
        0x20: summary([], [(0x10, 0b1111_1110)]),      // reads x2 through 0x10
        0x30: summary([], [(0x20, 0b1111_1011)]),      // wrote x2 before the call
        0x40: summary([0], [(0x30, 0xff), (0x20, 0xff)]),
        0x50: summary([], [(0x99, 0b0000_0011)]),      // 0x99 has no summary
        0x60: summary([1], [(0x70, 0xff)]),            // a cycle with 0x70
        0x70: summary([], [(0x60, 0xff)]),
        0x80: summary([], [(0x90, 0xff)]),             // callees above their callers:
        0x90: summary([], [(0xa0, 0xff)]),             // 0x80 is visited before 0x90
        0xa0: summary([3]),                            // learns x3 from 0xa0
    ]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[0x20]?.argumentReads == [2])
    #expect(summaries[0x30]?.argumentReads == [])
    #expect(summaries[0x40]?.argumentReads == [0, 2])
    #expect(summaries[0x50]?.argumentReads == [0, 1])
    #expect(summaries[0x60]?.argumentReads == [1])
    #expect(summaries[0x70]?.argumentReads == [1])
    #expect(summaries[0x80]?.argumentReads == [3])
    #expect(summaries.values.allSatisfy { $0.pendingReads.isEmpty })
}

/// What counts as using the caller's x29: a memory access through it, or any
/// other read of it, but not the store of it to the stack a prologue makes.
@Test func aFramePointerUseIsAReadOtherThanItsSave() throws {
    let engine = try #require(CapstoneEngine())
    func uses(_ word: UInt32) throws -> Bool {
        let bytes = (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
        let detail = try #require(engine.disassemble(Data(bytes), address: 0x1000).first?.detail)
        return CalleeRegisterSummary.usesFramePointer(detail)
    }
    #expect(try !uses(0xa9bf7bfd))   // stp x29, x30, [sp, #-16]!
    #expect(try !uses(0x910003fd))   // mov x29, sp
    #expect(try !uses(0xa8c17bfd))   // ldp x29, x30, [sp], #16
    #expect(try uses(0xf90003a1))    // str x1, [x29]
    #expect(try uses(0xf85f83a0))    // ldur x0, [x29, #-8]
    #expect(try uses(0xaa1d03e0))    // mov x0, x29
    #expect(try uses(0xf900001d))    // str x29, [x0]
}

/// The flag goes through calls the way reads do: a call with x29 unwritten
/// to a function that uses it, or to one with no summary, uses it too.
@Test func aFramePointerUseReachesThroughCalls() {
    let x29: UInt32 = 1 << 29
    var summaries: [UInt64: CalleeRegisterSummary] = [
        0x10: CalleeRegisterSummary(argumentReads: [], readsFramePointer: true, clobberedCalleeSaved: []),
        0x20: CalleeRegisterSummary(argumentReads: [], pendingReads: [.init(target: 0x10, unwritten: x29)],
                                    clobberedCalleeSaved: []),
        0x30: CalleeRegisterSummary(argumentReads: [], pendingReads: [.init(target: 0x10, unwritten: 0xff)],
                                    clobberedCalleeSaved: []),     // wrote x29 first
        0x40: CalleeRegisterSummary(argumentReads: [], pendingReads: [.init(target: 0x99, unwritten: x29)],
                                    clobberedCalleeSaved: []),     // 0x99 has no summary
    ]
    CalleeRegisterSummary.closeOverReads(&summaries)
    #expect(summaries[0x20]?.readsFramePointer == true)
    #expect(summaries[0x30]?.readsFramePointer == false)
    #expect(summaries[0x40]?.readsFramePointer == true)
    #expect(summaries[0x20]?.effect.readsFramePointer == true)
}
