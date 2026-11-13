// LEVELS: O Osize Onone
// Tuple and struct parameters and returns: up to four words travel directly
// in registers; a five-word struct goes indirectly (result through x8,
// parameter as an address in x0).
// TRUE behaviour:
//   divmod(100, 7) returns (14, 2) in x0, x1; callDivmod returns 14 * 1000 + 2.
//   makeBig(40) writes Big(40, 41, 42, 43, 44) through x8; callMakeBig returns
//   the e field, [x8 + 0x20].
//   takeBig receives the address of a stack Big(1, 2, 3, 4, 5) in x0 and
//   returns a + e. Its argument is an address, not the value 1.
// EXPECT structured * callDivmod :: divmod(100, 7)
// FORBID structured * callDivmod :: re:return 14\b(?!002)
// FORBID structured * callDivmod :: return 2
// EXPECT structured * callMakeBig :: makeBig(40)
// EXPECT structured * callMakeBig :: return r0.e
// FORBID structured * callMakeBig :: re:return r0\.[abcd]\b
// EXPECT structured O,Osize makeBig(Swift.Int) :: Big(a: arg0
// FORBID structured * makeBig(Swift.Int) :: b: arg0,
// EXPECT structured Onone makeBig(Swift.Int) :: (arg0, (arg0 + 1), (arg0 + 2), (arg0 + 3), (arg0 + 4))
// EXPECT structured * callTakeBig :: re:takeBig\(.+\)
// FORBID structured * callTakeBig :: takeBig(1
// FORBID structured * callTakeBig :: takeBig()
@inline(never) public func divmod(_ a: Int, _ b: Int) -> (Int, Int) { (a / b, a % b) }
public func callDivmod() -> Int { let (q, r) = divmod(100, 7); return q &* 1000 &+ r }
public struct Big { public var a, b, c, d, e: Int }
@inline(never) public func makeBig(_ s: Int) -> Big { Big(a: s, b: s &+ 1, c: s &+ 2, d: s &+ 3, e: s &+ 4) }
public func callMakeBig() -> Int { makeBig(40).e }
@inline(never) public func takeBig(_ b: Big) -> Int { b.a &+ b.e }
public func callTakeBig() -> Int { takeBig(Big(a: 1, b: 2, c: 3, d: 4, e: 5)) }
