// A callee in the same image that takes a ninth argument reads it from the
// caller's outgoing area, at or above its entry sp (`ldr x8, [sp]`). Laid
// out from the registers its body reads, the call claimed those alone:
// `nine(?)` for nine(q, 1, …, 7, 100). The registers in between need not be
// arguments (a float or an aggregate can go to the stack first), so the
// sound rendering keeps what is proven and ends in `…`.
//
// True behaviour: nine returns a + i; callNine(q) calls nine(q, 1, 2, 3, 4,
// 5, 6, 7, 100). two returns a * b and callTwo(q) calls two(q, 3): no
// stack argument, no `…`.
__attribute__((noinline)) long nine(long a, long b, long c, long d, long e, long f, long g, long h, long i) { return a + i; }
long callNine(long q) { return nine(q, 1, 2, 3, 4, 5, 6, 7, 100); }
__attribute__((noinline)) long two(long a, long b) { return a * b; }
long callTwo(long q) { return two(q, 3); }
