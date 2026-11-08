import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Parallel work must not change output: results come back in input order,
/// whatever order the chunks finish in. Sizes straddle the chunk boundary.
@Test func parallelMapEqualsMapInOrder() {
    for count in [0, 1, 255, 256, 257, 10_000] {
        let items = Array(0..<count)
        #expect(Parallel.map(items) { $0 &* 31 &+ 7 } == items.map { $0 &* 31 &+ 7 }, "\(count)")
        #expect(Parallel.map(items, chunk: 7) { String($0) } == items.map { String($0) }, "\(count)")
    }
}
