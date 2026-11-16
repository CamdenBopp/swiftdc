// A loop counter held in a register at -O and -Osize, not a stack slot.
// countUp lowers as `mov x19, #-3; L: add x19, x19, #3; bl sink;
// cmp x19, #0x3e5; b.lo L`: the counter is i + 3 at the test, which runs
// while i + 3 < 997 (unsigned), so sink sees 0, 3, …, 999.
// fromTen lowers as `mov w19, #0xc; L: sub x19, x19, #2; bl sink;
// cmp x19, #2; b.hi L`: sink sees 10, 8, 6, 4, 2.
@inline(never) public func sink(_ x: Int) { print(x) }

public func countUp() {
    var i = 0
    while i < 1000 { sink(i); i += 3 }
}

@inline(never) public func fromTen() {
    var i = 10
    repeat { sink(i); i -= 2 } while i > 0
}

// The test reads a closure's result, so its condition does not render:
// the counter must not be declared or stepped where nothing reads it.
@inline(never) public func untilLimit(_ limit: () -> Int) {
    var i = 0
    repeat { sink(i); i += 1 } while i != limit()
}

// A counter that starts from the argument. Wrapping keeps the -O loop to
// one block (`mov x19, x0; L: …; sub x19, x19, #2; cmp x19, #0; b.gt L`,
// or a `subs`): sink sees n, n - 2, … while the value stays positive.
@inline(never) public func countDown(_ n: Int) {
    var i = n
    repeat { sink(i); i &-= 2 } while i > 0
}

// A counter that starts from a call's result: no constant or argument to
// declare it from, so it is not named.
@inline(never) public func fromCall(_ start: () -> Int) {
    var i = start()
    repeat { sink(i); i &+= 1 } while i < 100
}

// Checked arithmetic: at -O the header ends in the overflow guard
// (`subs x19, x19, #2; b.vs trap`) and the loop test is in the block that
// closes the lap (`cmp x19, #0; b.gt header`). sink sees n, n - 2, …
@inline(never) public func checkedDown(_ n: Int) {
    var i = n
    repeat { sink(i); i -= 2 } while i > 0
}

// The same with a bound from the argument: sink sees 0, 1, …, n - 1.
@inline(never) public func checkedUp(_ n: Int) {
    var i = 0
    while i < n { sink(i); i += 1 }
}
