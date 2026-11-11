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
    #expect(try summary("tailcall").argumentReads == RegisterSet(0...7))
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

/// A local's address gives a coordinate, not a proof of its allocation's
/// extent. A register spill above it cannot bound an unknown callee's writes:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; mov x0, sp; bl 0x2000
///     add sp, sp, #0x10; ldp x20, x19, [sp, #0x10]; ldp x29, x30, [sp], #0x20; ret
///
/// Recovering the saves needs a callee footprint or independent ownership
/// evidence; their current values alone do not supply that evidence.
@Test func anEscapedLocalHasNoObjectBoundFromRegisterSaves() throws {
    var words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0x910003e0, 0x940003fa,
        0x910043ff, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let local = try #require(CalleeRegisterSummary.of(try body(words, name: "local")))
    // The frame record and the prologue's saves are no local's: the local's
    // pointer reaches neither.
    #expect(local.clobberedCalleeSaved.isEmpty, "\(local.clobberedCalleeSaved)")
    // The control: x29's own address, the frame record among the saves, may
    // reach every one of them (`mov x0, x29`).
    words[5] = 0x910003a0
    let record = try #require(CalleeRegisterSummary.of(try body(words, name: "record")))
    #expect(record.clobberedCalleeSaved.contains("x29"), "\(record.clobberedCalleeSaved)")
}

/// The dynamic address retains its legacy MAY escape policy, but its size
/// has no proven sign or bound. It supplies no positive call-time stack
/// boundary protecting the saved entry values:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; ldr x8, [x0]
///     mov x9, sp; sub x9, x9, x8; mov sp, x9; mov x0, x9; bl 0x2000
///     mov sp, x29; ldp x20, x19, [sp, #0x10]; ldp x29, x30, [sp], #0x20; ret
@Test func anUnboundedCallTimeStackCannotProtectSaves() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xf9400008, 0x910003e9,
        0xcb080129, 0x9100013f, 0xaa0903e0, 0x940003f6, 0x910003bf, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "belowEscape")))
    #expect(summary.clobberedCalleeSaved == ["x19", "x20", "x29"], "\(summary.clobberedCalleeSaved)")
}

/// An entry value spilled among locals (`str x21, [sp]`) supplies no
/// allocation boundary for a pointer above it (`add x0, sp, #8`). The frame
/// record above them is no local's, so that pointer cannot reach it:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x20; mov x19, x0; str x21, [sp]; add x0, sp, #8
///     bl 0x2000; add sp, sp, #0x20; ldp …; ldp …; ret
@Test func aSpilledEntryValueDoesNotProveLocalOwnership() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10083ff, 0xaa0003f3, 0xf90003f5, 0x910023e0,
        0x940003f9, 0x910083ff, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "spilled")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
}

/// A join that loses a frame alias's exact offset keeps the offsets it may
/// hold: x1 is `mov x1, sp`, a local, on one path and no frame address on the
/// other. That possible coordinate must still escape without an object bound:
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

/// A pointer in the saved registers' padding, bytes the prologue never
/// stored, is a local's: LLVM places small locals there (GoodLinks passes
/// `x29 - 0x48` as an inout x20 and stores a flag byte at `x29 - 0x41`). Like
/// a pointer to a local below the save area, it reaches none of the saves:
/// the save area, like the frame record, is no object of this frame. A
/// pointer into a word the prologue stored is no local's and reaches them.
///
///     str x28, [sp, #-0x60]!; stp x27, x26, [sp, #0x10]
///     stp x29, x30, [sp, #0x50]; add x29, sp, #0x50; sub sp, sp, #0x10
///     mov x27, x0; mov x0, sp; bl 0x2000; add x0, sp, #0x1f; bl 0x2000
///     add sp, sp, #0x10; ldp x29, x30, [sp, #0x50]; ldp x27, x26, [sp, #0x10]
///     ldr x28, [sp], #0x60; ret
@Test func escapedCoordinatesDoNotBoundObjectsAtTheNextSave() throws {
    var words: [UInt32] = [
        0xf81a0ffc, 0xa9016bfb, 0xa9057bfd, 0x910143fd, 0xd10043ff, 0xaa0003fb, 0x910003e0,
        0x940003f9, 0x91007fe0, 0x940003f7, 0x910043ff, 0xa9457bfd, 0xa9416bfb, 0xf84607fc, 0xd65f03c0,
    ]
    let gaps = try #require(CalleeRegisterSummary.of(try body(words, name: "gaps")))
    // `add x0, sp, #0x1f` lies in the padding between x28's save and
    // x27's: a local's address, so it reaches none of the saves.
    #expect(gaps.clobberedCalleeSaved.isEmpty, "\(gaps.clobberedCalleeSaved)")
    // Both calls given only the local (`mov x0, sp`): below the save area,
    // it reaches none of it.
    var local = words
    local[8] = 0x910003e0
    let below = try #require(CalleeRegisterSummary.of(try body(local, name: "below")))
    #expect(below.clobberedCalleeSaved.isEmpty, "\(below.clobberedCalleeSaved)")
    // `add x0, sp, #0x20` is x27's own save slot, inside the save area: it
    // may reach the saves above it and the record.
    words[8] = 0x910083e0
    let saved = try #require(CalleeRegisterSummary.of(try body(words, name: "saved")))
    #expect(saved.clobberedCalleeSaved.isSuperset(of: ["x27", "x29"]), "\(saved.clobberedCalleeSaved)")
    // The control: `add x0, sp, #0x60` is the frame record's own address.
    words[8] = 0x910183e0
    let record = try #require(CalleeRegisterSummary.of(try body(words, name: "record")))
    #expect(record.clobberedCalleeSaved.contains("x29"), "\(record.clobberedCalleeSaved)")
    // `add x0, sp, #0x70` is entry sp, above the record: the prologue stored
    // nothing there, but no byte at or above the record is padding.
    words[8] = 0x9101c3e0
    let entry = try #require(CalleeRegisterSummary.of(try body(words, name: "entry")))
    #expect(entry.clobberedCalleeSaved.contains("x29"), "\(entry.clobberedCalleeSaved)")
}

/// A local in the save area's padding that the body writes before passing its
/// address on (GoodLinks: `sturb w25, [x29, #-0x41]`, then `sub x1, x29,
/// #0x41` to a call) is still padding: only the prologue's stores, before x29
/// holds the frame address, make a byte of the save area.
///
///     str x28, [sp, #-0x60]!; stp x27, x26, [sp, #0x10]
///     stp x29, x30, [sp, #0x50]; add x29, sp, #0x50; sub sp, sp, #0x10
///     mov x27, x0; sturb wzr, [x29, #-0x41]; sub x0, x29, #0x41; bl 0x2000
///     add sp, sp, #0x10; ldp x29, x30, [sp, #0x50]; ldp x27, x26, [sp, #0x10]
///     ldr x28, [sp], #0x60; ret
@Test func aBodyStoreDoesNotMakePaddingASave() throws {
    let words: [UInt32] = [
        0xf81a0ffc, 0xa9016bfb, 0xa9057bfd, 0x910143fd, 0xd10043ff, 0xaa0003fb, 0x381bf3bf,
        0xd10107a0, 0x940003f8, 0x910043ff, 0xa9457bfd, 0xa9416bfb, 0xf84607fc, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "flag")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
}

/// A byte loaded through the frame pointer is data, not a frame address:
/// storing it to a local escapes nothing (GoodLinks copies a Bool stack
/// argument, `ldrb w15, [x29, #0x58]; strb w15, [sp, #0x130]`). Its
/// destination was a possible frame alias, which made the store an escape of
/// the whole frame, so the callee read as clobbering x19, x20 and x29.
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; ldrb w9, [x29, #0x20]; strb w9, [sp]
///     mov x0, sp; bl 0x2000; add sp, sp, #0x10; ldp x20, x19, [sp, #0x10]
///     ldp x29, x30, [sp], #0x20; ret
@Test func aNarrowLoadThroughTheFrameIsNoFrameAddress() throws {
    var words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0x394083a9, 0x390003e9,
        0x910003e0, 0x940003f8, 0x910043ff, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "flag")))
    #expect(summary.clobberedCalleeSaved.isEmpty, "\(summary.clobberedCalleeSaved)")
    // The control: a byte store of x29 itself (`strb w29, [sp]`) still
    // escapes the frame.
    words[6] = 0x390003fd
    let control = try #require(CalleeRegisterSummary.of(try body(words, name: "fp")))
    #expect(control.clobberedCalleeSaved.contains("x29"), "\(control.clobberedCalleeSaved)")
    // A post-indexed load's base is still an address: `mov x1, sp;
    // ldrb w9, [x1], #1; str x1, [x19]` stores a frame address to memory.
    words[5] = 0x910003e1; words[6] = 0x38401429; words[7] = 0xf9000261
    let walked = try #require(CalleeRegisterSummary.of(try body(words, name: "walked")))
    #expect(walked.clobberedCalleeSaved.contains("x29"), "\(walked.clobberedCalleeSaved)")
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

/// A join retains the legacy dynamic MAY origin, but that origin does not
/// prove where the unbounded call-time stack pointer lies:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; ldr x8, [x0]
///     mov x9, sp; sub x9, x9, x8; mov sp, x9; cbz x0, 1f; mov x1, x9
///     1: bl 0x2000; mov sp, x29; ldp …; ldp …; ret
@Test func aDynamicJoinDoesNotProveTheCallTimeStackBoundary() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xf9400008, 0x910003e9,
        0xcb080129, 0x9100013f, 0xb4000040, 0xaa0903e1, 0x940003f5, 0x910003bf, 0xa9414ff4,
        0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "allocOrNot")))
    #expect(summary.clobberedCalleeSaved == ["x19", "x20", "x29"], "\(summary.clobberedCalleeSaved)")
}

/// A projected field retains a dynamic MAY origin. The untyped size and
/// field offset cannot prove that a later callee's own stack allocation
/// misses the saved registers:
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; mov x19, x0; ldr x8, [x0]
///     mov x9, sp; sub x9, x9, x8; mov sp, x9
///     ldrsw x10, [x0, #48]; add x1, x9, x10; blr x2
///     mov sp, x29; ldp …; ldp …; ret
@Test func anUnprovedDynamicFieldCallCannotProtectSaves() throws {
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xaa0003f3, 0xf9400008, 0x910003e9,
        0xcb080129, 0x9100013f, 0xb980300a, 0x8b0a0121, 0xd63f0040, 0x910003bf, 0xa9414ff4,
        0xa8c27bfd, 0xd65f03c0,
    ]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "field")))
    #expect(summary.clobberedCalleeSaved == ["x19", "x20", "x29"], "\(summary.clobberedCalleeSaved)")
}

/// Where the incoming x20 lives decides whether a body reads it, not
/// whether x20 is ever named. Assembled with `xcrun clang -arch arm64 -c`:
///
///     overwrite: stp x20, x19, [sp, #-0x20]!; stp x29, x30, [sp, #0x10]
///                add x29, sp, #0x10; mov x20, x0; ldr x0, [x20]; bl far
///                ldp x29, x30, [sp, #0x10]; ldp x20, x19, [sp], #0x20; ret
///     spill:     sub sp, sp, #0x20; stp x29, x30, [sp, #0x10]
///                add x29, sp, #0x10; str x20, [sp, #0x8]; mov x20, x0
///                ldr x20, [sp, #0x8]; bl far
///                ldp x29, x30, [sp, #0x10]; add sp, sp, #0x20; ret
///     other:     (as spill, but) stur x20, [x29, #-0x8]; mov x20, x0
///                ldr x0, [sp, #0x8]; bl far
///     join:      cbz x0, 1f; mov x20, x0; 1: ldr x1, [x20]; ret
private let overwriteWords: [UInt32] = [
    0xa9be4ff4, 0xa9017bfd, 0x910043fd, 0xaa0003f4, 0xf9400280, 0x940000fb, 0xa9417bfd, 0xa8c24ff4, 0xd65f03c0,
]
private let spillWords: [UInt32] = [
    0xd10083ff, 0xa9017bfd, 0x910043fd, 0xf90007f4, 0xaa0003f4, 0xf94007f4, 0x940000be, 0xa9417bfd, 0x910083ff,
    0xd65f03c0,
]
private let otherRegisterWords: [UInt32] = [
    0xd10083ff, 0xa9017bfd, 0x910043fd, 0xf81f83b4, 0xaa0003f4, 0xf94007e0, 0x94000082, 0xa9417bfd, 0x910083ff,
    0xd65f03c0,
]
private let joinWords: [UInt32] = [0xb4000040, 0xaa0003f4, 0xf9400281, 0xd65f03c0]

private func callTarget(_ function: DisassembledFunction) throws -> UInt64 {
    try #require(function.instructions.first { $0.controlFlow == .call }?.branchTarget)
}

@Test func aBodyThatOverwritesX20BeforeUsingItReadsNoSelf() throws {
    let function = try body(overwriteWords, name: "overwrite")
    let target = try callTarget(function)
    // x20 is the body's own x0 at the load and the call; the save and the
    // epilogue's restore only move the caller's value.
    let stub = try #require(CalleeRegisterSummary.of(function, isImportStub: { $0 == target }))
    #expect(!stub.readsSelfRegister)
    // A call to an in-image function hands it no incoming x20.
    let inImage = try #require(CalleeRegisterSummary.of(function, isFunction: { $0 == target }))
    #expect(!inImage.readsSelfRegister)
    #expect(inImage.pendingReads.allSatisfy { $0.unwritten & (1 << 20) == 0 })
}

@Test func aSpilledSelfReloadedIntoX20IsRead() throws {
    // -Onone: `str x20, [sp, #8]; …; ldr x20, [sp, #8]; bl Animal.init`.
    let function = try body(spillWords, name: "spill")
    let target = try callTarget(function)
    let stub = try #require(CalleeRegisterSummary.of(function, isImportStub: { $0 == target }))
    #expect(stub.readsSelfRegister)
    // An in-image callee is asked: the reload is back in x20 at the call.
    let inImage = try #require(CalleeRegisterSummary.of(function, isFunction: { $0 == target }))
    #expect(!inImage.readsSelfRegister)
    #expect(inImage.pendingReads.contains { $0.target == target && $0.unwritten & (1 << 20) != 0 })
}

@Test func aSpilledSelfReloadedIntoAnArgumentIsRead() throws {
    // Spilled through x29, reloaded through sp into x0: the same slot.
    let function = try body(otherRegisterWords, name: "other")
    let target = try callTarget(function)
    let takesIt = try #require(CalleeRegisterSummary.of(function, calleeArity: { $0 == target ? 1 : nil }))
    #expect(takesIt.readsSelfRegister)
    // A callee that takes no argument never sees x0.
    let takesNothing = try #require(CalleeRegisterSummary.of(function, calleeArity: { $0 == target ? 0 : nil }))
    #expect(!takesNothing.readsSelfRegister)
}

@Test func x20OverwrittenOnOnePathStillHoldsSelfOnTheOther() throws {
    let function = try body(joinWords, name: "join")
    #expect(try #require(CalleeRegisterSummary.of(function)).readsSelfRegister)
}

/// -Onone `Animal.init` hands back the self it was given:
/// `mov x0, x20; mov x20, x1; ret`.
@Test func aReturnedSelfIsRead() throws {
    let function = try body([0xaa1403e0, 0xaa0103f4, 0xd65f03c0], name: "returnsSelf")
    #expect(try #require(CalleeRegisterSummary.of(function)).readsSelfRegister)
}

/// The -Onone initializers spill self (`str x20, [sp, #8]; ldr x20,
/// [sp, #8]; bl Animal.init`), and `Animal.init` returns it: both keep it.
@Test func anInitializerThatSpillsSelfKeepsItIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "__allocating_init")
    }
    for type in ["Dog", "Animal"] {
        let function = try #require(functions.first { $0.displayName.hasPrefix("Reconstruction.\(type).__allocating_init(") })
        let allocation = try #require(function.instructions.first { $0.callee == "swift_allocObject" })
        let binding = try #require(allocation.binding)
        #expect(binding.expression == "swift_allocObject(?, 16, 7)")
        let initializer = try #require(function.instructions.first { $0.callee?.hasPrefix("Reconstruction.\(type).init(") == true })
        #expect(initializer.callSelf == binding.name)
        for text in [function.renderPseudo(), function.renderStructured()] {
            #expect(text.contains("return Reconstruction.\(type).init(self: \(binding.name))"), Comment(rawValue: text))
            #expect(text.components(separatedBy: "swift_allocObject(").count == 2, Comment(rawValue: text))
        }
    }
}

/// The payload enum method has no context self. This image does not yet
/// supply its complete direct receiver layout: ordinary positive reads alone
/// cannot decide which of the remaining physical words are its whole value.
/// Keep the call, declining that unsupported positional reconstruction.
@Test func aByValueEnumMethodTakesNoSelfIfPresent() async throws {
    guard let text = try await structured("Sample.run", in: "Fixtures/Sample/libSample.dylib") else { return }
    #expect(text.contains("Sample.Tree.sum()"), Comment(rawValue: text))
    #expect(!text.contains("Sample.Tree.sum(self:"), Comment(rawValue: text))
}

/// An address that escapes before the frame record exists is no proven
/// local below it. Here it is the record's future slot itself, stored out
/// before the prologue saves x29 there, so a later unknown callee may
/// overwrite the saved x29:
///
///     sub sp, sp, #0x20; add x9, sp, #0x10; str x9, [x0]; mov x9, #0
///     stp x29, x30, [sp, #0x10]; add x29, sp, #0x10; bl 0x2000
///     ldp x29, x30, [sp, #0x10]; add sp, sp, #0x20; ret
///
/// No register holds the address at the call, so only the escape at the
/// store can account for the reach.
@Test func anAddressEscapedBeforeTheFrameRecordMayReachIt() throws {
    let words: [UInt32] = [
        0xd10083ff, 0x910043e9, 0xf9000009, 0xd2800009, 0xa9017bfd, 0x910043fd, 0x940003fa,
        0xa9417bfd, 0x910083ff, 0xd65f03c0,
    ]
    let early = try #require(CalleeRegisterSummary.of(try body(words, name: "early")))
    #expect(early.clobberedCalleeSaved.contains("x29"), "\(early.clobberedCalleeSaved)")
}

/// Every way the frame record's own address can reach code this body does
/// not see keeps the record reachable, so the saved x29 is not claimed:
/// a callee that reads x29, an unmodelled store of x29, and one path of a
/// join that stores x29 out.
@Test func everyEscapeOfTheRecordAddressKeepsItReachable() throws {
    // stp x29, x30, [sp, #-0x10]!; mov x29, sp; bl 0x2000; ldp …; ret,
    // where 0x2000 reads the frame pointer.
    let reader = CalleeRegisterSummary(argumentReads: [], readsFramePointer: true, clobberedCalleeSaved: [])
    let readsFP = try #require(CalleeRegisterSummary.of(
        try body([0xa9bf7bfd, 0x910003fd, 0x940003fe, 0xa8c17bfd, 0xd65f03c0], name: "readsFP"),
        calleeEffects: { _ in reader.effect }, isFunction: { $0 == 0x2000 }))
    #expect(readsFP.clobberedCalleeSaved.contains("x29"), "\(readsFP.clobberedCalleeSaved)")
    // stlr x29, [x0] (no modelled store) before an unknown call.
    let released = try #require(CalleeRegisterSummary.of(try body(
        [0xa9bf7bfd, 0x910003fd, 0xc89ffc1d, 0x940003fd, 0xa8c17bfd, 0xd65f03c0], name: "released")))
    #expect(released.clobberedCalleeSaved.contains("x29"), "\(released.clobberedCalleeSaved)")
    // sub sp, sp, #0x20; stp x29, x30, [sp, #0x10]; add x29, sp, #0x10
    // cbz x1, 1f; str x29, [sp]; 1: bl 0x2000; ldp …; add sp, sp, #0x20; ret.
    // One path stores the record's address out; the record slot itself is
    // intact on both, so only the join's escape fact keeps it reachable.
    let joined = try #require(CalleeRegisterSummary.of(try body(
        [0xd10083ff, 0xa9017bfd, 0x910043fd, 0xb4000041, 0xf90003fd, 0x940003fb,
         0xa9417bfd, 0x910083ff, 0xd65f03c0], name: "joined")))
    #expect(joined.clobberedCalleeSaved.contains("x29"), "\(joined.clobberedCalleeSaved)")
}

/// A prologue store at or above entry sp is in the caller's memory, which an
/// incoming pointer may reach (abi_frame_ownership.s), even in a function
/// with a frame record:
///
///     stp x29, x30, [sp, #-0x10]!; str x19, [sp, #0x10]; mov x29, sp
///     mov x19, xzr; str x1, [x0]; ldr x19, [sp, #0x10]; ldp x29, x30, [sp], #0x10; ret
@Test func aPrologueStoreInTheCallersMemoryIsNoOwnSave() throws {
    let words: [UInt32] = [0xa9bf7bfd, 0xf9000bf3, 0x910003fd, 0xaa1f03f3, 0xf9000001, 0xf9400bf3, 0xa8c17bfd, 0xd65f03c0]
    let summary = try #require(CalleeRegisterSummary.of(try body(words, name: "callerArea")))
    #expect(summary.clobberedCalleeSaved.contains("x19"), "\(summary.clobberedCalleeSaved)")
}

/// Swift's dynamically sized local: `___chkstk_darwin` probes x9 bytes, then
/// sp moves by that size rounded to 16. While sp holds that allocation, the
/// next callee's stack starts below the frame, so the saves above survive an
/// unknown call (the tracer's proof, d9bbf74, in the summary):
///
///     stp x29, x30, [sp, #-0x20]!; stp x20, x19, [sp, #0x10]; mov x29, sp
///     sub sp, sp, #0x10; ldr x9, [x0]; add x8, x9, #15; and x8, x8, #~15; bl ___chkstk_darwin
///     mov x9, sp; sub x8, x9, x8; mov sp, x8; bl 0x3000
///     mov sp, x29; ldp x20, x19, [sp, #0x10]; ldp x29, x30, [sp], #0x20; ret
@Test func aProbedAllocationKeepsTheSavesAboveItAcrossACall() throws {
    let probe: UInt64 = 0x2000
    let words: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xf9400009, 0x91003d28, 0x927ced08, 0x940003f9,
        0x910003e9, 0xcb080128, 0x9100011f, 0x940007f5, 0x910003bf, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let proven = try #require(CalleeRegisterSummary.of(try body(words, name: "probed"), isStackProbe: { $0 == probe }))
    #expect(proven.clobberedCalleeSaved.isEmpty, "\(proven.clobberedCalleeSaved)")
    // The control: with the probe unrecognised, sp is unknown at the call.
    let unproven = try #require(CalleeRegisterSummary.of(try body(words, name: "unprobed")))
    #expect(unproven.clobberedCalleeSaved.isSuperset(of: ["x19", "x20", "x29"]), "\(unproven.clobberedCalleeSaved)")
    // The control: sp moves by a reload of the size, not the probed value
    // (`ldr x10, [x0]; add x11, x10, #15; and x11, x11, #~15; mov x9, sp;
    // sub x8, x9, x11`): another load, so no proof.
    let reload: [UInt32] = [
        0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xd10043ff, 0xf9400009, 0x91003d28, 0x927ced08, 0x940003f9,
        0xf940000a, 0x91003d4b, 0x927ced6b, 0x910003e9, 0xcb0b0128, 0x9100011f, 0x940007f2,
        0x910003bf, 0xa9414ff4, 0xa8c27bfd, 0xd65f03c0,
    ]
    let reloaded = try #require(CalleeRegisterSummary.of(try body(reload, name: "reloaded"), isStackProbe: { $0 == probe }))
    #expect(reloaded.clobberedCalleeSaved.isSuperset(of: ["x19", "x20", "x29"]), "\(reloaded.clobberedCalleeSaved)")
}
