import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `libFoldedCalls.dylib` (foldedcalls.swift, -O): the linker folds
/// `Box.plus(_:)` and the signature specialization of `pairPlus(_:_:)` onto
/// one `add x0, x1, x0; ret`, and `callPair`, `callAdd` and `callBox` each
/// tail-call it. A heading there already declined to pick a symbol, but a
/// call to it took one: `callPair()`, which is `pairPlus((3, 2.5), 4)`,
/// rendered with `pairPlus`'s name, and `callBox(_:)`, which is `b.plus(6)`,
/// rendered `pairPlus(6)`: `self.a` in x1 lost to the other candidate's
/// layout. A call there names the address as its heading does and lays out
/// what the body reads.
private let fixture = "Fixtures/Sample/libFoldedCalls.dylib"

/// The folded address every caller reaches, from the symbol table.
private func sharedBodyAddress() throws -> UInt64? {
    let machO = try BinaryLoader.load(path: fixture)
    let plus = machO.symbols.first { $0.name == "_$s11FoldedCalls3BoxV4plusyS2iF" }
    let specialized = machO.symbols.first { $0.name == "_$s11FoldedCalls8pairPlusyS2i_Sdt_SitFTf4ndn_n" }
    guard let plus, let specialized, plus.offset == specialized.offset else { return nil }
    return UInt64(plus.offset)
}

@Test func aCallToAFoldedAddressTakesNoCandidatesNameOrLayoutIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let address = try #require(try sharedBodyAddress(), "the fixture no longer folds Box.plus with pairPlus")
    let sub = "sub_\(String(address, radix: 16))"
    let expected = [
        "FoldedCalls.callPair()": "\(sub)(3, 4)",
        "FoldedCalls.callAdd(Swift.Int)": "\(sub)(arg0, 5)",
        // x1 is the caller's `b.a`, unproven here, but the body reads it.
        "FoldedCalls.callBox(FoldedCalls.Box)": "\(sub)(6, ?)",
    ]
    // The unfiltered decode (objdump) and a filtered one (Capstone) name
    // calls on different paths.
    for filter in [nil, "callPair", "callAdd", "callBox"] as [String?] {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: filter)
        }
        let callers = functions.filter { expected[$0.displayName.components(separatedBy: " -> ")[0]] != nil }
        #expect(callers.count == (filter == nil ? 3 : 1), "\(filter ?? "unfiltered"): \(functions.map(\.displayName))")
        for function in callers {
            let call = try #require(expected[function.displayName.components(separatedBy: " -> ")[0]])
            for (view, text) in [("pseudo", function.renderPseudo()), ("structured", function.renderStructured()),
                                 ("listing", function.render())] {
                #expect(!text.contains("pairPlus") && !text.contains("addTwo") && !text.contains("plus("),
                        "\(filter ?? "unfiltered") \(view): \(text)")
                if view != "listing" {
                    #expect(text.contains(call), "\(filter ?? "unfiltered") \(view): \(text)")
                }
            }
        }
    }
}

/// Distinct symbols that all demangle to one name are one function's
/// aliases, so that name stands; two names decline to the heading's.
@Test func aFoldedTargetKeepsANameOnlyEveryCandidateShares() {
    let demangle: (String) -> String? = { ["_$sA": "M.f(Swift.Int) -> Swift.Int",
                                           "_$sB": "M.f(Swift.Int) -> Swift.Int",
                                           "_$sC": "M.g(Swift.Int) -> Swift.Int"][$0] }
    #expect(Disassembler.foldedTargetName(at: 0x600, candidates: ["_$sA", "_$sB"], demangle: demangle) == nil)
    #expect(Disassembler.foldedTargetName(at: 0x600, candidates: ["_$sA", "_$sC"], demangle: demangle) == "sub_600")
    #expect(Disassembler.foldedTargetName(at: 0x600, candidates: ["_a", "_b"], demangle: { _ in nil }) == "sub_600")
}

/// A vtable dispatch on self picks the candidate its owner proves. Two of
/// one type's members folded together leave the slot unproven.
@Test func anOwnerPicksAFoldedCandidateOnlyWhenItProvesOneIfPresent() throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let machO = try BinaryLoader.load(path: fixture)
    let demangled = ["$a": "M.Left.count.getter : Swift.Int", "$b": "M.Right.total.getter : Swift.Int",
                     "$c": "M.Right.size.getter : Swift.Int"]
    let resolver = Disassembler.ReferenceResolver(
        names: [0x10: "sub_10", 0x20: "sub_20"], stringRanges: [], machO: machO,
        demangleSymbol: { demangled[$0] },
        foldedCandidates: [0x10: ["$a", "$b"], 0x20: ["$b", "$c"]]
    )
    #expect(resolver.name(at: 0x10, ownedBy: "Right") == "M.Right.total.getter : Swift.Int")
    #expect(resolver.name(at: 0x10, ownedBy: "Left") == "M.Left.count.getter : Swift.Int")
    #expect(resolver.name(at: 0x20, ownedBy: "Right") == nil)
}

/// A witness-table dispatch reaches a folded address through a slot of one
/// conformance's table, which proves the candidate that is that
/// conformance's witness, if exactly one is.
@Test func aWitnessTableSlotPicksItsConformancesWitnessIfPresent() throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let machO = try BinaryLoader.load(path: fixture)
    let left = "protocol witness for M.P.f() -> () in conformance M.Left : M.P in M"
    let leftG = "protocol witness for M.P.g() -> () in conformance M.Left : M.P in M"
    let right = "protocol witness for M.P.f() -> () in conformance M.Right : M.P in M"
    let demangled = ["$l": left, "$lg": leftG, "$r": right, "$plain": "M.Left.f() -> ()"]
    let resolver = Disassembler.ReferenceResolver(
        names: [0x30: "sub_30", 0x40: "sub_40", 0x50: "M.Left.f() -> ()"], stringRanges: [], machO: machO,
        demangleSymbol: { demangled[$0] },
        foldedCandidates: [0x30: ["$l", "$plain", "$r"], 0x40: ["$l", "$lg"], 0x50: ["$l", "$plain"]],
        witnessTables: [(0x100 ..< 0x120, "M.Left : M.P in M"), (0x120 ..< 0x140, "M.Right : M.P in M")]
    )
    #expect(resolver.witnessName(at: 0x30, loadedFrom: 0x108) == left)
    #expect(resolver.witnessName(at: 0x30, loadedFrom: 0x128) == right)
    // Outside every table: nothing proves a candidate.
    #expect(resolver.witnessName(at: 0x30, loadedFrom: 0x148) == nil)
    // Two of the table's own witnesses folded together.
    #expect(resolver.witnessName(at: 0x40, loadedFrom: 0x108) == nil)
    // An address `names` did not decline keeps its own name.
    #expect(resolver.witnessName(at: 0x50, loadedFrom: 0x108) == nil)
    // Two tables' symbols at one address name two conformances.
    var aliased = resolver
    aliased.witnessTables = [(0x100 ..< 0x120, "M.Left : M.P in M"), (0x100 ..< 0x120, "M.Right : M.P in M")]
    #expect(aliased.witnessName(at: 0x30, loadedFrom: 0x108) == nil)
}

/// `libMarkerSymbols.dylib` (markersymbols.s): TinyCC's linker marker
/// symbols (`__start_text`, `__init_array_start`, `__init_array_end`) sit
/// on `add3`'s address. The heading declined to `sub_<addr>`, but the call
/// in `callAdd3`, which is `add3(1, 2, 3)`, read `→ _init_array_end`
/// (filtered) and `bl _add3  ; → add3` (unfiltered, objdump's pick). A
/// marker is one more symbol at the address, so the call takes the
/// heading's name, on both front ends and in every view.
@Test func aCallToAnAddressCarryingMarkerSymbolsTakesNoMarkersNameIfPresent() async throws {
    let markers = "Fixtures/Sample/libMarkerSymbols.dylib"
    guard FileManager.default.fileExists(atPath: markers) else { return }
    let machO = try BinaryLoader.load(path: markers)
    let add3 = try #require(machO.symbols.first { $0.name == "_add3" })
    let names = Set(machO.symbols.filter { $0.offset == add3.offset }.map(\.name))
    #expect(names == ["_add3", "__start_text", "__init_array_start", "__init_array_end"], "\(names)")
    let sub = "sub_\(String(add3.offset, radix: 16))"
    for filter in [nil, "callAdd3"] as [String?] {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: markers, functionFilter: filter)
        }
        let caller = try #require(functions.first { $0.symbol == "_callAdd3" }, "\(functions.map(\.symbol))")
        for (view, text) in [("pseudo", caller.renderPseudo()), ("structured", caller.renderStructured()),
                             ("listing", caller.render())] {
            // objdump writes the symbol it picked into the text (`bl _add3`).
            #expect(!text.contains("init_array") && !text.contains("start_text") && !text.contains("_add3")
                        && !text.contains("add3("),
                    "\(filter ?? "unfiltered") \(view): \(text)")
            #expect(text.contains(view == "listing" ? "→ \(sub)  args(1, 2, 3)" : "\(sub)(1, 2, 3)"),
                    "\(filter ?? "unfiltered") \(view): \(text)")
        }
    }
}
