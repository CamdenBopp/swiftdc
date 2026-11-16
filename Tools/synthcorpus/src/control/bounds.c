// Signed vs unsigned boundaries, compares against -1 and 0, and cmn.
#include <limits.h>
extern void sink(int);
// EXPECT structured * _is_int_min :: (arg0 & 0xffffffff)
// EXPECT structured * _is_int_min :: 0x80000000)
// FORBID structured * _is_int_min :: re:(<|>)=? 0x80000000
// EXPECT structured * _is_uint_max :: == -1)
// EXPECT structured * _minus_one :: == -1)
// FORBID structured * _minus_one :: == 1)
// minus_one: x > -1 is a sign test (signed).
// FORBID structured * _minus_one :: re:ᵁ -?[01]\)
// u_nonzero: x >u 0 is x != 0; a signed `> 0` is wrong for 0x80000000.
// FORBID structured * _u_nonzero :: re:\) > 0\)
// EXPECT structured * _s_nonpos :: <= 0)
// FORBID structured * _s_nonpos :: <=ᵁ 0
// EXPECT structured O0 _ge_max :: >= 0x7fffffff)
// FORBID structured * _ge_max :: ᵁ 0x7fffffff
// above_u32: unsigned 64-bit compare with 0xffffffff.
// EXPECT structured O0 _above_u32 :: arg0 >ᵁ 0xffffffff)
// FORBID structured * _above_u32 :: re:arg0 (>|>=) 0xffffffff\)
// at_long_min: x < LONG_MIN + 1 (signed) is x == LONG_MIN.
// FORBID structured * _at_long_min :: <ᵁ 0x8000000000000001
// EXPECT structured O1,O2,Os _at_long_min :: arg0 != 0x8000000000000000

// TRUE: sink(1) iff x == INT_MIN.
void is_int_min(int x) { if (x == INT_MIN) sink(1); }

// TRUE: sink(2) iff x == UINT_MAX.
void is_uint_max(unsigned x) { if (x == UINT_MAX) sink(2); }

// cmn: TRUE: sink(3) iff x == -1; sink(4) iff x > -1 (signed).
void minus_one(int x) { if (x == -1) sink(3); if (x > -1) sink(4); }

// Against -5 by cmn: TRUE: returns 1 iff x < -5 (signed).
int below_minus5(long x) { return x < -5; }

// Unsigned vs zero: TRUE: sink(5) iff x != 0 (x >u 0).
void u_nonzero(unsigned x) { if (x > 0) sink(5); }

// Signed vs 0 with <=: TRUE: sink(6) iff x <= 0.
void s_nonpos(int x) { if (x <= 0) sink(6); }

// Mixed signedness by the C rules: x is converted to unsigned, so -1 > 1u.
// TRUE: returns 1 iff (unsigned)x > y, i.e. an unsigned compare.
int mixed_cmp(int x, unsigned y) { return (unsigned)x > y; }

// Large immediates: TRUE: sink(7) iff x >= 0x7fffffff (signed int).
void ge_max(int x) { if (x >= INT_MAX) sink(7); }

// 64-bit unsigned: TRUE: sink(8) iff x >u 0xffffffff.
void above_u32(unsigned long x) { if (x > 0xffffffffUL) sink(8); }

// Signed 64 boundary: TRUE: sink(9) iff x < LONG_MIN + 1, i.e. x == LONG_MIN.
void at_long_min(long x) { if (x < LONG_MIN + 1) sink(9); }
