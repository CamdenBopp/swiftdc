// LEVELS: O Osize Onone
// 32-bit Swift counters (Int32, UInt32). Checked arithmetic on a 32-bit
// value lowers to `adds w; b.vs` (signed) or `adds w; b.hs` (unsigned
// carry) in front of a trap; -Onone keeps every guard.
// TRUE behaviour:
//   up32(n):     sink32(i) for i: Int32 = 0, 1, ..., n-1 (none if n <= 0)
//   downBy2(n):  sink32(i) for i = n, n-2, ... while i > 0; `i -= 2` traps
//                on overflow (only reachable at i <= Int32.min + 1, which
//                the i > 0 test rules out, so -O may drop the guard)
//   unsignedNe(n): sink32(Int32(truncatingIfNeeded: i)) for i: UInt32 = 0 ..< n,
//                exits when i == n
//   strideNe():  sink32(i) for i = 1, 4, ..., 97; exits when i == 100
// -O/-Osize step the counter before the back-edge test (`add w20, w20, #1;
// cmp w19, w20; b.ne`); a raw test with no visible step drops the transfer.
// FORBID structured O,Osize up32 :: re:^(?![\s\S]*\b(w20|i) (=|\+=) )[\s\S]*if \(w19 != w20\)
// FORBID structured O,Osize unsignedNe :: re:^(?![\s\S]*\b(w20|i) (=|\+=) )[\s\S]*if \(w19 != w20\)
// FORBID structured Osize strideNe :: re:^(?![\s\S]*\b(w19|i) (=|\+=) )[\s\S]*if \(w19 != 0x64\)
// downBy2 -O: `subs w19, w19, #2; b.hi` is taken iff the pre-step value is
// above 2. Raw w19 at the branch is the stepped value.
// FORBID structured O,Osize downBy2 :: re:\bw19 >
// -Onone: `mov w8, #0; subs w8, w8, w9; b.ge exit` loops while 0 < i, and
// the `cset w8, vs; tbnz` guard on `i - 2` must not end the loop.
// EXPECT structured Onone downBy2 :: while (0 < w9)
// EXPECT structured * up32 :: sink32(
// EXPECT structured * downBy2 :: sink32(
// EXPECT structured * unsignedNe :: sink32(
@inline(never) public func sink32(_ x: Int32) { print(x) }

public func up32(_ n: Int32) { var i: Int32 = 0; while i < n { sink32(i); i += 1 } }
public func downBy2(_ n: Int32) { var i = n; while i > 0 { sink32(i); i -= 2 } }
public func unsignedNe(_ n: UInt32) {
    var i: UInt32 = 0
    while i != n { sink32(Int32(truncatingIfNeeded: i)); i &+= 1 }
}
public func strideNe() { var i: Int32 = 1; while i != 100 { sink32(i); i += 3 } }
