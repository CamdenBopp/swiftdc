// Closure-propagated function signature specializations (-O). The closure
// argument is folded into the specialization, whose demangled name prints
// an unclosed `[` (`<Arg[0] = [Closure Propagated : …, Argument Types :
// [Swift.Int]> of ClosProp.apply(…) -> Swift.Int`). Each caller tail-calls
// it and returns its Int: `return …(arg0)`, not a bare statement.
@inline(never) public func apply(_ f: (Int) -> Int, _ k: Int) -> Int { f(k) &+ 1 }
public func noCapture(_ k: Int) -> Int { apply({ $0 &* 3 }, k) }
public func captures(_ k: Int, _ m: Int) -> Int { apply({ $0 &* m }, k) }
public func capturesTwo(_ k: Int, _ m: Int, _ n: Int) -> Int { apply({ $0 &* m &+ n }, k) }
