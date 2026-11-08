import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The send each function makes, as the pseudo view spells it.
private func sends(in path: String) async throws -> [String: String] {
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    var sends: [String: String] = [:]
    for function in functions {
        let text = function.renderPseudo()
        guard let line = text.components(separatedBy: "\n")
            .first(where: { line in [" ints:", " longs:", " mixed:", " pairs:"].contains(where: line.contains) })
        else { continue }
        sends[function.displayName] = line.trimmingCharacters(in: .whitespaces)
    }
    return sends
}

/// Apple arm64 packs Objective-C stack arguments, and at -O clang merges the
/// stores of two packed ints into one eight-byte store
/// (`objc_packed_stack.m`). That slot is not the first int: `g:0x800000007`
/// claimed g's and h's bits together. Without a signature, a 16-byte struct
/// argument's second word was read as the next argument (`h:9`, true 8). A
/// typed send takes a stack argument only from a store that covers it and no
/// other argument; an untyped send takes one slot per argument only where
/// there is exactly one aligned store per argument.
@Test(arguments: ["Fixtures/Sample/libObjCPackedStack.dylib", "Fixtures/Sample/libObjCPackedStack.opt.dylib"])
func packedStackArgumentsAreReadOnlyFromTheirOwnStoreIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let optimized = path.hasSuffix(".opt.dylib")
    let found = try await sends(in: path)
    let expected: [String: String] = [
        // -O0 stores g and h apart: g's own four-byte store is g. h at sp+4
        // is not read from the eight-byte slots.
        "-[Packer sendInts]": optimized
            ? "return [self ints:1 b:2 c:3 d:4 e:5 f:6 g:? h:?]"
            : "return [self ints:1 b:2 c:3 d:4 e:5 f:6 g:7 h:?]",
        "-[Packer sendLongs]": "return [self longs:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]",
        "-[Packer sendMixed]": "return [self mixed:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]",
        "_untypedInts": "[? ints:1 b:2 c:3 d:4 e:5 f:6 g:? h:?]",
        "_untypedLongs": "[? longs:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]",
        "_untypedMixed": "[? mixed:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]",
        "_untypedPairs": "[? pairs:1 b:2 c:3 d:4 e:5 f:6 g:? h:?]",
    ]
    for (name, send) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(found[name] == send, "\(path) \(name): \(found[name] ?? "no send")")
    }
}

/// A stack argument's store is that argument alone only when it covers the
/// argument and no other argument starts inside it.
@Test func aStackStoreHoldsOnlyTheArgumentItCoversAlone() {
    // g at sp+0 and h at sp+4, both ints.
    #expect(ObjCArgumentABI.storeHoldsOnlyArgument(at: 0, bytes: 4, storedBytes: 4, stackStarts: [0, 4]))
    #expect(!ObjCArgumentABI.storeHoldsOnlyArgument(at: 0, bytes: 4, storedBytes: 8, stackStarts: [0, 4]))
    // An int at sp+8 stored as eight bytes, with nothing after it.
    #expect(ObjCArgumentABI.storeHoldsOnlyArgument(at: 8, bytes: 4, storedBytes: 8, stackStarts: [0, 8]))
    // A long stored as four bytes: its upper half is unknown.
    #expect(!ObjCArgumentABI.storeHoldsOnlyArgument(at: 0, bytes: 8, storedBytes: 4, stackStarts: [0]))
    // An unknown store.
    #expect(!ObjCArgumentABI.storeHoldsOnlyArgument(at: 0, bytes: 4, storedBytes: 0, stackStarts: [0]))
}
