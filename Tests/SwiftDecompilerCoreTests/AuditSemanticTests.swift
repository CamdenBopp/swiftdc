import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func indirectTailTransfersAndAwaitsRemainVisibleIfPresent() async throws {
    for (path, filter, names) in [
        ("Fixtures/Sample/libIndirectTail.dylib", "", ["apply", "map_free", "choose_and_apply"]),
        ("Fixtures/Sample/libIndirectAwait.opt.dylib", "IndirectAwait", ["viaClosure", "viaProtocol", "viaClass"]),
    ] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
        }
        for name in names {
            let matching = functions.filter { $0.displayName.contains(name) }
            try #require(!matching.isEmpty)
            for text in [matching.map { $0.renderPseudo() }.joined(separator: "\n"), matching.map { $0.renderStructured() }.joined(separator: "\n")] {
                #expect(text.contains(path.contains("Await") ? "await indirect_call(" : "indirect_jump("), Comment(rawValue: text))
                #expect(!text.contains("leaf / pure computation"), Comment(rawValue: text))
                if name == "choose_and_apply" {
                    #expect(text.components(separatedBy: "choose(").count == 2, Comment(rawValue: text))
                    // The jump goes through choose's one result: inline when
                    // nothing with an effect separates them, else bound.
                    let inline = text.contains("indirect_jump(choose(")
                    let bound = text.range(of: #"let r[0-9]+ = choose\("#, options: .regularExpression) != nil
                        && text.range(of: #"indirect_jump\(r[0-9]+\)"#, options: .regularExpression) != nil
                    #expect(inline || bound, Comment(rawValue: text))
                }
            }
        }
    }
}

/// The loops a structured render contains, as (opening line, body lines,
/// the line after the loop's closing brace).
func structuredLoops(_ text: String) -> [(header: String, body: [String], after: String?)] {
    let lines = text.components(separatedBy: "\n")
    var loops: [(String, [String], String?)] = []
    for (index, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces).hasPrefix("while (") {
        let indent = line.prefix { $0 == " " }.count
        guard let close = lines[(index + 1)...].firstIndex(where: {
            $0.prefix { $0 == " " }.count == indent && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else { continue }
        loops.append((line, Array(lines[(index + 1)..<close]), close + 1 < lines.count ? lines[close + 1] : nil))
    }
    return loops
}

/// An -O `for x in array` rendered `while (true) { log(); if (x19 != 1)
/// { continue } }`: the CFG had the exit edge, but the structurer excluded
/// the return block from the loop's exits and the exit vanished. And a
/// loop's normal exit must lead where the code goes: rotating an
/// overflow-checked loop on its `b.vs` printed the exit as `break` into the
/// `trap()` after it (`accumulate`, whose loop returns when it ends).
@Test func optimizedLoopsKeepTheirExitsIfPresent() async throws {
    for path in ["Fixtures/Sample/libAuditSemantics.opt.dylib", "Fixtures/Sample/libReconstruction.opt.dylib",
                 "Fixtures/Sample/libReconstruction.osize.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: path)
        }
        var loops = 0
        for function in functions {
            let text = function.renderStructured()
            for loop in structuredLoops(text) {
                loops += 1
                let exits = loop.body.contains { line in
                    ["break", "return", "goto ", "throw", "trap()"].contains { line.contains($0) }
                }
                #expect(!loop.header.contains("while (true)") || exits, "\(path): no exit\n\(text)")
                let breaks = loop.body.contains { $0.trimmingCharacters(in: .whitespaces) == "break" }
                #expect(!(breaks && loop.after?.trimmingCharacters(in: .whitespaces) == "trap()"),
                        "\(path): a break falls into a trap\n\(text)")
            }
        }
        #expect(loops > 0, "\(path): no loops rendered")
    }
}

@Test func singleUseCallsStayBeforeEffectsAndBranchesIfPresent() async throws {
    let path = "Fixtures/Sample/libAuditSemantics.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "AuditSemantics")
    }
    for name in ["ordered", "branched"] {
        let function = try #require(functions.first { $0.displayName.hasPrefix("AuditSemantics.\(name)(") })
        for (structured, text) in [(false, function.renderPseudo()), (true, function.renderStructured())] {
            let producer = try #require(text.range(of: "let r0 = AuditSemantics.next("), Comment(rawValue: text))
            let effect = try #require(text.range(of: name == "branched" && structured ? "if (" : "AuditSemantics.log("), Comment(rawValue: text))
            #expect(producer.lowerBound < effect.lowerBound, Comment(rawValue: text))
            #expect(text.contains("return r0"), Comment(rawValue: text))
            #expect(text.components(separatedBy: "AuditSemantics.next(").count == 2, Comment(rawValue: text))
        }
    }
    let adjacent = try #require(functions.first { $0.displayName.hasPrefix("AuditSemantics.adjacent(") }).renderStructured()
    #expect(adjacent.contains("AuditSemantics.next(arg0)"), Comment(rawValue: adjacent))
    #expect(!adjacent.contains("let r"), Comment(rawValue: adjacent))
}

/// Loads between a call and its use reorder nothing a reader sees. Treating
/// the epilogue's `ldp x29, x30` between `bl Hasher._finalize` and `ret` as
/// an effect turned `return Swift.Hasher._finalize()` into
/// `let r0 = Swift.Hasher._finalize(); return r0` (158 fixture lines).
@Test func aResultReturnedPastTheEpilogueStaysInlineIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "hashValue")
    }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("return Swift.Hasher._finalize("), Comment(rawValue: text))
    #expect(!text.contains("= Swift.Hasher._finalize("), Comment(rawValue: text))
}

/// x20 freshly written before a call is `self` only for a callee that has
/// one. Parked there for a value live across the call, it rendered as the
/// receiver of a free function, and spelled one call twice:
/// `keepBox(self: makeBox(), makeBox(), 3)`.
@Test func aFreeFunctionTakesNoSelfIfPresent() async throws {
    let path = "Fixtures/Sample/libAuditSemantics.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "AuditSemantics.parked")
    }
    let text = try #require(functions.first).renderStructured()
    #expect(text.contains("AuditSemantics.keepBox("), Comment(rawValue: text))
    #expect(!text.contains("keepBox(self:"), Comment(rawValue: text))
    #expect(text.components(separatedBy: "AuditSemantics.makeBox(").count == 2, Comment(rawValue: text))
}

/// A getter of a class or static property, and a private method with no
/// parameters, take nothing in x0–x7, but their names kept them out of the
/// signature layout, so whatever x0 held printed as an argument:
/// `Gauge.(tick in _…)(r0)`, `Units.scale.getter(r0)`, `reading.getter(r1)`.
@Test func calleesWithoutParametersShowNoArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/libAuditSemantics.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "AuditSemantics")
    }
    let text = functions.filter { $0.displayName.hasPrefix("AuditSemantics.Gauge.run(") || $0.displayName.hasPrefix("AuditSemantics.scaled(") }
        .map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.range(of: #"\(tick in _[0-9A-F]+\)\(\)"#, options: .regularExpression) != nil, Comment(rawValue: text))
    #expect(text.contains("Units.scale.getter()"), Comment(rawValue: text))
    #expect(text.contains("Gauge.reading.getter()"), Comment(rawValue: text))
    #expect(Disassembler.withoutPrivateDiscriminators("M.(tick in _0A1B)") == "M.tick")
}

/// An accessor's ` : Type` is its property's type. Left on the callee it
/// read as a call through the type (`Foo.value.getter : Swift.Int()`), and a
/// self dispatch to the getter was named after the type: `self.Int()`.
@Test func anAccessorCallNamesItsPropertyNotItsTypeIfPresent() async throws {
    #expect(DisassembledFunction.strippedCallee("M.Box.value.getter : Swift.Int") == "M.Box.value.getter")
    #expect(DisassembledFunction.selfDispatchCall("M.Box.value.getter : Swift.Int") == "self.value.getter")
    #expect(DisassembledFunction.strippedCallee("M.f(Swift.Int) -> Swift.Int") == "M.f")
    #expect(DisassembledFunction.strippedCallee("M.P.a.modify : Swift.Int with unmangled suffix \".resume.0\"")
        == "M.P.a.modify with unmangled suffix \".resume.0\"")
    let path = "Fixtures/Sample/libReconstruction.osize.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(!text.contains("self.Int("), Comment(rawValue: text))
    #expect(!text.contains(".getter : Swift.Int("), Comment(rawValue: text))
}

/// Comparing with 1, or testing bit 0, is a truth test only for a Bool.
/// `level(n) == 1` for an Int-returning `level` rendered `if (level())`,
/// which also holds for 2; `level(n) % 2 == 0` (`tbz x0, #0`) rendered
/// `if (!level())`. A Bool-returning call still reads as a condition.
@Test func onlyABoolFoldsToATruthTestIfPresent() async throws {
    let path = "Fixtures/Sample/libAuditSemantics.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "AuditSemantics.is")
    }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("AuditSemantics.\(name)(") }).renderStructured()
    }
    let one = expandingResultBindingsForAssertions(try render("isOne"))
    #expect(one.contains("AuditSemantics.level(arg0) == 1") || one.contains("AuditSemantics.level(arg0) != 1"), Comment(rawValue: one))
    let even = try render("isEven")
    #expect(even.contains("bit 0 of AuditSemantics.level(arg0)"), Comment(rawValue: even))
    let ready = try render("isReady")
    #expect(ready.contains("if (AuditSemantics.ready(arg0))") || ready.contains("if (!AuditSemantics.ready(arg0))"), Comment(rawValue: ready))
}

/// After `try await store.apply(ops)` the await-return funclet tests the
/// callee's error in x20 and, on the error path, releases `ops` before
/// branching to its ResumeParent with x20 untouched: a rethrow. The throw
/// check counted every call as writing x20, which is callee-saved, so the
/// path read `else { return }`.
@Test func aRethrowAfterACleanupCallStillThrowsIfPresent() async throws {
    let path = "Fixtures/Sample/libRethrowCleanup.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "RethrowCleanup.A2.persist")
    }
    let resumes = functions.filter { $0.displayName.hasPrefix("(2) await resume partial function for RethrowCleanup.A2.persist") }
    let text = try #require(resumes.first).renderStructured()
    #expect(text.contains("throw ?"), Comment(rawValue: text))
    #expect(!text.contains("} else {\n        return\n"), Comment(rawValue: text))
}

/// Which calls follow the Swift convention (and so take `self` in x20) was
/// read from objdump's `symbol stub for: _$s…` comment. The in-process
/// decoder has no such text, so a filtered run, a cache image, or a
/// streamed listing dropped `self:` from every call to an imported Swift
/// method: `-f Dog.speak` rendered `String.append(" the ")` where the full
/// listing had `String.append(self: local_40, " the ")`.
@Test func aFilteredRunKeepsSelfOnImportedSwiftCallsIfPresent() async throws {
    let path = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let (filtered, whole) = try await withStableDependencies {
        let disassembler = Disassembler(preset: .default)
        return (try await disassembler.disassemble(path: path, functionFilter: "Dog.speak"),
                try await disassembler.disassemble(path: path))
    }
    let one = try #require(filtered.first { $0.displayName.contains("Dog.speak") }).renderStructured()
    let all = try #require(whole.first { $0.displayName.contains("Dog.speak") }).renderStructured()
    #expect(one.contains("Swift.String.append(self: "), Comment(rawValue: one))
    #expect(one == all, "filtered:\n\(one)\nwhole:\n\(all)")
}

/// A callee declared `async throws(Code)` hands its thrown payload back in
/// x0 (with x20 = 1), and the success and error paths resume in the same
/// funclet. Binding x0 as the awaited result made the catch block read
/// `TT.onError((awaited1 + 1000))`, the error as if it were the value.
@Test func aTypedThrowsAwaitBindsNoResultIfPresent() async throws {
    let path = "Fixtures/Sample/libTypedThrowsAwait.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "TypedThrowsAwait.useCode")
    }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("await TypedThrowsAwait.codeAsync(arg0)"), Comment(rawValue: text))
    #expect(!text.contains("awaited1"), Comment(rawValue: text))
}

/// The control: plain `throws` returns its error in x20, so x0 at the
/// resume is the result and keeps its name.
@Test func anUntypedThrowsAwaitKeepsItsBindingIfPresent() async throws {
    let path = "Fixtures/Sample/libAsyncFns.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "awaitThrowing")
    }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("let awaited1 = await AsyncFns.fetchOrThrow(arg0)"), Comment(rawValue: text))
}
