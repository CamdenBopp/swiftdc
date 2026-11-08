import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A stripped image keeps no symbol for a witness of a conformance to
/// another image's protocol (`Point: Equatable`), but the conformance
/// descriptor lists it: the requirement's bound method descriptor and the
/// witness's code. `disasm` names it from there, as its `TW` symbol
/// demangles, where it used to read `sub_100001164`.
struct ResilientWitnessNamingTests {
    /// The oracle is the unstripped image: every function the stripped one
    /// names as a protocol witness carries the name the unstripped symbol
    /// table gives that address, over every stripped fixture with an
    /// unstripped original.
    @Test func everyStrippedWitnessNameIsTheUnstrippedSymbolsIfPresent() async throws {
        let pairs = MemberAddressTests.strippedPairs()
        guard !pairs.isEmpty else { return }
        var compared = 0
        for pair in pairs {
            let stripped = try await Disassembler(preset: .default).disassemble(path: pair.stripped)
            let unstripped = try await Disassembler(preset: .default).disassemble(path: pair.unstripped)
            let truth = Dictionary(unstripped.map { ($0.startAddress, $0.displayName) }, uniquingKeysWith: { a, _ in a })
            for function in stripped where function.displayName.hasPrefix("protocol witness for ") && function.source == .metadata {
                compared += 1
                #expect(truth[function.startAddress] == function.displayName,
                        "\(pair.stripped) 0x\(String(function.startAddress, radix: 16)): \(function.displayName)")
            }
        }
        #expect(compared > 0, "no stripped witness was named, so the oracle is vacuous")
    }

    /// The reported addresses: both `==` witnesses, named apart.
    @Test func strippedEquatableWitnessesAreNamedIfPresent() async throws {
        let path = "Fixtures/Sample/sample.stripped"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let functions = try await Disassembler(preset: .default).disassemble(path: path)
        let names = Dictionary(functions.map { ($0.startAddress, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        #expect(names[0x100001164] == "protocol witness for static Swift.Equatable.== infix(A, A) -> Swift.Bool in conformance sample.Point : Swift.Equatable in sample")
        #expect(names[0x100001508] == "protocol witness for static Swift.Equatable.== infix(A, A) -> Swift.Bool in conformance sample.Direction : Swift.Equatable in sample")
    }

    /// Witnesses metadata reads but must not name (`witnessnaming.swift`):
    /// a generic type's, whose symbol spells `Box<A>`, and `Mode`'s, whose
    /// bodies the linker folded with the private `Key`'s. The unstripped
    /// symbol table says where each one is; stripped, none of those
    /// addresses may carry a witness name.
    @Test func aGenericOrFoldedWitnessIsNotNamedIfPresent() async throws {
        let unstripped = "Fixtures/Sample/libWitnessNaming.dylib"
        let path = "Fixtures/Sample/libWitnessNaming.stripped.dylib"
        guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: unstripped) else { return }
        let symbols = try BinaryLoader.load(path: unstripped).symbols
        let box = symbols.filter { $0.name.hasSuffix("TW") && $0.name.contains("3BoxV") }.map { UInt64($0.offset) }
        let mode = symbols.filter { $0.name.hasSuffix("TW") && $0.name.contains("4ModeO") }.map { UInt64($0.offset) }
        #expect(box.count == 1 && mode.count == 4, "\(box) \(mode)")
        let functions = try await Disassembler(preset: .default).disassemble(path: path)
        let names = Dictionary(functions.map { ($0.startAddress, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        for address in box + mode {
            let name = try #require(names[address], "no function at 0x\(String(address, radix: 16))")
            #expect(!name.hasPrefix("protocol witness for"), "0x\(String(address, radix: 16)): \(name)")
        }
        // Each folded body keeps `Mode`'s witness as its one candidate; the
        // owner metadata cannot name adds none.
        let metadata = MetadataSymbolizer().functionNames(in: try BinaryLoader.load(path: path))
        for address in mode {
            let candidates = metadata.folded[address] ?? []
            #expect(candidates.count == 1 && candidates.allSatisfy { $0.contains("conformance WitnessNaming.Mode :") },
                    "0x\(String(address, radix: 16)): \(candidates)")
        }
    }
}
