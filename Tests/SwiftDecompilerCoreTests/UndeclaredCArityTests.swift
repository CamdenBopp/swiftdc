import Foundation
import Testing
@testable import SwiftDecompilerCore

// A call to a C symbol outside the image that no table, SDK declaration or
// body bounds has no arity in the binary. `tailcallsinks.c` declares
// `void A(void)` and `long P(long)` only in its own source.

private func listing(_ path: String, _ filter: String) async throws -> DisassembledFunction? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
    }
    return try #require(functions.first { $0.symbol == "_" + filter }, "\(filter) not found in \(path)")
}

/// `s9`: after `P(a)`, x0 holds P's result, and `A()` takes nothing; it
/// read `A(r0)`. `P(a + 1)` with x0 untracked read `P()`. Neither arity is
/// known, so every call to them renders `(…)`.
@Test func undeclaredCCalleeClaimsNoArgumentsIfPresent() async throws {
    guard let function = try await listing("Fixtures/Sample/libTailCallSinks.dylib", "s9") else { return }
    let structured = function.renderStructured()
    let pseudo = function.renderPseudo()
    for text in [structured, pseudo] {
        #expect(!text.contains("A(r0)"), "\(text)")
        #expect(!text.contains("B(r0)"), "\(text)")
        #expect(!text.contains("P()"), "\(text)")
        #expect(!text.contains("C()"), "\(text)")
        #expect(text.contains("A(…)"), "\(text)")
    }
    // Every one of the four P calls and the A, B and C calls is marked.
    let calls = function.instructions.filter { $0.controlFlow == .call || $0.controlFlow == .branch }
        .filter { DisassembledFunction.calleeName(of: $0) != nil }
    #expect(calls.count == 6, "\(calls.map(\.text))")
    for call in calls {
        #expect(call.callArguments == ["…"], "\(call.address): \(call.annotation ?? "")")
    }
}

/// The statements of one function of `importarity.c`, in order.
private func importStatements(_ name: String) async throws -> [String]? {
    guard let function = try await listing("Fixtures/Sample/libImportArity.dylib", name) else { return nil }
    return function.renderPseudo().components(separatedBy: "\n").dropFirst().dropLast()
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// `t1`: nothing sets x0 for h0, and g0's stale result read `h0(g0())`, which
/// also hid the order of two calls. `t4` forwards its parameter and read
/// `ext()`. `d4`'s x1 is an entry value and read `ext(1, arg1)`. `c2`'s fadd
/// was dropped by `sinkD(extd())`, which claimed the result itself.
@Test func importWithNoPrototypeClaimsNoListIfPresent() async throws {
    guard let t1 = try await importStatements("t1"),
          let c2 = try await importStatements("c2"),
          let t4 = try await importStatements("t4"),
          let d4 = try await importStatements("d4")
    else { return }
    #expect(t1 == ["g0(…)", "h0(…)"])
    #expect(c2 == ["extd(…)", "sinkD(…)"])
    #expect(t4 == ["ext(…)"])
    #expect(d4 == ["ext(…)"])
}

/// The same through `@_silgen_name`: `ext_h0(ext_g0())` and
/// `ext_one(1, arg1)`, with the caller's own value still rendered.
@Test func silgenImportClaimsNoListIfPresent() async throws {
    let path = "Fixtures/Sample/libImportArity.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "\(name)").renderPseudo()
    }
    let t1 = try text("ImportArity.t1() -> ()")
    #expect(t1.contains("ext_g0(…)") && t1.contains("ext_h0(…)") && !t1.contains("ext_h0(ext_g0"), "\(t1)")
    let d4 = try text("ImportArity.d4(Swift.Int, Swift.Int) -> Swift.Int")
    #expect(d4.contains("return (ext_one(…) + arg1)"), "\(d4)")
}

/// A global's addressor takes nothing: `importedaddressor.swift` read
/// `lib.libVar.unsafeMutableAddressor(self: (? + arg0),
/// lib.libConst.unsafeMutableAddressor(self: arg0, arg0, arg1))`.
@Test func globalAddressorTakesNoSelfAndNoArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/libImportedAddressor.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "readBoth")
    }
    let text = try #require(functions.first).renderPseudo()
    #expect(text.contains("lib.libConst.unsafeMutableAddressor()"), "\(text)")
    #expect(text.contains("lib.libVar.unsafeMutableAddressor()"), "\(text)")
    #expect(!text.contains("self:"), "\(text)")
}

@Test func globalVariableAddressorIsTwoComponents() {
    #expect(DisassembledFunction.isGlobalVariableAddressor("lib.libVar.unsafeMutableAddressor : Swift.Int"))
    for name in ["lib.S.x.unsafeMutableAddressor : Swift.Int", "lib.libVar.getter : Swift.Int",
                 "lib.libVar.unsafeMutableAddressor", "lib.(x in _ABC).unsafeMutableAddressor : Swift.Int"] {
        #expect(!DisassembledFunction.isGlobalVariableAddressor(name), "\(name)")
    }
}

/// A C function the SDK declares keeps its declared arguments: `puts` in
/// `indirecttail.c`'s `choose`.
@Test func declaredCCalleeKeepsItsArgumentsIfPresent() async throws {
    guard let function = try await listing("Fixtures/Sample/libIndirectTail.dylib", "choose") else { return }
    let text = function.renderPseudo()
    #expect(text.contains("puts(\"choose\")"), "\(text)")
}

/// A call through a register the tracer resolved to an in-image body keeps
/// its arguments, though the name is a bare C identifier: `blr x8` into
/// `writablepointer.c`'s `twice(long)` and `staticwitness.s`'s `_slot5`.
@Test func resolvedInImageCalleeKeepsItsArgumentsIfPresent() async throws {
    if let pinned = try await listing("Fixtures/Sample/libWritablePointer.dylib", "viaPinned") {
        let text = pinned.renderPseudo()
        #expect(text.contains("twice((arg0 + 1))"), "\(text)")
    }
    if let witness = try await listing("Fixtures/Sample/libStaticWitness.dylib", "callThroughWitness") {
        let text = witness.renderPseudo()
        #expect(text.contains("slot5(?, ?, 0x4038)"), "\(text)")
    }
}

@Test func undeclaredCSymbolIsABareCIdentifier() {
    for name in ["P", "_private_helper", "abort", "notifyDone", "glEnd2"] {
        #expect(Disassembler.isUndeclaredCSymbol(name), "\(name)")
    }
    for name in ["Swift.print(_: Any...) -> ()", "M.f(Swift.Int) -> Swift.Int", "objc_msgSend",
                 "objc_msgSend$count", "sub_1f00", "OUTLINED_FUNCTION_3", "t9.cold.1",
                 "X.value.getter : Swift.Int", "-[NSObject init]", "foo(int)", "_Z1gi",
                 "swift_willThrow", "swift_setAtWritableKeyPath", "_swift_stdlib_reportUnimplementedInitializerInFile",
                 "objc_retain_x20", "objc_setProperty_nonatomic_copy", "__memset_chk", "__cxa_begin_catch", ""] {
        #expect(!Disassembler.isUndeclaredCSymbol(name), "\(name)")
    }
}
