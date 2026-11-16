// Range checks and ccmp chains.
#include <stdint.h>
extern void sink(int);
// EXPECT structured O0 _out_range :: < -100)
// EXPECT structured O0 _out_range :: > 100)
// FORBID structured * _out_range :: re:(<|>)ᵁ -?100\)
// chain_unsigned: both compares are unsigned (b.ls / b.hi).
// EXPECT structured * _chain_unsigned :: re:\(arg0 & 0xffffffff\) (<=ᵁ|>ᵁ) \(arg1 & 0xffffffff\)
// EXPECT structured * _chain_unsigned :: re:\(arg2 & 0xffffffff\) (<=ᵁ|>ᵁ) \(arg3 & 0xffffffff\)
// FORBID structured * _chain_unsigned :: re:\(arg[02] & 0xffffffff\) (<=|>=|<|>) \(
// range_branch -O0: signed compares of lo, x and hi.
// EXPECT structured O0 _range_branch :: >>ˢ 32) > (((arg0 & 0xffffffff) << 32) >>ˢ 32))
// FORBID structured * _range_branch :: ᵁ
// is_alpha at -O0 tests 65 and 90 signed.
// EXPECT structured O0 _is_alpha :: >>ˢ 32) < 65)

// `cmp; ccmp; b.cond` (or cset) range: TRUE: 1 iff 10 <= x && x < 20 (signed).
int in_range(int x) { return x >= 10 && x < 20; }

// Unsigned range trick: (unsigned)(x - 10) < 10. TRUE: 1 iff 10 <= x < 20.
int in_range_u(unsigned x) { return x - 10 < 10; }

// Branchy range: TRUE: sink(1) iff lo <= x && x < hi, else sink(2).
void range_branch(int x, int lo, int hi) {
  if (lo <= x && x < hi) sink(1); else sink(2);
}

// Outside a range with ||: TRUE: sink(3) iff x < -100 || x > 100.
void out_range(int x) { if (x < -100 || x > 100) sink(3); }

// ccmp chain of three equalities: TRUE: 1 iff a == 1 && b == 2 && c == 3.
int chain3(int a, int b, int c) { return a == 1 && b == 2 && c == 3; }

// Mixed chain: TRUE: 1 iff a > 0 || (b < 5 && c != 7).
int chain_mixed(int a, int b, int c) { return a > 0 || (b < 5 && c != 7); }

// Unsigned compare chain: TRUE: sink(4) iff a >u b && c <=u d.
void chain_unsigned(unsigned a, unsigned b, unsigned c, unsigned d) {
  if (a > b && c <= d) sink(4);
}

// ASCII letter test: TRUE: 1 iff 'A'<=c<='Z' or 'a'<=c<='z'.
int is_alpha(int c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
