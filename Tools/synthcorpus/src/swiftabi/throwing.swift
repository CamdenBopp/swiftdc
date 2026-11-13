// LEVELS: O Osize Onone
// Throwing functions: the callee returns its error in x21 (swifterror) and the
// caller zeroes x21 before the call and tests it after.
// TRUE behaviour:
//   check(x): throws Bad.negative(x) if x < 0, Bad.tooBig if x > 1000, else 2x.
//   sumChecked: a throw inside a loop; the first error leaves the loop and is
//   rethrown; otherwise the sum of 2x over the array.
//   safe(x): check(x), or -1 when it throws. It is never just check(x).
//   applyTwice rethrows; useRethrows specializes it with { $0 + 1 } to x + 2:
//   at -O, applyTwice-specialized(5); at -Onone, applyTwice(closure, 5) with
//   the thick closure in x0, x1 (context 0) and 5 in x2.
//   evenOnly(x) throws(Small): throws .odd for odd x, else x / 2 (exact, so
//   an arithmetic shift is right). useTyped returns evenOnly(x) or -7.
// EXPECT structured * check(Swift.Int) :: swift_willThrow(
// EXPECT structured O,Onone check(Swift.Int) :: throw
// EXPECT structured O check(Swift.Int) :: return (arg0 << 1)
// EXPECT structured Onone check(Swift.Int) :: return (2 * arg0)
// EXPECT structured * sumChecked :: Throwing.check(
// EXPECT structured * sumChecked :: error != nil
// EXPECT structured * sumChecked :: while
// EXPECT structured * Throwing.safe :: Throwing.check(arg0)
// EXPECT structured * Throwing.safe :: error != nil
// FORBID structured * Throwing.safe :: return Throwing.check(arg0)
// EXPECT structured O,Osize useRethrows :: of Throwing.applyTwice(5)
// EXPECT structured Onone useRethrows :: re:applyTwice\(\?, (\?|5)\)
// FORBID structured Onone useRethrows :: applyTwice(?, 0)
// EXPECT structured * evenOnly :: throw
// EXPECT structured O,Osize evenOnly :: return (arg0 >>ˢ 1)
// EXPECT structured Onone evenOnly :: return (arg0 / 2)
// EXPECT structured * useTyped :: Throwing.evenOnly(arg0)
// FORBID structured * useTyped :: return Throwing.evenOnly(arg0)
// At -Osize the epilogue is outlined (b OUTLINED_FUNCTION_0, which restores
// x21/x22 and returns). safe and useTyped return an Int there: a bare
// `return` claims no value and a missing return falls off the end.
// FORBID structured Osize Throwing.safe :: re:(?m)^\s*return$
// EXPECT structured Osize Throwing.safe :: return ?
// EXPECT structured Osize useTyped :: return
// EXPECT structured Osize useRethrows :: re:return (\?|.*applyTwice)
public enum Bad: Error { case negative(Int), tooBig }
@inline(never) public func check(_ x: Int) throws -> Int {
  if x < 0 { throw Bad.negative(x) }; if x > 1000 { throw Bad.tooBig }; return x &* 2 }
public func sumChecked(_ xs: [Int]) throws -> Int { var t = 0; for x in xs { t &+= try check(x) }; return t }
public func safe(_ x: Int) -> Int { (try? check(x)) ?? -1 }
@inline(never) public func applyTwice(_ f: (Int) throws -> Int, _ x: Int) rethrows -> Int { try f(try f(x)) }
public func useRethrows() -> Int { applyTwice({ $0 &+ 1 }, 5) }
public enum Small: Error { case odd }
@inline(never) public func evenOnly(_ x: Int) throws(Small) -> Int { if x & 1 == 1 { throw .odd }; return x / 2 }
public func useTyped(_ x: Int) -> Int { do { return try evenOnly(x) } catch { return -7 } }
