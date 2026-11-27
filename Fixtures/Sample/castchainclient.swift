// Two conditional casts in a row. When the first fails its result, nil, is
// still in x0, and the compiler asks for the second class's metadata with
// that zero as the request word instead of loading a fresh 0.
//
// classify(k, n, b): o = ccMake(k, n).
//   o is CCOne: n &+ b.  o is CCTwo: n &* b.  Otherwise b.
import CastChainKit

@inline(never) public func classify(_ k: Int, _ n: Int, _ b: Int) -> Int {
    let o = ccMake(k, n)
    if let one = o as? CCOne { return one.n &+ b }
    if let two = o as? CCTwo { return two.n &* b }
    return b
}
