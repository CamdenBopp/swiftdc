// Mutating stdlib calls on an inout array at -Osize.
// push2: appends v then w (two appends).
public func push2(_ a: inout [Int], _ v: Int, _ w: Int) { a.append(v); a.append(w) }
// reserve: a.reserveCapacity(n).
public func reserve(_ a: inout [Int], _ n: Int) { a.reserveCapacity(n) }
// clear: a.removeAll(keepingCapacity: true).
public func clear(_ a: inout [Int]) { a.removeAll(keepingCapacity: true) }
// insertFront: a.insert(v, at: 0).
public func insertFront(_ a: inout [Int], _ v: Int) { a.insert(v, at: 0) }
