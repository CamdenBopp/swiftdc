// adds/subs that write the register they compare, under ordered conditions.
extern void sink(int);
extern void sinkl(long);
// diff_pos: the test is on the wrapped difference, never on a > b.
// EXPECT structured * _diff_pos :: (arg0 & 0xffffffff) - (arg1 & 0xffffffff)
// FORBID structured * _diff_pos :: re:\(arg0 & 0xffffffff\) << 32\) >>ˢ 32\) (>|>=|<|<=) \(
// countdown -O1/-O2/-Os: `sub w19, w19, #1; cmp w19, #2; b.gt/b.hi`: the cmp
// reads the already-decremented w19, so `w19 > 2` (or >ᵁ) is right there.
// EXPECT structured O1,O2,Os _countdown :: >>ˢ 32) >= 2)
// EXPECT structured O1,O2,Os _countdown :: re:if \(w19 >ᵁ? 2\)

// Countdown: `subs w19, w19, #1; b.gt loop` (or b.ne). TRUE: sink(n-1), sink(n-2)
// ... sink(0) is not reached: the body runs with n-1 down to 1 while n-1 > 0.
void countdown(int n) { while (--n > 0) sink(n); }

// TRUE: returns 1 iff a + b < 0 as an int (the sum is computed first, the
// test reads the sum's sign, not the original a).
int sum_negative(int a, int b) { int s = a + b; sink(s); return s < 0; }

// subs to a new value then a signed compare of it with zero. TRUE: sink(1)
// iff a - b > 0 (after wrap), and returns a - b.
int diff_pos(int a, int b) { int d = a - b; if (d > 0) sink(1); return d; }

// Overflow detection: TRUE: returns 1 iff a + b overflows signed int.
int add_overflows(int a, int b) { int r; return __builtin_add_overflow(a, b, &r); }

// Unsigned carry: TRUE: returns 1 iff a + b wraps (carry out).
int add_carries(unsigned a, unsigned b) { unsigned r; return __builtin_add_overflow(a, b, &r); }

// Borrow: TRUE: returns 1 iff a - b borrows (a <u b).
int sub_borrows(unsigned long a, unsigned long b) { unsigned long r; return __builtin_sub_overflow(a, b, &r); }
