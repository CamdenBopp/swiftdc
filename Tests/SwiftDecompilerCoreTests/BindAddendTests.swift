import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An import whose 64-bit addend has the top bit set is read without a
/// trap. The direct retain/release runtime binds its mask as
/// `__swift_retainRelease_slowpath_mask_v1 + 0x8000000000000000`, and
/// MachOKit's `addend` converts that field to `Int`: every `disasm` view,
/// `xrefs` and `analyze` died with SIGTRAP on such an image
/// (`bindaddend.s`).
@Test func aBindWithATopBitAddendIsReadIfPresent() async throws {
    let path = "Fixtures/Sample/libBindAddend.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    #expect(functions.map(\.displayName).sorted() == ["_keep", "_read_mask"])
    // The stub's own bind has no addend, so the retain is still recognised.
    let keep = try #require(functions.first { $0.displayName == "_keep" }).render()
    #expect(keep.contains("→ objc_retain"), Comment(rawValue: keep))
    // The bound slot is not named as plain `malloc`: its addend moves it.
    let read = try #require(functions.first { $0.displayName == "_read_mask" }).render()
    #expect(!read.contains("malloc"), Comment(rawValue: read))
}
