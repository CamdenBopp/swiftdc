// Fixture: Swift stack shapes. True behaviour per function.
@inline(never) public func consume(_ p: UnsafeMutableRawPointer, _ n: Int) { blackHole &+= Int(bitPattern: p) &+ n }
public var blackHole = 0

// tempAlloc(n): stack temporary of n Ints (dynamic size: alloca or heap fallback).
// True: fills buf[i] = i + k, consume(base, n), returns buf[n-1] (or k when n == 0).
@inline(never) public func tempAlloc(_ n: Int, _ k: Int) -> Int {
    withUnsafeTemporaryAllocation(of: Int.self, capacity: n) { buf in
        for i in 0..<n { buf[i] = i &+ k }
        consume(UnsafeMutableRawPointer(buf.baseAddress!), n)
        return n == 0 ? k : buf[n - 1]
    }
}
// tempFixed(k): fixed 1024-Int temporary (8 KB frame). True: consume(base, 1024); returns buf[7] == k &+ 7.
@inline(never) public func tempFixed(_ k: Int) -> Int {
    withUnsafeTemporaryAllocation(of: Int.self, capacity: 1024) { buf in
        buf.initialize(repeating: k)
        buf[7] = k &+ 7
        consume(UnsafeMutableRawPointer(buf.baseAddress!), 1024)
        return buf[7]
    }
}
// tupleFrame(a, b): 8 KB tuple local. True: consume(&t, a); returns a &+ b.
public struct Big { var x: (Int, Int, Int, Int, Int, Int, Int, Int) }
@inline(never) public func bigTuple(_ a: Int, _ b: Int) -> Int {
    var arr = [Int](repeating: a, count: 4)
    arr[1] = b
    return arr.withUnsafeMutableBytes { p in consume(p.baseAddress!, a); return a &+ b }
}
// fpKeep(a, b): d8/d9 across call. True: consume(…, 1); returns a * b + a.
@inline(never) public func fpKeep(_ a: Double, _ b: Double) -> Double {
    var x = 0
    consume(&x, 1)
    return a * b + a
}
