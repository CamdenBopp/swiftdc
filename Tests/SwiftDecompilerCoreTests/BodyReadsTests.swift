import Foundation
import Testing
@testable import SwiftDecompilerCore

private let fixture = "Fixtures/Sample/libBodyReads.dylib"

private func pseudo(_ name: String) async throws -> String {
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: fixture) }
    return try #require(functions.first { $0.displayName == name }, "no \(name)").renderPseudo()
}

/// A call to an in-image function no signature describes passed every
/// register through the highest its body reads, positionally, so a
/// register below that one which the body never reads showed the caller's
/// stale value: `body_reads.s`'s `useSecond` writes x0 before reading it
/// and rendered `useSecond(5, 7)`, and `accessorLike`, which reads only
/// x2 (by passing it to memset), rendered `accessorLike(5)`. An unread
/// register now gives no value.
@Test func aRegisterTheCalleeNeverReadsIsNoArgumentIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let second = try await pseudo("_callUseSecond")
    #expect(second.contains("useSecond(?, 7)"), Comment(rawValue: second))
    let accessor = try await pseudo("_callAccessorLike")
    #expect(accessor.contains("accessorLike()"), Comment(rawValue: accessor))
}
