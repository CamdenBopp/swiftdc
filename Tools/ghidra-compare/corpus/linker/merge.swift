// Swift LLVM function merging fixture (-O -Xllvm -enable-merge-functions).
// True behaviour: mA(x,y,z) = ((x ^ y) &* 1234567) &+ (z &* x) &- (y >> 3) &+ 0x11111
//                 mB(...) same but the last constant is 0x22222, mC with 0x33333.
// Swift's merge-functions pass may turn these into thunks that pass the
// differing constant to one shared `Tm` body as an extra argument.
@inline(never) public func mA(_ x: Int, _ y: Int, _ z: Int) -> Int { var r = (x ^ y) &* 1234567; r = r &+ (z &* x); r = r &- (y >> 3); r ^= r >> 7; r = r &* 31; return r &+ 0x11111 }
@inline(never) public func mB(_ x: Int, _ y: Int, _ z: Int) -> Int { var r = (x ^ y) &* 1234567; r = r &+ (z &* x); r = r &- (y >> 3); r ^= r >> 7; r = r &* 31; return r &+ 0x22222 }
@inline(never) public func mC(_ x: Int, _ y: Int, _ z: Int) -> Int { var r = (x ^ y) &* 1234567; r = r &+ (z &* x); r = r &- (y >> 3); r ^= r >> 7; r = r &* 31; return r &+ 0x33333 }
public func useM(_ a: Int) -> Int { mA(a, 1, 2) &+ mB(a, 3, 4) &+ mC(5, a, 6) }
