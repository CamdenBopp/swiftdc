// Closure-propagated function signature specializations (-O). The closure
// argument is folded into the specialization, whose demangled name prints
// an unclosed `[` (`<Arg[0] = [Closure Propagated : …, Argument Types :
// [Swift.Int]> of ClosProp.apply(…) -> Swift.Int`). Each caller tail-calls
// it and returns its Int: `return …(arg0)`, not a bare statement.
@inline(never) public func apply(_ f: (Int) -> Int, _ k: Int) -> Int { f(k) &+ 1 }
@inline(never) public func noCapture(_ k: Int) -> Int { apply({ $0 &* 3 }, k) }
@inline(never) public func captures(_ k: Int, _ m: Int) -> Int { apply({ $0 &* m }, k) }
@inline(never) public func capturesTwo(_ k: Int, _ m: Int, _ n: Int) -> Int { apply({ $0 &* m &+ n }, k) }

// C entry points let native tests identify the fixture independently of its
// reconstructed argument list. Small test inputs avoid conversion overflow.
@_cdecl("closprop_no_capture")
public func nativeNoCapture(_ k: Int64) -> Int64 { Int64(noCapture(Int(k))) }
@_cdecl("closprop_captures")
public func nativeCaptures(_ k: Int64, _ m: Int64) -> Int64 { Int64(captures(Int(k), Int(m))) }
@_cdecl("closprop_captures_two")
public func nativeCapturesTwo(_ k: Int64, _ m: Int64, _ n: Int64) -> Int64 { Int64(capturesTwo(Int(k), Int(m), Int(n))) }
