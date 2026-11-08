// -O drops an unused parameter into a function signature specialization
// (`<Arg[0] = Dead> of helperI(Swift.Int, Swift.Int)`), which takes `b` in
// x0, and keeps a thunk under the original name that moves x1 into x0.
// True behaviour: helperI returns b * 23, helperS returns i * 19; neither
// reads its first parameter, and neither is a method.
@inline(never) func helperI(_ a: Int, _ b: Int) -> Int { b &* 23 }
@inline(never) func helperS(_ s: String, _ i: Int) -> Int { i &* 19 }
public func callI(_ i: Int, _ j: Int) -> Int { helperI(i, j) &+ helperI(j, i) }
public func callS(_ i: Int) -> Int { helperS("x", i) &+ helperS("y", i &+ 1) }
