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
