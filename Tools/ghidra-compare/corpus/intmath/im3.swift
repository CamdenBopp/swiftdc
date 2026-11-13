// Bounds-check probes: the trap is program logic, not an overflow guard.
// True: d = a &- b; m = a < b ? 7 : d; traps iff m >= n (unsigned); returns m.
@inline(never) public func bound1(_ a: UInt, _ b: UInt, _ n: UInt) -> UInt {
    let d = a &- b
    let m = a < b ? 7 : d
    precondition(m < n)
    return m
}
// True: traps iff i >= n (unsigned), returns i &- 1 computed with subs.
@inline(never) public func bound2(_ i: UInt, _ n: UInt) -> UInt {
    let j = i &- 1
    let k = i == 0 ? 99 : j
    precondition(k < n)
    return k
}
// Array index: traps iff i < 0 || i >= count.
@inline(never) public func idx(_ a: [Int], _ i: Int) -> Int { a[i] }
