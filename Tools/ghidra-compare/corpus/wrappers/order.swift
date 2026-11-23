public final class C { public var a: Int = 0; public var b: Int = 0; public var c: Int = 0; public init() {} }
// true: o.a = 5, then o.c = OLD a + 1 (non-adjacent fields, separate str)
public func rot(_ o: C) { let old = o.a; o.a = 5; o.c = old &+ 1 }
// true: o.a = v; o.b = OLD a (adjacent fields, likely stp)
public func shift(_ o: C, _ v: Int) { let old = o.a; o.a = v; o.b = old }
public struct S { public var p: Int; public var q: Int }
// true: swaps fields of inout s
public func swapPQ(_ s: inout S) { let t = s.p; s.p = s.q; s.q = t }
