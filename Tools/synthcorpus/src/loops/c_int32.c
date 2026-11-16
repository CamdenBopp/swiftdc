// LEVELS: O0 O1 O2 Os
// 32-bit loop counters in C. Each loop calls `sink`, defined here and kept
// out of line, so the loop survives optimization and the argument is
// provably w0. The counter lives in a w register (a 32-bit stack slot at -O0).
// TRUE behaviour, per function:
//   up_to_arg(n):     sink(i) for i = 0, 1, ..., n-1 (signed int, none if n <= 0)
//   up_to_arg64(n):   the same with a 64-bit long counter (control case)
//   down_by_two(n):   sink(i) for i = n, n-2, ... while i > 0 (signed). -O2
//                     lowers the test as `subs w19, w19, #2; b.hi`: taken iff
//                     the value *before* the step is above 2 (unsigned; the
//                     guard proved it positive).
//   unsigned_ne(n):   sink(i) for i = 0 .. n-1, exits when i == n (unsigned)
//   ne_by_three():    sink(i) for i = 1, 4, 7, ..., 97; exits when i == 100
//                     (fully unrolled at -O2/-Os: 33 calls, no loop)
//   unsigned_down(n): sink(i) for i = n-1 down to 0. -O2: `sub w19, w19, #1;
//                     cmn w19, #1; b.ne`: loops while the stepped i != 0xffffffff.
//
// A raw register at a test means its value at the test. After
// `subs w19, w19, #2` that is the stepped value, so `w19 >ᵁ 2` (the
// pre-step operand) is one step off and `w19 > 0` is wrong at the wrap.
// FORBID structured O1,O2,Os down_by_two :: re:\b[wx]19 >ᵁ? 
// FORBID structured O1,O2,Os down_by_two :: re:\b[wx]19 >= 
// The -O2 test of up_to_arg reads the stepped counter against n:
// `add w20, w20, #1; cmp w19, w20; b.ne` is taken iff n != i + 1.
// FORBID structured O2,Os up_to_arg :: re:\(w20 \+ 1\) != w19|w19 != \(w20 \+ 1\)
// A raw callee-saved register tested on the back edge, with no visible step
// anywhere in the function, reads as a loop whose test never changes: the
// counter's transfer was dropped (`add w20, w20, #1` before `cmp w19, w20`).
// FORBID structured O1,O2,Os up_to_arg :: re:^(?![\s\S]*\b(w20|i) (=|\+=) )[\s\S]*if \(w19 != w20\)
// FORBID structured O1,O2,Os unsigned_ne :: re:^(?![\s\S]*\b(w20|i) (=|\+=) )[\s\S]*if \(w19 != w20\)
// FORBID structured O1,O2,Os unsigned_down :: re:^(?![\s\S]*\b(w19|i) (=|-=) )[\s\S]*if \(w19 != -1\)
// FORBID structured O1,Os ne_by_three :: re:^(?![\s\S]*\b(w19|i) (=|\+=) )[\s\S]*if \(w19 != 0x64\)
// The 64-bit control names its counter; a 32-bit one is the same loop.
// EXPECT structured O1,O2,Os up_to_arg64 :: var i = 0
// Every function is a loop over sink: no function may render empty.
// EXPECT structured * up_to_arg :: sink(
// EXPECT structured * unsigned_down :: sink(
volatile int sunk;
__attribute__((noinline)) void sink(int x) { sunk = x; }

void up_to_arg(int n) { for (int i = 0; i < n; i++) sink(i); }
void up_to_arg64(long n) { for (long i = 0; i < n; i++) sink((int)i); }
void down_by_two(int n) { for (int i = n; i > 0; i -= 2) sink(i); }
void unsigned_ne(unsigned n) { for (unsigned i = 0; i != n; i++) sink((int)i); }
void ne_by_three(void) { for (int i = 1; i != 100; i += 3) sink(i); }
void unsigned_down(unsigned n) { for (unsigned i = n; i-- != 0;) sink((int)i); }
