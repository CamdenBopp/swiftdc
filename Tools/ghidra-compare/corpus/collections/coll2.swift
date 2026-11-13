// Collections probe 2. True behaviour in each comment.
public struct P { public var x: Int; public var y: Int; public var z: Int32 }

// Returns a[i].y: element stride 24 (x@0, y@8, z@16), base 0x20; traps if i out of range.
public func py(_ a: [P], _ i: Int) -> Int { a[i].y }
// Returns Int(a[i].z), sign-extended.
public func pz(_ a: [P], _ i: Int) -> Int { Int(a[i].z) }
// Returns a[i+1] - a[i] (wrapping); traps if i+1 overflows, i<0, i+1>=count.
public func diff(_ a: [Int], _ i: Int) -> Int { a[i + 1] &- a[i] }
// Counts adjacent increasing pairs; loop i in 1..<count; empty -> 0.
public func incPairs(_ a: [Int]) -> Int { var c = 0; if a.count < 2 { return 0 }; for i in 1..<a.count where a[i] > a[i-1] { c &+= 1 }; return c }
// Returns true iff a contains v (UInt8).
public func hasByte(_ a: [UInt8], _ v: UInt8) -> Bool { a.contains(v) }
// Inserts k->v into d.
public func dput(_ d: inout [Int: Int], _ k: Int, _ v: Int) { d[k] = v }
// Inserts v into set, returns whether newly inserted.
public func sins(_ s: inout Set<Int>, _ v: Int) -> Bool { s.insert(v).inserted }
// Slice element: s[i] where s is ArraySlice; traps if i < startIndex or i >= endIndex.
public func sliceAt(_ s: ArraySlice<Int>, _ i: Int) -> Int { s[i] }
// Slice count: endIndex - startIndex.
public func sliceCount(_ s: ArraySlice<Int>) -> Int { s.count }
// Last index of a value <= t scanning backwards, or -1.
public func lastLE(_ a: [Int], _ t: Int) -> Int { var i = a.count - 1; while i >= 0 { if a[i] <= t { return i }; i -= 1 }; return -1 }
// UInt32 array sum (wrapping), zero-extended into UInt64.
public func u32sum(_ a: [UInt32]) -> UInt64 { var s: UInt64 = 0; for x in a { s &+= UInt64(x) }; return s }
// Returns a.first ?? 7
public func firstOr7(_ a: [Int]) -> Int { a.first ?? 7 }
// Returns count of elements that are even.
public func evens(_ a: [Int]) -> Int { a.reduce(0) { $0 &+ ($1 & 1 == 0 ? 1 : 0) } }
// Stride by 2 over indices, sum a[i] wrapping.
public func evIdx(_ a: [Int]) -> Int { var s = 0; for i in stride(from: 0, to: a.count, by: 2) { s &+= a[i] }; return s }
// Returns Int8 element sign-extended.
public func i8At(_ a: [Int8], _ i: Int) -> Int { Int(a[i]) }
// Returns a.dropFirst(k).first ?? -1
public func dropK(_ a: [Int], _ k: Int) -> Int { a.dropFirst(k).first ?? -1 }
// Removes last element; traps when empty.
public func popL(_ a: inout [Int]) -> Int { a.removeLast() }
