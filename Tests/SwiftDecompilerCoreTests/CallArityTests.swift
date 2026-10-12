import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A call site snapshots x0–x7 positionally, so a register the callee never
/// reads rendered as an argument, and an integer passed after a Double read in
/// the Double's position. Arguments of a Swift callee whose every parameter is
/// a proven one-register scalar are now laid out from its signature. Each
/// caller in `callarity.swift` leaves a non-argument register live.
///
/// A parameter count alone is not a layout: a String is two registers, so a
/// count cap on `sink(_: String, _: Int)` drops the Int. That was tried and
/// reverted on 2026-10-12; the layout declines any parameter it cannot size.
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
        #expect(callMixed.contains("CallArity.mixed(arg0, ?, arg1)"), "\(fixture): \(callMixed)")
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
    // A String is two registers; generics carry trailing metadata; inout is a pointer
    // to a value of unknown footprint here; async has a context.
    #expect(layout("M.sink(Swift.String, Swift.Int) -> ()") == nil)
    #expect(layout("M.gen<A>(Swift.Int, A) -> Swift.Int") == nil)
    #expect(layout("M.bump(inout Swift.Int) -> ()") == nil)
    #expect(layout("M.wait(Swift.Int) async -> Swift.Int") == nil)
    // An instance method of a type not known to be a class: its self may be a
    // value passed after the formals.
    #expect(layout("M.S.scaled(Swift.Int) -> M.S") == nil)
    #expect(layout("closure #1 (Swift.Int) -> () in M.f() -> ()") == nil)
    #expect(layout("M.Holder.value.getter : Swift.Int") == nil)
}
