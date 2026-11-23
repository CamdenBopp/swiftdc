// LEVELS: O Osize Onone
// More than eight integer and float parameters: the ninth and tenth go on the
// stack at [sp] and [sp, #8] of the caller's outgoing area.
// TRUE behaviour: callSum10 passes 1..8 in x0-x7 and 109, 110 on the stack.
// callFsum10 passes 1.0..8.0 in d0-d7 and 9.5, 10.5 on the stack, stored as
// the integer bit patterns 0x4023000000000000 and 0x4025000000000000.
// A render may decline the two stack doubles, never print them as integers.
// EXPECT structured * callSum10 :: sum10(1, 2, 3, 4, 5, 6, 7, 8, 109, 110)
// EXPECT structured * callFsum10 :: re:fsum10\(1\.0, 2\.0, 3\.0, 4\.0, 5\.0, 6\.0, 7\.0, 8\.0, (\?|9\.5), (\?|10\.5)\)
// FORBID structured * callFsum10 :: re:fsum10\(1\.0, 2\.0, 3\.0, 4\.0, 5\.0, 6\.0, 7\.0, 8\.0\)
// FORBID structured * callFsum10 :: 0x4023
// FORBID structured * callFsum10 :: 46218
// FORBID structured * callSum10 :: re:sum10\(1, 2, 3, 4, 5, 6, 7, 8\)
@inline(never) public func sum10(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int,
                                 _ f: Int, _ g: Int, _ h: Int, _ i: Int, _ j: Int) -> Int {
  a &+ b &+ c &+ d &+ e &+ f &+ g &+ h &+ (i &* 3) &+ (j &* 5) }
public func callSum10() -> Int { sum10(1, 2, 3, 4, 5, 6, 7, 8, 109, 110) }
@inline(never) public func fsum10(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double,
                                  _ f: Double, _ g: Double, _ h: Double, _ i: Double, _ j: Double) -> Double {
  a + b + c + d + e + f + g + h + i * 3 + j * 5 }
public func callFsum10() -> Double { fsum10(1, 2, 3, 4, 5, 6, 7, 8, 9.5, 10.5) }
