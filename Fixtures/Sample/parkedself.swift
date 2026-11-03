// A caller parks a temporary in callee-saved x20 before calling a function
// that takes no `self` there (-O): a by-value enum method, whose self is a
// trailing word, and a local function. True behaviour: freshEnum returns
// v + md.weight(v) + ext2(s) with v = ext(k); useLocal the same through
// inner(v); neither callee reads x20.
public enum Mode: Int { case a, b, c
    @inline(never) public func weight(_ k: Int) -> Int { rawValue &* 17 &+ k } }
@inline(never) public func ext(_ k: Int) -> Int { k &* 3 &+ 1 }
@inline(never) public func ext2(_ k: Int) -> Int { k &* 5 &+ 2 }
@inline(never) public func freshEnum(_ k: Int, _ md: Mode) -> Int { let v = ext(k); let s = md.weight(v); return v &+ s &+ ext2(s) }
@inline(never) public func useLocal(_ k: Int) -> Int {
    @inline(never) func inner(_ x: Int) -> Int { x &* 19 &+ 4 }
    let v = ext(k); let s = inner(v); return v &+ s &+ ext2(s)
}
