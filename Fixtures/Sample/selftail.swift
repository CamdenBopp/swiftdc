// A method that tail-calls itself through self's vtable (-O): `br x1` with
// x1 loaded from the class's slot for countdown, which resolves to this
// function's own entry. The target is a call (an override may own the
// slot), not a jump: read as a branch target it became an edge back to the
// entry, and the call a `while` loop that never changes arg0.
//
// True behaviour: countdown(n) returns 0 when n <= 0, otherwise the
// result of self.countdown(n - 1), called once through the vtable.
open class Counter {
    public init() {}
    open func countdown(_ n: Int) -> Int {
        if n <= 0 { return 0 }
        return countdown(n &- 1)
    }
}
