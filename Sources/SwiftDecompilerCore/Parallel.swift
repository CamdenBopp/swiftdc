import Foundation
import Synchronization

/// Data-parallel helpers for pure per-item work over a whole image.
///
/// Results come back in input order, so output never depends on scheduling;
/// only work whose result is a pure function of its input belongs here.
enum Parallel {
    /// `items.map(transform)`, computed in chunks across the cores.
    static func map<T: Sendable, R: Sendable>(
        _ items: [T], chunk: Int = 256, _ transform: @Sendable (T) -> R
    ) -> [R] {
        guard items.count > chunk else { return items.map(transform) }
        let chunks = (items.count + chunk - 1) / chunk
        let parts = Mutex<[Int: [R]]>([:])
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            let low = index * chunk, high = min(low + chunk, items.count)
            let part = items[low..<high].map(transform)
            parts.withLock { $0[index] = part }
        }
        return parts.withLock { parts in (0..<chunks).flatMap { parts[$0] ?? [] } }
    }

    /// `range.map(transform)` in input order, with each chunk of consecutive
    /// indices handed to one call so it can set up per-thread state (a
    /// decoder) once.
    static func mapChunks<R: Sendable>(
        _ range: Range<Int>, chunk: Int, _ transform: @Sendable (Range<Int>) -> [R]
    ) -> [R] {
        guard range.count > chunk else { return transform(range) }
        let chunks = (range.count + chunk - 1) / chunk
        let parts = Mutex<[Int: [R]]>([:])
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            let low = range.lowerBound + index * chunk, high = min(low + chunk, range.upperBound)
            let part = transform(low ..< high)
            parts.withLock { $0[index] = part }
        }
        return parts.withLock { parts in (0..<chunks).flatMap { parts[$0] ?? [] } }
    }

    /// Runs `body` on every item across the cores, for its side effect on a
    /// thread-safe cache.
    static func forEach<T: Sendable>(_ items: [T], chunk: Int = 256, _ body: @Sendable (T) -> Void) {
        _ = map(items, chunk: chunk) { body($0) }
    }
}
