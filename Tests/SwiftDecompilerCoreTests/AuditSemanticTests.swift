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
