// LEVELS: O Osize Onone
// Swift switch and condition shapes.
// EXPECT structured O,Osize swDense :: sink((((0 <= arg0) && (arg0 < 6)) ? (arg0 + 10) : -1))
// EXPECT structured Onone swDense :: Swiftswitch.sink(15)
// EXPECT structured Onone swDense :: Swiftswitch.sink(-1)
// swRanges: k < 0 is the sign bit; 100 bounds 10...99 unsigned once k >= 0.
// EXPECT structured O,Osize swRanges :: ((arg0 & 0x8000000000000000) != 0) ? 1
// FORBID structured * swRanges :: re:arg0 (>|>=) 100\)
// swFall: case 1 runs sink(1) then falls into sink(2).
// EXPECT structured * swFall :: re:sink\((1|arg0)\)\n\s+goto loc_\w+
// FORBID structured * swFall :: re:sink\(1\)\n\s+return
// sgt: `cset lt` is signed; ugt `cset lo` on proven UInt operands may be a plain `<`.
// FORBID structured * sgt :: ᵁ
// EXPECT structured O,Osize inRange :: ((0 <= (arg0 - 10)) && ((arg0 - 10) < 10))
// EXPECT structured Onone inRange :: ((arg0 >= 10) && (arg0 < 20))
// fnotlt: `cset pl` is true for NaN; `a >= b` is false for NaN.
// FORBID structured * fnotlt :: re:arg0 >= arg1|arg1 <= arg0
// FORBID structured * flt :: re:arg0 >= arg1|arg0 > arg1
// EXPECT structured * bit7 :: (arg0 & 128) != 0)
// EXPECT structured * minusOne :: if (arg0 == -1)
// FORBID structured * minusOne :: re:arg0 == 1\)
// andCalls: check(2) is only called after check(1) returned true.
// EXPECT structured O,Osize andCalls :: re:if \(!Swiftswitch.check\(1\)\) \{\n\s+return\n\s+\} else \{\n\s+if \(!Swiftswitch.check\(2\)\)
// EXPECT structured Onone andCalls :: re:if \(r0\) \{\n\s+let r1 = Swiftswitch.check\(2\)
// EXPECT structured O,Osize classify :: return (((arg0 & 0x8000000000000000) != 0) ? -1 : ((arg0 == 0) ? 0 : ((arg0 >ᵁ 9) ? (arg0 + 1000) : (arg0 << 1))))
@inline(never) public func sink(_ x: Int) { print(x) }

// Dense Int switch with default; a jump table or a compare chain.
// TRUE: 0→sink(10), 1→sink(11), 2→sink(12), 3→sink(13), 4→sink(14),
// 5→sink(15), else sink(-1).
public func swDense(_ k: Int) {
  switch k {
  case 0: sink(10)
  case 1: sink(11)
  case 2: sink(12)
  case 3: sink(13)
  case 4: sink(14)
  case 5: sink(15)
  default: sink(-1)
  }
}

// Range patterns. TRUE: k<0 → sink(1); 0..<10 → sink(2); 10...99 → sink(3);
// else sink(4).
public func swRanges(_ k: Int) {
  switch k {
  case ..<0: sink(1)
  case 0..<10: sink(2)
  case 10...99: sink(3)
  default: sink(4)
  }
}

// Fallthrough. TRUE: k==1 → sink(1), sink(2); k==2 → sink(2); else nothing.
public func swFall(_ k: Int) {
  switch k {
  case 1: sink(1); fallthrough
  case 2: sink(2)
  default: break
  }
}

// Unsigned compare. TRUE: returns true iff a > b as UInt.
public func ugt(_ a: UInt, _ b: UInt) -> Bool { a > b }

// Signed compare. TRUE: returns true iff a > b as Int.
public func sgt(_ a: Int, _ b: Int) -> Bool { a > b }

// Range check. TRUE: true iff 10 <= x && x < 20.
public func inRange(_ x: Int) -> Bool { x >= 10 && x < 20 }

// Float NaN. TRUE: true iff a < b (false for NaN).
public func flt(_ a: Double, _ b: Double) -> Bool { a < b }

// TRUE: true iff !(a < b): true for NaN.
public func fnotlt(_ a: Double, _ b: Double) -> Bool { !(a < b) }

// Enum switch in a loop. TRUE: accumulates 1 per .a, 10 per .b, 100 per .c,
// sinks the total.
public enum Tok { case a, b, c, d }
public func swLoop(_ ts: [Tok]) {
  var acc = 0
  for t in ts {
    switch t {
    case .a: acc += 1
    case .b: acc += 10
    case .c: acc += 100
    case .d: sink(acc)
    }
  }
  sink(acc)
}

// Bit test on bit 7. TRUE: sink(7) iff bit 7 of x is set.
public func bit7(_ x: UInt) { if x & 0x80 != 0 { sink(7) } }

// Compare against -1 (cmn). TRUE: sink(3) iff x == -1; sink(4) iff x > -1.
public func minusOne(_ x: Int) { if x == -1 { sink(3) }; if x > -1 { sink(4) } }

// Short circuit with side effects. TRUE: check(2) only when check(1) is true.
@inline(never) public func check(_ x: Int) -> Bool { x & 1 == 1 }
public func andCalls() { if check(1) && check(2) { sink(5) } }

// Several exits. TRUE: x<0 → -1; x==0 → 0; x<10 → x*2; else x+1000.
public func classify(_ x: Int) -> Int {
  if x < 0 { return -1 }
  if x == 0 { return 0 }
  if x < 10 { return x &* 2 }
  return x &+ 1000
}
