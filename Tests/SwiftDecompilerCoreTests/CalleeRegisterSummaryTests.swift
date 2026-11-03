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
        #expect(expandingResultBindingsForAssertions(chained).contains("pick(twice("), "\(level): \(chained)")
        #expect(!chained.contains("bump(pick"), "\(level): \(chained)")
    }
}

/// Preservation, not storage, decides a clobber. Assembled the same way,
/// decoded at 0x2000:
///
///     spillsNoReload: str x19, [sp, #-16]!; mov x19, x0; add sp, sp, #16; ret
///     viaRegister:    mov x9, x19; mov x19, x0; mov x19, x9; ret
///     framed:         stp x20, x19, [sp, #-32]!; stp x29, x30, [sp, #16];
///                     add x29, sp, #16; mov x19, x0; mov x20, x1; bl framed;
///                     ldp x29, x30, [sp, #16]; ldp x20, x19, [sp], #32; ret
///     onePath:        str x19, [sp, #-16]!; mov x19, x0; cbz x0, 1f;
///                     ldr x19, [sp]; 1: add sp, sp, #16; ret
///     subFrame:       sub sp, sp, #0x40; stp x29, x30, [sp, #0x30];
///                     str x21, [sp, #0x20]; add x29, sp, #0x30; mov x21, x2;
///                     ldur x21, [x29, #-0x10]; ldp x29, x30, [sp, #0x30];
///                     add sp, sp, #0x40; ret
@Test func calleeSavedClobbersComeFromPreservationNotStorage() throws {
    let words: [UInt32] = [
        0xf81f0ff3, 0xaa0003f3, 0x910043ff, 0xd65f03c0, 0xaa1303e9, 0xaa0003f3,
        0xaa0903f3, 0xd65f03c0, 0xa9be4ff4, 0xa9017bfd, 0x910043fd, 0xaa0003f3,
        0xaa0103f4, 0x97fffffb, 0xa9417bfd, 0xa8c24ff4, 0xd65f03c0, 0xf81f0ff3,
        0xaa0003f3, 0xb4000040, 0xf94003f3, 0x910043ff, 0xd65f03c0, 0xd10103ff,
        0xa9037bfd, 0xf90013f5, 0x9100c3fd, 0xaa0203f5, 0xf85f03b5, 0xa9437bfd,
        0x910103ff, 0xd65f03c0,
    ]
    let layout: [(String, UInt64)] = [
        ("spillsNoReload", 0x0), ("viaRegister", 0x10), ("framed", 0x20), ("onePath", 0x44), ("subFrame", 0x5c),
    ]
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x2000)
    try #require(decoded.count == words.count)
    var clobbers: [String: Set<String>] = [:]
    for (index, (name, offset)) in layout.enumerated() {
        let end = index + 1 < layout.count ? 0x2000 + layout[index + 1].1 : UInt64.max
        let body = decoded.filter { $0.address >= 0x2000 + offset && $0.address < end }.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: name, demangledName: nil, startAddress: 0x2000 + offset,
                                            instructions: body, source: .symbol)
        clobbers[name] = try #require(CalleeRegisterSummary.of(function)).clobberedCalleeSaved
    }
    #expect(clobbers["spillsNoReload"] == ["x19"], "stored but never reloaded")
    #expect(clobbers["viaRegister"] == [], "restored through x9")
    #expect(clobbers["framed"] == [], "the standard frame")
    #expect(clobbers["onePath"] == ["x19"], "reloaded on one path only")
    #expect(clobbers["subFrame"] == [], "saved off sp, reloaded off x29")
}

/// printf's variadic arguments are stack slots in format order (Apple arm64):
/// the format's conversions say how many. `printf("%ld\n", x)` rendered
/// `printf(0x…)`, dropping x; a stale x1 could read as the first value.
@Test func aPrintfCallShowsOneArgumentPerConversionIfPresent() async throws {
    for level in ["O0", "O1"] {
        let fixture = "Fixtures/Sample/libCallReads.\(level).dylib"
        guard let one = try await structured("afterPrint", in: fixture),
              let two = try await structured("printTwo", in: fixture) else { continue }
        let oneCall = one.split(separator: "\n").first { $0.contains("printf(") }.map(String.init) ?? ""
        let twoCall = two.split(separator: "\n").first { $0.contains("printf(") }.map(String.init) ?? ""
        #expect(oneCall.filter { $0 == "," }.count == 1, "\(level): \(oneCall)")
        #expect(twoCall.filter { $0 == "," }.count == 2, "\(level): \(twoCall)")
    }
}

/// A synthetic body decoded at 0x1000, as one function.
private func body(_ words: [UInt32], name: String) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    return DisassembledFunction(
        symbol: name, demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

/// A dynamic allocation hangs below the frame, so a store into it reaches no
/// save, and an epilogue that takes sp back from x29 reloads them:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10
///     mov x19, x0; ldr x8, [x0]; mov x9, sp; sub x9, x9, x8; mov sp, x9
///     str xzr, [x9]
///     mov sp, x29; ldp x20, x19, [sp, #0x10]; ldp x29, x30, [sp], #0x20; ret
///
/// Read as a write of unknown extent through a frame alias, the store
/// forgot every save, and the summary claimed x19, x20 and x29 clobbered:
/// each caller lost its frame pointer across the call. The allocation hangs
/// below the 16 bytes of locals; a store reaches at most its own extent
/// above them (the bound the tracer's `.frameDynamic` uses), never a save.
@Test func aStoreIntoADynamicAllocationKeepsTheSaves() throws {
    let dynamic: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xf9400008, 0x910003e9,
        0xcb080129, 0x9100013f, 0xf900013f, 0x910003bf, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(dynamic, name: "dynamic")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
    // An address a constant above the allocation's base stays inside it:
    // `add x10, x9, #8; str xzr, [x10]`.
    var offset = dynamic
    offset.replaceSubrange(9...9, with: [0x9100212a, 0xf900015f])
    let shifted = try #require(CalleeRegisterSummary.of(try body(offset, name: "offset")))
    #expect(shifted.clobberedCalleeSaved.isEmpty, "\(shifted.clobberedCalleeSaved)")
    // The control: a store through an unbounded frame alias (`str xzr, [x9,
    // x8]`, the allocation indexed by its own size) may reach the saves.
    var indexed = dynamic
    indexed[9] = 0xf828693f
    let control = try #require(CalleeRegisterSummary.of(try body(indexed, name: "indexed")))
    #expect(control.clobberedCalleeSaved.contains("x29"), "\(control.clobberedCalleeSaved)")
}

/// A frame alias reaches a call only through a register the callee can take
/// an input in. One that keeps the calling convention takes the argument
/// registers, x8, x20 and x21: an indirect call (the machine outliner calls
/// its fragments directly), a call through an import stub, or a callee of
/// known arity, which takes exactly its parameters and x8. The alias here is
/// parked in x19, the sp a dynamic allocation restores after the call:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     mov x19, sp; mov x0, sp; <call>; mov x0, x19
///     ldp x20, x19, [sp, #0x10]; ldp x29, x30, [sp], #0x20; ret
///
/// Taken for an argument, it escaped the frame, the call forgot every save,
/// and the summary claimed x19, x20 and x29 clobbered.
@Test func aFrameAliasEscapesOnlyThroughACallsInputs() throws {
    func parked(_ call: UInt32) -> [UInt32] {
        [0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0x910003f3, 0x910003e0, call,
         0xaa1303e0, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0]
    }
    let indirect: UInt32 = 0xd63f0020 // blr x1
    let direct: UInt32 = 0x940003fb // bl 0x2000
    func clobbers(_ call: UInt32, arity: Int? = nil, stub: Bool = false) throws -> Set<String> {
        let function = try body(parked(call), name: "parked")
        return try #require(CalleeRegisterSummary.of(
            function, calleeArity: { _ in arity }, isImportStub: { _ in stub })).clobberedCalleeSaved
    }
    // x0 holds a frame address too, so only a callee that cannot take x0
    // keeps the saves: the indirect and stub calls take it.
    #expect(try clobbers(indirect).contains("x29"))
    #expect(try clobbers(direct, stub: true).contains("x29"))
    // A callee of arity 0 takes no x0: the parked x19 is no input.
    #expect(try clobbers(direct, arity: 0).isEmpty)
    // Arity 1 takes x0, a frame address.
    #expect(try clobbers(direct, arity: 1).contains("x29"))
    // Any callee may return a large struct through x8: a frame address
    // there is an input even at arity 0 (`mov x8, sp`).
    var result = parked(direct)
    result[4] = 0x910003e8
    let function = try body(result, name: "result")
    let summary = try #require(CalleeRegisterSummary.of(function, calleeArity: { _ in 0 }))
    #expect(summary.clobberedCalleeSaved.contains("x29"))
}

/// The same with no frame address in an argument register: an indirect call
/// or an import stub cannot take the x19 alias; an unknown in-image target,
/// possibly an outlined fragment, can.
@Test func aParkedFrameAliasIsNoInputOfACallThatKeepsTheConvention() throws {
    func parked(_ call: UInt32) -> [UInt32] {
        [0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0x910003f3, call,
         0xaa1303e0, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0]
    }
    func clobbers(_ call: UInt32, stub: Bool = false) throws -> Set<String> {
        let function = try body(parked(call), name: "parked")
        return try #require(CalleeRegisterSummary.of(function, isImportStub: { _ in stub })).clobberedCalleeSaved
    }
    #expect(try clobbers(0xd63f0020).isEmpty) // blr x1
    #expect(try clobbers(0x940003fc, stub: true).isEmpty) // bl 0x2000, a stub
    #expect(try clobbers(0x940003fc).contains("x29")) // bl 0x2000, unknown
}

/// A local's address handed to a call reaches that local, below the
/// register save area, not the saves above it, the extent the tracer's
/// `escapedReach` gives a local:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; mov x0, sp; bl 0x2000
///     add sp, sp, #0x10; ldp x20, x19, [sp, #0x10]; ldp x29, x30, [sp], #0x20; ret
///
/// The escape forgot every save, and the summary claimed x19, x20 and x29
/// clobbered: `-Onone` `makeWide` passing its result buffer to its
/// initializer read `return ?` in `wideSum` after it.
@Test func anEscapedLocalReachesNoSaveAboveIt() throws {
    var words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0x910003e0, 0x940003fa,
        0x910043ff, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let local = try #require(CalleeRegisterSummary.of(try body(words, name: "local")))
    #expect(local.clobberedCalleeSaved.isEmpty, "\(local.clobberedCalleeSaved)")
    // The control: x29's own address, the frame record among the saves, may
    // reach every one of them (`mov x0, x29`).
    words[5] = 0x910003a0
    let record = try #require(CalleeRegisterSummary.of(try body(words, name: "record")))
    #expect(record.clobberedCalleeSaved.contains("x29"), "\(record.clobberedCalleeSaved)")
}

/// An address inside a dynamic allocation, handed to a call, reaches that
/// allocation, below the frame's locals, and no save:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; ldr x8, [x0]
///     mov x9, sp; sub x9, x9, x8; mov sp, x9; mov x0, x9; bl 0x2000
///     mov sp, x29; ldp x20, x19, [sp, #0x10]; ldp x29, x30, [sp], #0x20; ret
@Test func anEscapedDynamicAllocationReachesNoSave() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xf9400008, 0x910003e9,
        0xcb080129, 0x9100013f, 0xaa0903e0, 0x940003f6, 0x910003bf, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "belowEscape")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
}

/// The save area is the run of entry values at the top of the frame. An
/// entry value spilled among the locals (`str x21, [sp]`) is no save, and a
/// local above it (`add x0, sp, #8`) is still a local:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x20; mov x19, x0; str x21, [sp]; add x0, sp, #8
///     bl 0x2000; add sp, sp, #0x20; ldp …; ldp …; ret
@Test func aSpilledEntryValueIsNoPartOfTheSaveArea() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10083ff, 0xaa0003f3, 0xf90003f5, 0x910023e0,
        0x940003f9, 0x910083ff, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "spilled")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
}

/// A join that loses a frame alias's exact offset keeps the offsets it may
/// hold: x1 is `mov x1, sp`, a local, on one path and no frame address on the
/// other, so the call reaches at most that local:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; cbz x0, 1f; mov x1, sp
///     1: bl 0x2000; add sp, sp, #0x10; ldp …; ldp …; ret
@Test func aJoinKeepsTheFrameOffsetsAnAliasMayHold() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xb4000040, 0x910003e1,
        0x940003f9, 0x910043ff, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "joined")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
    // A copy of the alias keeps the offsets: `mov x2, x1` before the call.
    var copied = words
    copied.insert(0xaa0103e2, at: 7)
    copied[8] = 0x940003f8 // bl 0x2000 from its new address
    let copy = try #require(CalleeRegisterSummary.of(try body(copied, name: "copied")))
    #expect(copy.clobberedCalleeSaved.isEmpty, "\(copy.clobberedCalleeSaved)")
    // The control: the same join where the other path holds x29's own
    // address, the frame record, may reach every save.
    var record = words
    record[4] = 0x910003a1 // mov x1, x29
    let control = try #require(CalleeRegisterSummary.of(try body(record, name: "record")))
    #expect(control.clobberedCalleeSaved.contains("x29"), "\(control.clobberedCalleeSaved)")
}

/// An escaped address reaches the object it points at, up to the next saved
/// value above it, wherever it lies: a local below the save area, or a byte
/// local the compiler keeps in the padding word `str x28, [sp, #-0x60]!`
/// leaves at sp + 8. Two escapes keep two ranges; one widened interval
/// spanned the saves between them.
///
///     str x28, [sp, #-0x60]!; stp x27, x26, [sp, #0x10]
///     stp x29, x30, [sp, #0x50]; add x29, sp, #0x50; sub sp, sp, #0x10
///     mov x27, x0; mov x0, sp; bl 0x2000; add x0, sp, #0x1f; bl 0x2000
///     add sp, sp, #0x10; ldp x29, x30, [sp, #0x50]; ldp x27, x26, [sp, #0x10]
///     ldr x28, [sp], #0x60; ret
@Test func anEscapedAddressReachesUpToTheNextSave() throws {
    var words: [UInt32] = [
        0xf81a0ffc, 0xa9016bfb, 0xa9057bfd, 0x910143fd, 0xd10043ff, 0xaa0003fb, 0x910003e0,
        0x940003f9, 0x91007fe0, 0x940003f7, 0x910043ff, 0xa9457bfd, 0xa9416bfb, 0xf84607fc, 0xd65f03c0,
    ]
    let gaps = try #require(CalleeRegisterSummary.of(try body(words, name: "gaps")))
    #expect(gaps.clobberedCalleeSaved.isEmpty, "\(gaps.clobberedCalleeSaved)")
    // The control: `add x0, sp, #0x20` is x27's own save slot.
    words[8] = 0x910083e0
    let saved = try #require(CalleeRegisterSummary.of(try body(words, name: "saved")))
    #expect(saved.clobberedCalleeSaved.contains("x29"), "\(saved.clobberedCalleeSaved)")
}

/// A join of two dynamic allocations keeps sp below the higher bound, so a
/// store through it still reaches no save:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; ldr x8, [x0]; cbz x0, 1f
///     mov x9, sp; sub x9, x9, x8; mov sp, x9; b 2f
///     1: sub sp, sp, #0x10; mov x9, sp; sub x9, x9, x8; mov sp, x9
///     2: str xzr, [sp]; mov sp, x29; ldp …; ldp …; ret
@Test func aJoinOfTwoAllocationsKeepsTheirBound() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xf9400008, 0xb40000a0,
        0x910003e9, 0xcb080129, 0x9100013f, 0x14000005, 0xd10043ff, 0x910003e9, 0xcb080129,
        0x9100013f, 0xf90003ff, 0x910003bf, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "twoAllocs")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
}

/// A join that leaves a register a dynamic allocation's address on one path
/// and no frame address on the other keeps that bound for an escape:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; ldr x8, [x0]
///     mov x9, sp; sub x9, x9, x8; mov sp, x9; cbz x0, 1f; mov x1, x9
///     1: bl 0x2000; mov sp, x29; ldp …; ldp …; ret
@Test func aJoinKeepsAnAllocationsBoundForAnEscape() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xf9400008, 0x910003e9,
        0xcb080129, 0x9100013f, 0xb4000040, 0xaa0903e1, 0x940003f5, 0x910003bf, 0xa9414ff4,
        0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "allocOrNot")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
}

/// An address inside a dynamic allocation plus an offset in a register
/// stays inside it: Swift projects a field of the value a buffer holds with
/// `add x1, x9, x10`, x10 a field offset read from metadata. Handed to a
/// call, it reaches that allocation, below the frame's locals, and no save:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; ldr x8, [x0]
///     mov x9, sp; sub x9, x9, x8; mov sp, x9
///     ldrsw x10, [x0, #48]; add x1, x9, x10; blr x2
///     mov sp, x29; ldp …; ldp …; ret
@Test func aFieldOfADynamicAllocationStaysInIt() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xf9400008, 0x910003e9,
        0xcb080129, 0x9100013f, 0xb980300a, 0x8b0a0121, 0xd63f0040, 0x910003bf, 0xa9414ff4,
        0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "field")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
}
