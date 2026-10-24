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

/// The `args(…)` note of each call to `callee` in `function`'s listing.
private func noteArguments(_ callee: String, in function: DisassembledFunction) -> [[String]] {
    function.instructions.compactMap { insn -> [String]? in
        guard insn.controlFlow == .call || insn.controlFlow == .branch,
              let annotation = insn.annotation, annotation.hasPrefix("→ \(callee)"),
              let open = annotation.range(of: "  args(") else { return nil }
        var depth = 1
        var index = open.upperBound
        while index < annotation.endIndex, depth > 0 {
            if annotation[index] == "(" { depth += 1 } else if annotation[index] == ")" { depth -= 1 }
            if depth > 0 { index = annotation.index(after: index) }
        }
        return DisassembledFunction.splitTopLevelArguments(annotation[open.upperBound..<index])
    }
}

/// A call whose arguments were all untracked was trimmed of them and read
/// as taking none: `variadic.m`'s `churn(a, b, c, d)` over untracked C
/// parameters rendered `churn()`. Every register the body's own
/// instructions read is a parameter, and an unknown one is `?`.
@Test func aBodyBoundedCallShowsEveryParameterItReadsIfPresent() async throws {
    let path = "Fixtures/Sample/libVariadic.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "describe")
    }
    let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("churn(?, ?, ?, ?)"), Comment(rawValue: text))
}

/// The padding counts only what the body's own instructions read. A call
/// inside it proves no parameter: `swift_willThrowTyped`'s in-image body
/// spills x0-x2 and reaches x6 and x7 only by calling a function of unknown
/// arity, and padded to those it read as taking eight
/// (`libTypedThrowsNever`); `accessorLike` reads x2 only by passing it to
/// memset and is padded to nothing.
@Test func aBodyBoundedCallPadsOnlyToWhatTheBodyReadsIfPresent() async throws {
    let path = "Fixtures/Sample/libTypedThrowsNever.dylib"
    guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: fixture)
    else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let lists = functions.flatMap { noteArguments("swift_willThrowTyped", in: $0) }
    #expect(!lists.isEmpty && lists.allSatisfy { $0.count == 3 && !$0.contains("?") }, "\(lists)")
    let accessor = try await pseudo("_callAccessorLike")
    #expect(accessor.contains("accessorLike()"), Comment(rawValue: accessor))
}
