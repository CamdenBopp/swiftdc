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

// A callee with a frame reads its stack arguments through x29 (`add x29,
// sp, #0x10; ldr x8, [x29, #0x10]`), after a call, after a test, or into a
// callee-saved register it saved itself (`ldr x19, [x29, #0x10]`). Each
// call passes 100 at [sp]; each renders with `…`, and every call above
// that read only its registers rendered as complete
// (`framed(arg0, 1, 2, 3, 4, 5, 6, 7)` at -O0).
extern long sink(long);
extern void sinkv(void);
__attribute__((noinline)) long framed(long a, long b, long c, long d, long e, long f, long g, long h, long i) { sinkv(); return a + i; }
long callFramed(long q) { return framed(q, 1, 2, 3, 4, 5, 6, 7, 100); }
__attribute__((noinline)) long tested(long a, long b, long c, long d, long e, long f, long g, long h, long i) { if (a) return sink(i); return 0; }
long callTested(long q) { return tested(q, 1, 2, 3, 4, 5, 6, 7, 100); }
__attribute__((noinline)) long kept(long a, long b, long c, long d, long e, long f, long g, long h, long i) { long r = sink(a); return r + i; }
long callKept(long q) { return kept(q, 1, 2, 3, 4, 5, 6, 7, 100); }
__attribute__((noinline)) long framedTwo(long a, long b) { long r = sink(a); return r * b; }
long callFramedTwo(long q) { return framedTwo(q, 3); }
// passed hands a and b on to pair untouched, so its register reads come
// from pair's summary, a rebuild that forgot its own stack read.
__attribute__((noinline)) long pair(long a, long b) { return a * b + sink(a); }
__attribute__((noinline)) long passed(long a, long b, long c, long d, long e, long f, long g, long h, long i) { return pair(a, b) + i; }
long callPassed(long q) { return passed(q, 1, 2, 3, 4, 5, 6, 7, 100); }
