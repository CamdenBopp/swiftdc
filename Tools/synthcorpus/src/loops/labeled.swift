// LEVELS: O Osize Onone
// Labeled break/continue across three and four nested loops, and early
// return and throw from the innermost loop.
// TRUE behaviour:
//   find3(n):  for a in 0..<n, b in 0..<n, c in 0..<n: if probe(a,b,c) == 0
//              return a*10000 + b*100 + c (first hit in lexical order); -1 if none.
//   skip3(n):  for a, b, c in 0..<n: p = probe(a,b,c); p < 0 continues the
//              outer loop (next a), p > 5 continues the middle loop (next b),
//              otherwise sink(p). sink only ever sees p in 0...5.
//   deep4(n):  four loops a, b, c, d; `break outer` when probe4 == 1 (stops all),
//              `continue second` when probe4 == 2 (next b); sink(d) otherwise.
//   throwing(n): for a, b, c in 0..<n: if probe(a,b,c) == 99 throw Bad.hit(a);
//              sink(c) otherwise.
// Early return of a computed value must not read as falling off the loops:
// EXPECT structured * find3 :: probe(
// EXPECT structured * deep4 :: probe4(
// -O: `break outer` is the function's only exit after the loops: a return.
// EXPECT structured O deep4 :: re:if \(r0 == 1\) \{\n\s*return
// EXPECT structured * throwing :: throw
// EXPECT structured * skip3 :: sink(
// EXPECT structured * throwing :: probe(
@inline(never) public func probe(_ a: Int, _ b: Int, _ c: Int) -> Int { a ^ (b &* 7) ^ (c &* 13) }
@inline(never) public func probe4(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Int { (a ^ b ^ c ^ d) & 3 }
@inline(never) public func sink(_ x: Int) { print(x) }
public enum Bad: Error { case hit(Int) }

public func find3(_ n: Int) -> Int {
    for a in 0..<n { for b in 0..<n { for c in 0..<n {
        if probe(a, b, c) == 0 { return a &* 10000 &+ b &* 100 &+ c }
    } } }
    return -1
}
public func skip3(_ n: Int) {
    outer: for a in 0..<n {
        middle: for b in 0..<n {
            for c in 0..<n {
                let p = probe(a, b, c)
                if p < 0 { continue outer }
                if p > 5 { continue middle }
                sink(p)
            }
        }
    }
}
public func deep4(_ n: Int) {
    outer: for a in 0..<n {
        second: for b in 0..<n {
            for c in 0..<n {
                for d in 0..<n {
                    let p = probe4(a, b, c, d)
                    if p == 1 { break outer }
                    if p == 2 { continue second }
                    sink(d)
                }
            }
        }
    }
}
public func throwing(_ n: Int) throws {
    for a in 0..<n { for b in 0..<n { for c in 0..<n {
        if probe(a, b, c) == 99 { throw Bad.hit(a) }
        sink(c)
    } } }
}
