import Testing
import Foundation
@testable import SwiftDecompilerCore

/// At -O `FoldLeft.count` and `FoldRight.total` share one getter body. Two
/// maps credited it to whichever class they read first:
///
/// - vtable dispatch named `self`'s slot by address, so `FoldRight.twiceTotal()`
///   rendered `return (self.count << 1)`: a property FoldRight does not have.
///   The slot is self's own, so the name must be the candidate at that address
///   that belongs to self's type.
/// - `SelfTypeIndex` bound the shared body's `self` to FoldLeft, so the body's
///   field reads would be named from FoldLeft's layout whichever class called
///   it. A body two class descriptors bind now has no binding.
private let fixtures = ["Fixtures/Sample/libCodegen.opt.dylib", "Fixtures/Sample/libCodegen.opt.stripped.dylib"]

@Test func aDispatchThroughAFoldedSlotIsNamedForSelfsOwnClassIfPresent() async throws {
    for fixture in fixtures where FileManager.default.fileExists(atPath: fixture) {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "twiceTotal")
        }
        let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
        #expect(text.contains("self.total"), "\(fixture): \(text)")
        #expect(!text.contains("count"), "\(fixture): \(text)")
    }
}

@Test func aBodyTwoClassesShareHasNoSelfTypeIfPresent() throws {
    let path = fixtures[1]
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let folds = MetadataSymbolizer().functionNames(in: machO).folded
    #expect(folds.count >= 2, "the fixture no longer folds: \(folds)")
    let index = SelfTypeIndex.build(in: machO)
    for (address, candidates) in folds {
        #expect(index.binding(for: address) == nil,
                "0x\(String(address, radix: 16)) \(candidates) is bound to \(String(describing: index.binding(for: address)?.selfTypeName))")
    }
    // Unshared bodies keep theirs, so the check is not vacuous.
    #expect(index.count >= 4)
}

/// A folded address declines to pick a name, so every symbol folded onto it
/// selects it under `-f`, raw or demangled. Each printed "No function
/// matched" for a symbol the binary exports (the empty-result class).
@Test func everyFoldedSymbolSelectsItsFunctionIfPresent() async throws {
    let fixture = "Fixtures/Sample/libReconstruction.opt.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    for filter in ["$s14Reconstruction7urgencyAA8PriorityOyF", "Reconstruction.heading", "IntQuad.a.setter"] {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: filter)
        }
        #expect(functions.contains { $0.source == .foldedSymbols }, "\(filter): \(functions.map(\.displayName))")
    }
}
