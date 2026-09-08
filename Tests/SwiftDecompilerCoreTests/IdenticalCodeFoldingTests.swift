import Testing
import Foundation
@testable import SwiftDecompilerCore
import MachOKit

/// Identical code folding (`ld -icf`, on by default for release Mach-O) collapses
/// byte-identical function bodies — outlined value witnesses, trivial getters, the
/// `_modify` resume funclets that all reduce to a bare `ret` — onto one address,
/// under every one of their original mangled names. Nothing in a mangled name
/// records the merge, so naming the address after whichever symbol the table lists
/// first (the obvious "nearest symbol" heuristic) is a confident, specific
/// misattribution of all the others.
///
/// This is a soundness case, not a cosmetic one. It is the concrete reason
/// swiftdc's `sub_`-naming problem cannot be closed by a smarter symbol search:
/// for a folded address there is no single correct name, because there is no
/// single function there. The guard's job is to decline — render `sub_<addr>` and
/// list the candidates — never to guess one.
///
/// Runs only when `Fixtures/Sample/sample.release` (a real `-O` binary that
/// exhibits folding) is built, matching the suite's `…IfPresent` convention.

private let optimizedFixture = "Fixtures/Sample/sample.release"

/// `__text` addresses that two or more *distinct* symbols name, computed straight
/// from the symbol table — the same evidence `Disassembler.foldedSymbolAddresses`
/// uses, but recomputed here independently of the disassembler's naming decision,
/// which is what this test is actually checking.
private func foldedAddresses(in machO: MachOFile) -> [UInt64: [String]] {
    guard let text = machO.sections.first(where: {
        $0.segmentName == "__TEXT" && $0.sectionName == "__text"
    }) else { return [:] }
    let range = UInt64(text.address) ..< UInt64(text.address + text.size)
    var byAddress: [UInt64: Set<String>] = [:]
    for symbol in machO.symbols where !symbol.name.isEmpty {
        let address = UInt64(symbol.offset)
        guard range.contains(address) else { continue }
        byAddress[address, default: []].insert(symbol.name)
    }
    return byAddress.filter { $0.value.count >= 2 }.mapValues { $0.sorted() }
}

@Test func declinesToNameIdenticalCodeFoldedAddressesIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: optimizedFixture),
          let machO = try? BinaryLoader.load(path: optimizedFixture)
    else { return }

    let folded = foldedAddresses(in: machO)

    // Adversarial: the fixture must actually EXHIBIT folding, or the assertions
    // below are vacuous. A `-O` build with a linker default of `-icf` does; if a
    // toolchain change stops folding, this fails loudly rather than passing empty.
    #expect(
        !folded.isEmpty,
        "sample.release exhibits no identical-code-folded addresses; the guard cannot be exercised"
    )

    let functions = try await Disassembler(preset: .default).disassemble(path: optimizedFixture)

    // Every recovered function that starts on a folded address (and is not an
    // Objective-C IMP, which stays metadata-named) must decline to pick a name.
    let foldedFunctions = functions.filter {
        folded[$0.startAddress] != nil && $0.objcMethod == nil
    }
    #expect(
        !foldedFunctions.isEmpty,
        "no recovered function starts on a folded address, so the guard is untested"
    )

    for function in foldedFunctions {
        let candidates = folded[function.startAddress]!
        let hex = String(function.startAddress, radix: 16)

        // Declined: synthesized name, no demangled name, source tags the fold.
        #expect(
            function.source == .foldedSymbols,
            "0x\(hex): source is \(function.source), expected .foldedSymbols"
        )
        #expect(function.demangledName == nil, "0x\(hex): must carry no demangled name")
        #expect(function.symbol == "sub_\(hex)", "0x\(hex): must render as sub_<addr>")
        #expect(function.displayName == "sub_\(hex)")

        // The one behaviour that must never happen: silently adopting one of the
        // folded symbols. `displayName` is not any candidate's name.
        #expect(
            !candidates.contains(function.displayName),
            "0x\(hex): picked one folded symbol (\(function.displayName)) instead of declining"
        )

        // The information isn't thrown away — the candidates are carried and rendered.
        #expect(function.foldedCandidates == candidates, "0x\(hex): candidate list mismatch")
        let rendered = function.render()
        #expect(rendered.contains("identical code folding"), "0x\(hex): render omits the fold note")
        #expect(
            candidates.allSatisfy { rendered.contains($0) },
            "0x\(hex): render must list every folded candidate"
        )
    }
}
