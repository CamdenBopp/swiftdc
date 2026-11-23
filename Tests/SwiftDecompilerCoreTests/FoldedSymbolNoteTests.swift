import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A folded address declines to pick a name and renders `sub_<addr>`. The
/// plain listing printed the symbols it declined between; `--pseudo`,
/// `--structured` and `--cfg` printed none, so a function the image names
/// twice read as one no symbol names (libReconstruction.opt.dylib: 48
/// folded functions noted in the listing, 0 in the other three views).
/// Every view now carries every candidate.
@Test func everyViewListsTheSymbolsAFoldedAddressDeclinesIfPresent() async throws {
    let fixture = "Fixtures/Sample/libReconstruction.opt.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }
    let folded = functions.filter { $0.source == .foldedSymbols }
    #expect(!folded.isEmpty, "the fixture has no folded address, so nothing is tested")
    // The fixture covers the single-block structured fallback. The decoded
    // branch below independently exercises the multi-block structurer.
    #expect(folded.contains { $0.basicBlocks(consumer: "test").count == 1 })

    for function in folded {
        let candidates = try #require(function.foldedCandidates)
        #expect(candidates.count >= 2)
        let views = [
            "listing": function.render(), "pseudo": function.renderPseudo(),
            "structured": function.renderStructured(), "cfg": function.renderCFG(),
        ]
        for (view, text) in views.sorted(by: { $0.key < $1.key }) {
            let lines = text.components(separatedBy: "\n")
            #expect(
                lines.filter { $0.contains("\(candidates.count) symbols folded onto") }.count == 1,
                "\(function.displayName) \(view): the fold is stated once"
            )
            // The candidates follow the note directly, each once, in the
            // sorted order `foldedCandidates` holds: no name is preferred
            // and no process's hash order decides the listing.
            let listed = lines.drop { !$0.contains("symbols folded onto") }.dropFirst()
                .prefix(candidates.count)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(
                listed == candidates.map { "//   \($0)" },
                "\(function.displayName) \(view): listed \(listed), expected \(candidates)"
            )
            #expect(candidates == candidates.sorted(), "\(function.displayName): candidates are sorted")
            #expect(text.hasPrefix("sub_"), "\(function.displayName) \(view): the name stays declined")
        }
    }
}

@Test func multiBlockFoldedFunctionKeepsCandidatesInStructuredOutput() throws {
    let engine = try #require(CapstoneEngine())
    // cbz x0,0x1008; mov x0,#1; ret. Two possible paths join at ret.
    let words: [UInt32] = [0xb4000040, 0xd2800020, 0xd65f03c0]
    let bytes = words.flatMap { word in
        (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
    }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let candidates = ["_firstCandidate", "_secondCandidate"]
    let function = DisassembledFunction(symbol: "sub_1000", demangledName: nil,
        startAddress: 0x1000, instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .foldedSymbols, foldedCandidates: candidates)
    try #require(function.basicBlocks(consumer: "folded-note-test").count > 1)
    let lines = function.renderStructured().components(separatedBy: "\n")
    #expect(lines.first == "sub_1000 {")
    #expect(lines.filter { $0.contains("2 symbols folded onto 0x1000") }.count == 1)
    #expect(Array(lines.dropFirst(2).prefix(2)) == candidates.map { "    //   \($0)" })
}

/// A function with one name gains no fold note in any view.
@Test func aFunctionWithOneNameCarriesNoFoldNoteIfPresent() async throws {
    let fixture = "Fixtures/Sample/libReconstruction.opt.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }
    let named = functions.filter { $0.source != .foldedSymbols }
    #expect(!named.isEmpty)
    for function in named {
        for text in [function.renderPseudo(), function.renderStructured(), function.renderCFG()] {
            #expect(!text.contains("symbols folded onto"), "\(function.displayName)")
        }
    }
}
