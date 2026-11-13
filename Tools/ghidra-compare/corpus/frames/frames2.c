// Fixture: unusual stack frames with in-image callees whose bodies prove
// their arity (sink reads x0,x1; use reads x0 and returns x0).
#include <string.h>
#include <setjmp.h>
volatile long g_sink;
__attribute__((noinline)) void sink(void *p, long n) { g_sink = (long)p ^ n; }
__attribute__((noinline)) long use(long x) { g_sink = x; return g_sink + 3; }
__attribute__((noinline)) double fuse(double x) { g_sink = (long)x; return (double)g_sink; }

// big_frame: 64 KB buffer, ___chkstk_darwin probe. True: sink(buf, n); return buf[n&0xffff] + n.
long big_frame(long n) { char buf[65536]; sink(buf, n); return buf[n & 0xffff] + n; }
// mid_frame: 5008 B frame. True: sink(buf, 7); return buf[3]*2.
long mid_frame(void) { char buf[5000]; sink(buf, 7); return (long)buf[3] * 2; }
// vla: True: sink(a, n); return a[0] + n.
long vla(long n) { long a[n]; sink(a, n); return a[0] + n; }
// alloca_after: alloca then call with arg passed through. True: sink(p, k); returns use(k).
long alloca_after(long k) { void *p = __builtin_alloca(k); sink(p, k); return use(k); }
// aligned64: realigned sp. True: sink(x, 64); return x[1] + k.
long aligned64(long k) { _Alignas(64) long x[8]; sink(x, 64); return x[1] + k; }
// big_args: 64 KB frame and 3 args survive the probe. True: return use(a) + b + c.
long big_args(long a, long b, long c) { char buf[70000]; sink(buf, a); return use(a) + b + c; }
// fpsaved: d8/d9 callee saved across call. True: return fuse(a) * a + b.
double fpsaved(double a, double b) { return fuse(a) * a + b; }
// big_fp: FP args across ___chkstk_darwin. True: sink(buf,1); return a + b.
double big_fp(double a, double b) { char buf[70000]; sink(buf, 1); return a + b + buf[5]; }
static jmp_buf jb;
// sj: True: if setjmp(jb) != 0 return -1; sink(0,n); return n+1.
long sj(long n) { if (setjmp(jb)) return -1; sink(0, n); return n + 1; }
// two_args: True: return use(a) + b.
long two_args(long a, long b) { return use(a) + b; }
// konst: True: returns 42 (no locals).
long konst(void) { char buf[8000]; sink(buf, 0); return 42; }
