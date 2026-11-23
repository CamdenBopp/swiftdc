// LEVELS: O Osize Onone
// Swift checked arithmetic inside loops. Each `+`/`-`/`*` that the optimizer
// cannot prove safe keeps an overflow guard: `adds; b.vs trap`,
// `adds; b.vc next` (trap on fall-through), `smulh`/`cmp …, asr #63; b.ne`
// for multiply, or `cset w8, vs; tbnz w8, #0, trap` at -Onone. The trap is
// a `brk #1`: a render must keep both the trap path and the loop test.
// TRUE behaviour:
//   sumTo(n):      s = 0; for k in 0..<n { s += k * k } (traps on overflow); return s
//   accumulate(a): s = 0; for x in a { s += x } (traps on overflow); return s
//   countDown(n):  var i = n; repeat { sink(i); i -= 3 } while i > 0; traps if
//                  `i - 3` overflows (i near Int.min)
//   powerUntil(n): var p = 1; while p < n { p *= 3 } (traps on overflow); return p
//   unsignedUp(n): UInt32 sum 1 + 0 + 1 + ... + (n-1), each `+=` traps on
//                  carry (`adds w; b.hs`); -O unrolls by four
//   preconditioned(a, lo): for x in a { precondition(x >= lo); sink(x &- lo) };
//                  -O lowers the precondition as `subs x0, x8, x19; b.lo trap`,
//                  the same instructions as a checked UInt subtraction.
// The folded guard (`subs x19, x19, #3; b.vs trap`) must not lose the test
// that closes the lap (`cmp x19, #0; b.gt`) or the step:
// EXPECT structured * countDown :: Checked.sink(i)
// EXPECT structured * countDown :: i -= 3
// EXPECT structured O,Osize countDown :: if ((i - 3) > 0)
// Back-edge tests on a register stepped in the body (`add x9, x9, #1`,
// `subs x9, x9, #1`, `add x0, x0, x0, lsl #1`) with no visible step drop
// the transfer; the loop reads as one whose test never changes.
// FORBID structured O,Osize sumTo :: re:^(?![\s\S]*\b(x9|i) (=|\+=) )[\s\S]*if \(x0 != x9\)
// FORBID structured O,Osize accumulate :: re:^(?![\s\S]*\b(x9|i) (=|-=) )[\s\S]*if \(x9 != 0\)
// FORBID structured O,Osize powerUntil :: re:^(?![\s\S]*\bx0 (=|\*=) )[\s\S]*(while|if) \(x0 < x8\)
// FORBID structured O preconditioned :: re:^(?![\s\S]*\b(x20|i) (=|-=) )[\s\S]*if \(x20 != 0\)
// The multiply guard (`smulh; cmp …, asr #63; b.ne trap`) is not folded:
// EXPECT structured O,Osize sumTo :: trap()
@inline(never) public func sink(_ x: Int) { print(x) }

public func sumTo(_ n: Int) -> Int {
    var s = 0
    for k in 0..<n { s += k * k }
    return s
}
public func accumulate(_ a: [Int]) -> Int {
    var s = 0
    for x in a { s += x }
    return s
}
public func countDown(_ n: Int) { var i = n; repeat { sink(i); i -= 3 } while i > 0 }
public func powerUntil(_ n: Int) -> Int { var p = 1; while p < n { p *= 3 }; return p }
public func unsignedUp(_ n: UInt32) -> UInt32 { var i: UInt32 = 0; var s: UInt32 = 1; while i < n { s += i; i += 1 }; return s }
public func preconditioned(_ a: [UInt], _ lo: UInt) { for x in a { precondition(x >= lo); sink(Int(bitPattern: x &- lo)) } }
