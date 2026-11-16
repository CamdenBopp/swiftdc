import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A call site snapshotted x0–x7 positionally, so a register the callee never
/// reads rendered as an argument, and an integer passed after a Double read in
/// the Double's position. Arguments of a Swift callee whose every parameter is
/// a proven one-register scalar are now laid out from its signature. Each
/// caller in `callarity.swift` leaves a non-argument register live.
///
/// A parameter count alone is not a layout: a String is two registers, so a
/// count cap on `sink(_: String, _: Int)` drops the Int. That was tried and
/// reverted on 2026-10-12; the layout sizes each parameter (a String's two
/// registers since 2026-10-23) and declines any it cannot size.
private let fixtures = ["Fixtures/Sample/libCallArity.dylib", "Fixtures/Sample/libCallArity.opt.dylib"]

private func pseudo(_ filter: String, in fixture: String) async throws -> String {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: filter)
    }
    return functions.map { $0.renderPseudo() }.joined(separator: "\n")
}

@Test func swiftCalleeArgumentsFollowTheSignatureIfPresent() async throws {
    var checked = 0
    for fixture in fixtures where FileManager.default.fileExists(atPath: fixture) {
        let callOne = try await pseudo("CallArity.callOne", in: fixture)
        #expect(callOne.contains("CallArity.one(arg0)"), "\(fixture): \(callOne)")
        #expect(!callOne.contains("CallArity.one(arg0, "), "\(fixture): \(callOne)")

        let callMixed = try await pseudo("CallArity.callMixed", in: fixture)
        // The Double is in d0, the second Int in x1; the constant renders as the
        // Double the signature says it is.
        #expect(callMixed.contains("CallArity.mixed(arg0, 2.5, arg1)"), "\(fixture): \(callMixed)")
        checked += 1
    }
    // At -Onone `callNone` keeps both calls; `none` takes nothing, so `one`'s
    // result left in x0 is not its argument.
    if FileManager.default.fileExists(atPath: fixtures[0]) {
        let callNone = try await pseudo("CallArity.callNone", in: fixtures[0])
        #expect(callNone.contains("CallArity.none()"), "\(callNone)")
        #expect(!callNone.contains("none(CallArity.one"), "\(callNone)")
        #expect(checked == 2, "the -O fixture is missing; build Fixtures/Sample/build.sh")
    }
}

/// Unit view of what the layout accepts and declines.
@Test func theLayoutDeclinesWhatItCannotSize() {
    func layout(_ name: String) -> [Disassembler.ScalarParameterClass]? {
        Disassembler.swiftCallArgumentLayout(
            callee: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())
    }
    #expect(layout("M.one(Swift.Int) -> Swift.Int") == [.integer])
    #expect(layout("M.none() -> Swift.Int") == [])
    #expect(layout("M.mixed(Swift.Int, Swift.Double, Swift.Int) -> Swift.Double") == [.integer, .floating, .integer])
    #expect(layout("static M.S.make(Swift.Int) -> M.S") == [.integer])
    #expect(layout("M.S.init(x: Swift.Int) -> M.S") != nil)
    // A generic value is passed by address and the metadata follows the
    // formals, unshown; a tuple result with a generic element takes its
    // buffer first, from x0, and is not laid out. An async callee's context is its
    // `swiftasync` parameter (x22) and its formals take the ordinary
    // registers (`define swifttailcc void @dbl(ptr swiftasync %0, double
    // %1)`), unless an indirect result's buffer comes first (`@bigRes(ptr
    // %0, ptr swiftasync %1, i64 %2)`), which is not laid out. A String's two
    // registers and an inout address are sized in StringArityTests.
    #expect(layout("M.gen<A>(Swift.Int, A) -> Swift.Int") == [.integer, .integer])
    #expect(layout("M.split<A>(A, Swift.Int) -> (A, Swift.Int)") == nil)
    #expect(layout("M.wait(Swift.Int) async -> Swift.Int") == [.integer])
    #expect(layout("M.wait(Swift.Int) async -> M.Big") == nil)
    // An instance method of a type not known to be a class: its self may be a
    // value passed after the formals.
    #expect(layout("M.S.scaled(Swift.Int) -> M.S") == nil)
    #expect(layout("closure #1 (Swift.Int) -> () in M.f() -> ()") == nil)
    #expect(layout("M.Holder.value.getter : Swift.Int") == nil)
}

/// The readiness doc's float-argument entry: -Onone `Double(f) * 1.5` passes
/// the Float in s0, which call sites did not read, so the conversion rendered
/// `Swift.Double.init(?)` (and before that `Swift.Double.init()`).
@Test func aFloatArgumentReachesItsCalleeIfPresent() async throws {
    let fixture = "Fixtures/Sample/libConversions.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let text = try await pseudo("widenedTimesConstant", in: fixture)
    #expect(text.contains("Swift.Double.init(arg0)"), "\(text)")
}

/// A tail branch to a body that never writes x0 or v0, makes no call and
/// stores only to its own stack returns the x0 it was given. -O `callGen`
/// is `b sub_3e0`, and sub_3e0 is a lone `ret` (`gen(a, t) { a }`), so it
/// returns a; it rendered `sub_3e0()` and no return. `passthrough_tail.s`
/// pins the three guards: `keep` (a lone `ret`) returns n, `store` writes a
/// global and keeps its call, and `bump` writes x0 and is no passthrough.
@Test func aTailBranchToABodyThatKeepsX0ReturnsItIfPresent() async throws {
    let fixture = "Fixtures/Sample/libCallArity.opt.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let callGen = try await pseudo("callGen", in: fixture)
    #expect(callGen.contains("return arg0"), "\(callGen)")
    let tails = "Fixtures/Sample/libPassthroughTail.dylib"
    guard FileManager.default.fileExists(atPath: tails) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: tails) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("Passthrough.\(name)(") }).renderStructured()
    }
    #expect(try render("callKeep").contains("return arg0\n"))
    #expect(try render("callStore").contains("store(arg0)"))
    #expect(!(try render("callStore")).contains("return arg0"))
    #expect(!(try render("callWrite")).contains("return arg0"))
}

/// A function with no signature returns what its callers prove: one reads
/// x0 after calling it, and none reads x1, a float register or x21, or
/// returns right after the call (handing on a possible error).
/// `caller_proven.s`: `leaf` returns 7; `pair`'s caller reads x0 and x1,
/// `thrower`'s tests x21, `fwd`'s returns right after the call,
/// `setsError` writes x21 itself, and `dleaf`'s result is a float, so none
/// of those shows a value. Stripped,
/// the `sample.stripped` specialization of `Direction.init(rawValue:)`
/// returns its machine value as the unstripped twin's callers read it.
@Test func aResultItsCallersReadIsReturnedIfPresent() async throws {
    let path = "Fixtures/Sample/libCallerProven.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }).renderStructured()
    }
    #expect(try render("_leaf").contains("return 7\n"))
    for name in ["_dleaf", "_pair", "_thrower", "_fwd", "_setsError"] {
        #expect(!(try render(name)).contains("return"), "\(name)")
    }
    let stripped = "Fixtures/Sample/sample.stripped"
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let text = try await withStableDependencies { try await Disassembler().disassemble(path: stripped) }
        .map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("return ((arg0 <ᵁ 4) ? arg0 : 4)"))
}


/// A caller-proven result reaches the structured renderer's own exits: a
/// tail call out of `tailLeaf` is the value it returns, so the exit reads
/// `return ?` (or the call), never a bare `return` that says nothing comes
/// back.
@Test func aCallerProvenResultReachesATailExitIfPresent() async throws {
    let path = "Fixtures/Sample/libCallerProven.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.symbol == "_tailLeaf" }).renderStructured()
    #expect(!text.contains("return\n"), "\(text)")
}

/// Every rebuild of a function keeps its caller-proven result: dropping it
/// would turn its declined exits back into a bare `return`.
@Test func everyRebuildKeepsACallerProvenResult() throws {
    let engine = try #require(CapstoneEngine())
    let decoded = try #require(engine.disassemble(Data([0xc0, 0x03, 0x5f, 0xd6]), address: 0x1000).first)
    let ret = Instruction(address: decoded.address, text: decoded.text, controlFlow: decoded.controlFlow,
                          branchTarget: decoded.branchTarget, detail: decoded.detail)
    var function = DisassembledFunction(symbol: "sub_1000", demangledName: nil, startAddress: 0x1000,
        instructions: [ret], source: .address)
    function.callerProvenResult = true
    #expect(function.replacingInstructions([ret]).callerProvenResult)
    #expect(function.replacingInstructionPayload([ret]).callerProvenResult)
    #expect(function.retainingCFG(function.controlFlowGraph).callerProvenResult)
    #expect(function.attachingSwitchTargets([:]).callerProvenResult)
}
