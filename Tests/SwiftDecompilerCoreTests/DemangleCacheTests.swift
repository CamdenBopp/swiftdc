import Testing
@testable import SwiftDecompilerCore

/// `Disassembler.demangle` is memoized because the same symbol is demangled many
/// times in one run (measured ~2.5x redundancy on the fixtures). These pin the
/// cache's contract: a distinct key is computed exactly once, and the result is
/// returned unchanged — including a `nil` result, so a symbol that demangles to
/// nothing is not recomputed on every reference.

@Test func demangleCacheComputesOncePerDistinctKey() {
    let cache = DemangleCache()
    var computes = 0

    #expect(cache.value(for: "a") { _ in computes += 1; return "A" } == "A")
    #expect(cache.value(for: "a") { _ in computes += 1; return "A" } == "A") // hit
    #expect(computes == 1)

    #expect(cache.value(for: "c") { _ in computes += 1; return "C" } == "C")
    #expect(computes == 2) // a new key computes
}

@Test func demangleCacheMemoizesNilResults() {
    let cache = DemangleCache()
    var computes = 0

    // A symbol that demangles to nothing is a real, cacheable answer.
    #expect(cache.value(for: "b") { _ in computes += 1; return nil } == nil)
    // The second lookup must NOT recompute — the closure here would fail the
    // test if it ran, proving the nil was cached rather than the key treated
    // as absent.
    #expect(cache.value(for: "b") { _ in
        Issue.record("recomputed a cached nil result")
        computes += 1
        return "WRONG"
    } == nil)
    #expect(computes == 1)
}
