// add with overflow trap: traps iff a+b overflows.
public func addT(_ a: Int, _ b: Int) -> Int { a + b }
// Loop: s = sum of 1..n of i (checked), traps on overflow.
public func triT(_ n: Int) -> Int { var s = 0; var i = 0; while i < n { i &+= 1; s += i }; return s }
// Loop over pointer: sum of p[0..<n] checked.
public func psum(_ p: UnsafePointer<Int>, _ n: Int) -> Int { var s = 0; var i = 0; while i < n { s += p[i]; i &+= 1 }; return s }
