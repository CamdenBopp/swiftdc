import Foundation
import Testing
@testable import SwiftDecompilerCore

/// What a callee's body proves about the registers a call to it reads and
/// clobbers. Assembled with `xcrun clang -arch arm64 -c`, read back with
/// `llvm-objdump -d`, decoded at 0x1000:
///
///     noargs:   adrp x8, …; ldr x0, [x8]; add x0, x0, #1; ret
///     reads02:  sub x0, x2, x0; ret
///     branchy:  cbz x0, 1f; mov x1, #5; 1: add x0, x1, #1; ret
///     fragment: add x20, sp, #8; ret          (an outliner fragment)
///     saver:    stp x19, x30, [sp, #-16]!; mov x19, x0; mov x0, x19;
///               ldp x19, x30, [sp], #16; ret
///     tailcall: mov x9, #1; b noargs
///     caller:   mov x20, x0; bl fragment; mov x0, x20; ret
private let summaryWords: [UInt32] = [
    0x90000008, 0xf9400100, 0x91000400, 0xd65f03c0, 0xcb000040, 0xd65f03c0,
    0xb4000040, 0xd28000a1, 0x91000420, 0xd65f03c0, 0x910023f4, 0xd65f03c0,
    0xa9bf7bf3, 0xaa0003f3, 0xaa1303e0, 0xa8c17bf3, 0xd65f03c0, 0xd2800029,
    0x17ffffee, 0xaa0003f4, 0x97fffff6, 0xaa1403e0, 0xd65f03c0,
]

private let starts: [(name: String, offset: UInt64)] = [
    ("noargs", 0x0), ("reads02", 0x10), ("branchy", 0x18), ("fragment", 0x28),
    ("saver", 0x30), ("tailcall", 0x44), ("caller", 0x4c),
]

private func shapes() throws -> [String: DisassembledFunction] {
    let engine = try #require(CapstoneEngine())
    let bytes = summaryWords.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == summaryWords.count)
    var functions: [String: DisassembledFunction] = [:]
    for (index, start) in starts.enumerated() {
        let end = index + 1 < starts.count ? 0x1000 + starts[index + 1].offset : UInt64.max
        let body = decoded.filter { $0.address >= 0x1000 + start.offset && $0.address < end }.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        functions[start.name] = DisassembledFunction(
            symbol: start.name, demangledName: nil, startAddress: 0x1000 + start.offset,
            instructions: body, source: .symbol)
    }
    return functions
}

@Test func calleeSummaryReadsArgumentsFromTheBody() throws {
    let functions = try shapes()
    func summary(_ name: String) throws -> CalleeRegisterSummary {
        let function = try #require(functions[name])
        return try #require(CalleeRegisterSummary.of(function))
    }
    #expect(try summary("noargs").argumentReads == [])
    #expect(try summary("noargs").argumentCount == 0)
    #expect(try summary("reads02").argumentReads == [0, 2])
    #expect(try summary("reads02").argumentCount == 3)
    // x1 is written before its read on one path only: still an argument.
    #expect(try summary("branchy").argumentReads == [0, 1])
    // A tail call may forward any argument register.
    #expect(try summary("tailcall").argumentReads == Set(0...7))
    // A fragment that rewrites x20 without saving it clobbers it; a function
    // that spills x19 first does not.
    #expect(try summary("fragment").clobberedCalleeSaved == ["x20"])
    #expect(try summary("saver").clobberedCalleeSaved == [])
}

@Test func aCallToAFragmentForgetsTheCalleeSavedRegistersItWrites() throws {
    let functions = try shapes()
    let caller = try #require(functions["caller"])
    let ret = try #require(caller.instructions.last)
    // Without the summary, x20 survives the call and arg0 comes back out.
    let blind = ValueTracer().analyze(caller, entry: .swiftInstance(scalarArguments: ["x0": 0]))
    #expect(blind.exitValues[ret.address] == .argument(0))
    var tracer = ValueTracer()
    tracer.calleeClobbers[0x1028] = ["x20"]
    let informed = tracer.analyze(caller, entry: .swiftInstance(scalarArguments: ["x0": 0]))
    #expect(informed.exitValues[ret.address] != .argument(0))
}

private func structured(_ filter: String, in fixture: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: fixture) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: filter)
    }
    return functions.map { $0.renderStructured() }.joined(separator: "\n")
}

/// `Hasher._combine(Swift.UInt) -> ()` returns nothing; x0 after it is not a
/// value. Every synthesized `hashValue` rendered
/// `Swift.Hasher._finalize(Swift.Hasher._combine(0))`.
@Test func aVoidCalleesResultFlowsNowhereIfPresent() async throws {
    guard let text = try await structured("ReconError : Swift.Hashable", in: "Fixtures/Sample/libReconstruction.opt.dylib")
    else { return }
    #expect(text.contains("Swift.Hasher._combine("), Comment(rawValue: text))
    #expect(!text.contains("(Swift.Hasher._combine("), Comment(rawValue: text))
}

/// A C callee takes what its body reads: `bump(void)` after `printf` rendered
/// `bump(printf(…))`. And a call the next one does not take still prints: at
/// -O0 `pick(twice(x), 7, x) + bump()` lost `pick` and `twice` entirely once
/// `bump` stopped taking the stale x0, because consumption was read from the
/// raw registers rather than the rendered arguments.
@Test func aCalleeWithoutASignatureTakesWhatItsBodyReadsIfPresent() async throws {
    for level in ["O0", "O1"] {
        let fixture = "Fixtures/Sample/libCallReads.\(level).dylib"
        guard let printed = try await structured("afterPrint", in: fixture),
              let chained = try await structured("chained", in: fixture) else { continue }
        #expect(printed.contains("bump()"), "\(level): \(printed)")
        #expect(!printed.contains("bump(printf"), "\(level): \(printed)")
        #expect(printed.contains("printf("), "\(level): \(printed)")
        #expect(chained.contains("pick(twice("), "\(level): \(chained)")
        #expect(!chained.contains("bump(pick"), "\(level): \(chained)")
    }
}
