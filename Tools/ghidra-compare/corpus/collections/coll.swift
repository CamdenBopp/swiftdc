// Collections probe fixture. Each function's true behaviour is in its comment.

// Returns a[i]; traps iff i < 0 or i >= a.count (unsigned compare i >= count).
public func at(_ a: [Int], _ i: Int) -> Int { a[i] }

// Returns a.count (load [x0+0x10]).
public func cnt(_ a: [Int]) -> Int { a.count }

// Returns a.capacity (load [x0+0x18] >> 1).
public func cap(_ a: [Int]) -> Int { a.capacity }

// Sum of all elements with overflow trap; loop i in 0..<count.
public func sumAll(_ a: [Int]) -> Int { var s = 0; for x in a { s += x }; return s }

// Sum of elements > t.
public func sumAbove(_ a: [Int], _ t: Int) -> Int { a.filter { $0 > t }.reduce(0, +) }

// Returns index of first element == v, or -1.
public func firstIdx(_ a: [Int], _ v: Int) -> Int { a.firstIndex(of: v) ?? -1 }

// Returns first element > t or 0.
public func firstAbove(_ a: [Int], _ t: Int) -> Int { a.first(where: { $0 > t }) ?? 0 }

// Sum over stride(from: 0, to: n, by: 3); n > 0 assumed nothing.
public func strideSum(_ n: Int) -> Int { var s = 0; for i in stride(from: 0, to: n, by: 3) { s &+= i }; return s }

// Sum of a..<b; traps if a > b (range precondition).
public func rangeSum(_ a: Int, _ b: Int) -> Int { var s = 0; for i in a..<b { s &+= i }; return s }

// Closed range sum 0...n, traps if n < 0.
public func closedSum(_ n: Int) -> Int { var s = 0; for i in 0...n { s &+= i }; return s }

// Appends v to a in place (CoW: isUniquelyReferenced, grow when count >= capacity).
public func push(_ a: inout [Int], _ v: Int) { a.append(v) }

// Swaps a[i], a[j].
public func sw(_ a: inout [Int], _ i: Int, _ j: Int) { a.swapAt(i, j) }

// a[i] = v; traps if i out of bounds.
public func setAt(_ a: inout [Int], _ i: Int, _ v: Int) { a[i] = v }

// Array of n copies of v.
public func rep(_ v: Int, _ n: Int) -> [Int] { Array(repeating: v, count: n) }

// Map doubling each element (wrapping).
public func dbl(_ a: [Int]) -> [Int] { a.map { $0 &* 2 } }

// Dictionary lookup, default 0.
public func dget(_ d: [String: Int], _ k: String) -> Int { d[k] ?? 0 }

// Set contains.
public func scontains(_ s: Set<Int>, _ v: Int) -> Bool { s.contains(v) }

// Sum of dictionary values (wrapping).
public func dsum(_ d: [Int: Int]) -> Int { var s = 0; for (_, v) in d { s &+= v }; return s }

// Sum of zip products (wrapping), length min(a.count,b.count).
public func dot(_ a: [Int], _ b: [Int]) -> Int { var s = 0; for (x, y) in zip(a, b) { s &+= x &* y }; return s }

// Sum of index*element (wrapping).
public func wsum(_ a: [Int]) -> Int { var s = 0; for (i, x) in a.enumerated() { s &+= i &* x }; return s }

// Sum of slice a[lo..<hi] (wrapping); traps if out of range.
public func sliceSum(_ a: [Int], _ lo: Int, _ hi: Int) -> Int { var s = 0; for x in a[lo..<hi] { s &+= x }; return s }

// ContiguousArray last element or -1.
public func clast(_ a: ContiguousArray<Int>) -> Int { a.last ?? -1 }

// Buffer pointer sum (wrapping).
public func bsum(_ a: [Int]) -> Int { a.withUnsafeBufferPointer { b in var s = 0; for x in b { s &+= x }; return s } }

// Sort descending.
public func sdesc(_ a: [Int]) -> [Int] { a.sorted { $0 > $1 } }

// Lazy map filter count: count of elements whose square > 100.
public func lazyCount(_ a: [Int]) -> Int { a.lazy.map { $0 &* $0 }.filter { $0 > 100 }.count }

// Reserve then append 0..<n.
public func build(_ n: Int) -> [Int] { var a: [Int] = []; a.reserveCapacity(n); for i in 0..<n { a.append(i) }; return a }

// isEmpty: count == 0.
public func empty(_ a: [Int]) -> Bool { a.isEmpty }

// UInt8 array element at i, zero-extended.
public func byteAt(_ a: [UInt8], _ i: Int) -> Int { Int(a[i]) }

// Int32 element at i, sign-extended.
public func i32At(_ a: [Int32], _ i: Int) -> Int { Int(a[i]) }

// Max element or Int.min.
public func mx(_ a: [Int]) -> Int { a.max() ?? Int.min }

// Reverse loop: sum from last to first of a[i]*i (wrapping).
public func rsum(_ a: [Int]) -> Int { var s = 0; for i in stride(from: a.count - 1, through: 0, by: -1) { s &+= a[i] &* i }; return s }
