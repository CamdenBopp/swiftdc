// Collections probe 3: trap conditions and loop bounds. True behaviour in comments.

// a[Int(u)]: traps iff u > Int.max (sign bit set) or Int(u) >= count.
public func atU(_ a: [Int], _ u: UInt) -> Int { a[Int(u)] }
// a[Int(j)] with Int32 j: traps iff j < 0 or j >= count (sign-extended).
public func at32(_ a: [Int], _ j: Int32) -> Int { a[Int(j)] }
// Sum a[i] for i in lo...hi (wrapping); traps if lo > hi or out of bounds.
public func closedRange(_ a: [Int], _ lo: Int, _ hi: Int) -> Int { var s = 0; for i in lo...hi { s &+= a[i] }; return s }
// Sum of (0..<n).reversed() of i*i wrapping.
public func revSq(_ n: Int) -> Int { var s = 0; for i in (0..<n).reversed() { s &+= i &* i }; return s }
// Returns a.last! ; traps when empty.
public func lastBang(_ a: [Int]) -> Int { a.last! }
// Returns count of i in 0..<n with i % 3 == 0 (n >= 0 else range trap).
public func mod3(_ n: Int) -> Int { var c = 0; for i in 0..<n where i % 3 == 0 { c &+= 1 }; return c }
// Returns a[a.count / 2]; traps when empty.
public func mid(_ a: [Int]) -> Int { a[a.count / 2] }
// Returns true iff the array is sorted ascending (non-strict).
public func isSorted(_ a: [Int]) -> Bool { var i = 1; while i < a.count { if a[i - 1] > a[i] { return false }; i += 1 }; return true }
// Binary search: index of v in sorted a, or -1.
public func bsearch(_ a: [Int], _ v: Int) -> Int {
  var lo = 0, hi = a.count
  while lo < hi { let m = (lo + hi) / 2; if a[m] < v { lo = m + 1 } else if a[m] > v { hi = m } else { return m } }
  return -1
}
// Returns a[i] for UInt16 array, as Int; traps on bounds.
public func u16At(_ a: [UInt16], _ i: Int) -> Int { Int(a[i]) }
// Copies: returns Array(a.prefix(k)).count == min(k, count); traps if k < 0.
public func prefixCount(_ a: [Int], _ k: Int) -> Int { Array(a.prefix(k)).count }
// Matrix element m[r][c] for [[Int]]; traps on either index.
public func m2(_ m: [[Int]], _ r: Int, _ c: Int) -> Int { m[r][c] }
