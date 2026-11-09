import Foundation
import Testing
@testable import SwiftDecompilerCore

private func structured(_ path: String) async throws -> [String: String] {
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    return Dictionary(functions.map { ($0.displayName, $0.renderStructured()) }, uniquingKeysWith: { a, _ in a })
}

/// `[[arg - 8] + k]` called with the same argument where the witness takes
/// its metadata is that argument's value witness k (`valueWitnessCall`).
/// The same loads with another argument passed as the metadata, or a load
/// at `-16`, prove nothing and stay unresolved.
@Test func aValueWitnessThroughArgumentMetadataIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libValueWitnessArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try await structured(path)
    #expect(text["_vwDestroy"]?.contains("destroy value witness for arg1(arg0, arg1)") == true, "\(text["_vwDestroy"] ?? "")")
    for name in ["_vwOtherMetadata", "_vwNotTheTable"] {
        #expect(text[name]?.contains("value witness") == false, "\(name)")
        #expect(text[name]?.contains("unresolved call") == true, "\(name)")
    }
}

/// A stripped generic function the optimizer never specialized receives
/// its metadata as an argument: `assignCopy` destroys `a`, and
/// `duplicate` copies `x` into a temporary and takes it into `box`.
@Test func aStrippedGenericFunctionsValueWitnessesAreNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libArgumentWitness.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let all = try await structured(path).values.joined(separator: "\n")
    // Named for an operation, still not an address: unresolved dispatch.
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let graph = CallGraph(functions: functions)
    #expect(graph.unresolvedCallSites == 3 && graph.externalCallSites == 1)
    #expect(all.contains("destroy value witness for arg2(arg0, arg2)"))
    #expect(all.contains("initializeWithCopy value witness for arg2(?, arg0, arg2)"))
    #expect(all.contains("initializeWithTake value witness for arg2(arg1, ?, arg2)"))
}

/// An enum's three witnesses follow its size, stride, flags and extra
/// inhabitant count (`+0x58`). Only an enum's table has them, so a call
/// through one is named only when it passes the metadata back as its last
/// argument.
@Test func anEnumValueWitnessIsNamedOnlyWithItsMetadataIfPresent() async throws {
    let path = "Fixtures/Sample/libValueWitnessArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try await structured(path)
    #expect(text["_vwEnumTag"]?.contains("getEnumTag value witness for arg1(arg0, arg1)") == true)
    #expect(text["_vwInjectTag"]?.contains("destructiveInjectEnumTag value witness for arg2(arg0, arg1, arg2)") == true)
    #expect(text["_vwEnumTagOther"]?.contains("unresolved call") == true)
    #expect(text["_vwEnumTagOther"]?.contains("value witness") == false)
}

/// The same rule for metadata the loader binds: an enum slot read through
/// `Swift.Int`'s table, called with another register as T, is no witness
/// call anything proves.
@Test func anEnumSlotWithoutItsMetadataStaysUnresolvedIfPresent() async throws {
    let path = "Fixtures/Sample/libVoidWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try await structured(path)
    #expect(text["_vwEnumSlotOther"]?.contains("unresolved call") == true, "\(text["_vwEnumSlotOther"] ?? "")")
    #expect(text["_vwEnumSlotOther"]?.contains("value witness") == false)
}

/// An associated type's metadata comes from swift_getAssociatedTypeWitness
/// with the associated type's descriptor, and its value witnesses are named
/// for that associated type of the conforming type: `A.Element` where a
/// signature names A, `arg1.Element` stripped. A call that does not pass
/// the metadata back stays unresolved.
@Test func anAssociatedTypesValueWitnessIsNamedIfPresent() async throws {
    let named = "Fixtures/Sample/libAssociatedWitness.dylib", stripped = "Fixtures/Sample/libAssociatedWitness.stripped.dylib"
    let asm = "Fixtures/Sample/libVoidWitness.dylib"
    guard [named, stripped, asm].allSatisfy(FileManager.default.fileExists(atPath:)) else { return }
    // countAll sizes stack buffers from a type's runtime size, so its
    // stack pointer is unknown at its calls, and an unproved callee may
    // reuse any frame slot below it (callee stack lifetime): the witness
    // tables it spills are not kept across those calls, and its witness
    // calls stay unresolved rather than named from a stale slot. Each
    // associated type's metadata still reaches the call that needs it.
    for path in [named, stripped] {
        let text = try await structured(path).values.joined(separator: "\n")
        #expect(text.contains("associated type descriptor for Swift.Sequence.Element"), "\(path)")
        #expect(!text.contains(" value witness for ?."), "\(path)")
    }
    let text = try await structured(asm)
    #expect(text["_vwAssocDestroy"]?.contains("destroy value witness for arg6.Element(") == true, "\(text["_vwAssocDestroy"] ?? "")")
    #expect(text["_vwAssocOther"]?.contains("unresolved call") == true)
    #expect(text["_vwAssocOther"]?.contains("value witness") == false)
}
