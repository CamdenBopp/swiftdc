import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A callee whose result is `Never` has no success value. One that throws
/// still comes back, along its error edge alone, and x0 there is scratch or
/// a typed error's payload. The call was given a result all the same:
/// `bl stop; ret` in a `throws -> Int` function rendered `return try
/// stop(arg0)`, and a caller adding one to a typed error's payload rendered
/// `return (halt(arg0) + 1)`. nosuccess.swift and no_success.s state each
/// function's true behaviour.
private func views(of path: String, module: String) async throws -> [String: [String]] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    var views: [String: [String]] = [:]
    for function in functions where function.displayName.hasPrefix("\(module).") {
        let name = String(function.displayName.dropFirst(module.count + 1).prefix { $0 != "(" })
        views[name] = [function.renderStructured(), function.renderPseudo()]
    }
    return views
}

/// Lines of `text` in order, trimmed.
private func lines(_ text: String) -> [String] {
    text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
}

/// The lines of `text` that call `callee`, and whether each is the call
/// alone: a statement, not bound, returned or part of another expression.
private func calls(to callee: String, in text: String) -> (count: Int, allBare: Bool) {
    let calling = lines(text).filter { $0.contains("\(callee)(") }
    return (calling.count, calling.allSatisfy { $0.hasPrefix("\(callee)(") })
}

private let asmPath = "Fixtures/Sample/libNoSuccessAsm.dylib"

/// The gate reads the result type, not any `Never` in the name.
@Test func onlyANeverResultIsNoSuccessValue() {
    #expect(ValueTracer.CallFacts(callee: "M.stop(Swift.Int) throws -> Swift.Never").returnsNeverByName)
    #expect(ValueTracer.CallFacts(callee: "M.halt(Swift.Int) throws(M.Refused) -> Swift.Never").returnsNeverByName)
    #expect(ValueTracer.CallFacts(callee: "M.die(Swift.Int) -> Swift.Never").returnsNeverByName)
    // The thrown type, a parameter and an optional result are not the result.
    #expect(!ValueTracer.CallFacts(callee: "M.ordinary(Swift.Int) throws(Swift.Never) -> Swift.Int").returnsNeverByName)
    #expect(!ValueTracer.CallFacts(callee: "M.take((Swift.Int) -> Swift.Never) -> Swift.Int").returnsNeverByName)
    #expect(!ValueTracer.CallFacts(callee: "M.maybe(Swift.Int) -> Swift.Never?").returnsNeverByName)
    #expect(!ValueTracer.CallFacts(callee: "M.count(Swift.Int) throws -> Swift.Int").returnsNeverByName)
    // No signature says nothing about the result.
    #expect(!ValueTracer.CallFacts(callee: "nosuccess_opaque").returnsNeverByName)
    #expect(!ValueTracer.CallFacts(callee: "sub_1000").returnsNeverByName)
}

/// `bl stop`, the epilogue and `ret` in a throwing function: the exit is
/// not `return try` of a value the callee does not have.
@Test func aForwardedNeverCallIsNotAReturnedValueIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: asmPath) else { return }
    for text in try #require(try await views(of: asmPath, module: "NoSuccessAsm")["relay"]) {
        let stop = calls(to: "NoSuccessAsm.stop", in: text)
        // The call is there once, as a statement.
        #expect(stop.count == 1 && stop.allBare, Comment(rawValue: text))
        #expect(!text.contains("return try"), Comment(rawValue: text))
        #expect(!lines(text).contains { $0.hasPrefix("return") }, Comment(rawValue: text))
    }
}

/// x0 read after a typed-throws `Never` callee is its error's payload:
/// the caller returns a value, and it is not the call.
@Test func aRegisterAfterANeverCallIsNotItsResultIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: asmPath) else { return }
    for text in try #require(try await views(of: asmPath, module: "NoSuccessAsm")["code"]) {
        let halt = calls(to: "NoSuccessAsm.halt", in: text)
        #expect(halt.count == 1 && halt.allBare, Comment(rawValue: text))
        #expect(lines(text).contains("return ?"), Comment(rawValue: text))
    }
}

/// The controls: a throwing callee with an Int result is still forwarded,
/// `throws(Never) -> Int` still has its Int, and a callee with no
/// signature keeps the result nothing disproves.
@Test func aCalleeWithAResultKeepsItIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: asmPath) else { return }
    let views = try await views(of: asmPath, module: "NoSuccessAsm")
    for text in try #require(views["relayCount"]) {
        #expect(lines(text).contains { $0.hasPrefix("return try NoSuccessAsm.count(") }, Comment(rawValue: text))
    }
    for text in try #require(views["useOrdinary"]) {
        #expect(lines(text).contains { $0.hasPrefix("return ") && $0.contains("NoSuccessAsm.ordinary(") },
                Comment(rawValue: text))
    }
    for text in try #require(views["useOpaque"]) {
        #expect(lines(text).contains { $0.hasPrefix("return ") && $0.contains("nosuccess_opaque(") },
                Comment(rawValue: text))
    }
}

/// The compiler's own lowering, at each level: a call of `stop` or `halt`
/// is a statement wherever it appears, never a value.
@Test(arguments: ["Onone", "O", "Osize"])
func aCompiledNeverCallIsNeverAValueIfPresent(level: String) async throws {
    let path = "Fixtures/Sample/libNoSuccess.\(level).dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let views = try await views(of: path, module: "NoSuccess")
    for (name, callee) in [("caught", "NoSuccess.stop"), ("relay", "NoSuccess.stop"), ("haltCode", "NoSuccess.halt")] {
        for text in try #require(views[name], "no \(name)") {
            let found = calls(to: callee, in: text)
            #expect(found.count >= 1 && found.allBare, Comment(rawValue: "\(name) at -\(level):\n\(text)"))
        }
    }
}

/// With the normal edge gone the optimizer runs the catch straight after
/// the call: it stays in the render, and the `throws(Never)` control keeps
/// its value.
@Test(arguments: ["O", "Osize"])
func aCompiledCatchAfterANeverCallIsStillThereIfPresent(level: String) async throws {
    let path = "Fixtures/Sample/libNoSuccess.\(level).dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let views = try await views(of: path, module: "NoSuccess")
    for text in try #require(views["caught"]) {
        // The catch releases the error it caught. At -Osize its `return 1`
        // is in an outlined tail, so the release is what both levels show.
        #expect(lines(text).contains { $0.hasPrefix("swift_errorRelease(") }, Comment(rawValue: text))
        if level == "O" { #expect(lines(text).contains("return 1"), Comment(rawValue: text)) }
    }
    for text in try #require(views["useOrdinary"]) {
        let ordinary = calls(to: "NoSuccess.ordinary", in: text)
        #expect(ordinary.count >= 1 && !ordinary.allBare, Comment(rawValue: text))
    }
}
