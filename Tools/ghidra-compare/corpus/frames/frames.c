// Fixture: unusual stack frames. True behaviour stated per function.
#include <string.h>
#include <setjmp.h>
#include <stdlib.h>
extern void sink(void *p, long n);
extern long use(long x);

// big_frame: 64 KB local buffer (stack probe via ___chkstk_darwin at -O2).
// True: calls sink(buf, n) then returns buf[n & 0xffff] + n.
long big_frame(long n) {
    char buf[65536];
    sink(buf, n);
    return buf[n & 0xffff] + n;
}

// mid_frame: 5000-byte frame (sub sp, #1, lsl #12 pattern).
// True: sink(buf,7); returns (long)buf[3] * 2.
long mid_frame(void) {
    char buf[5000];
    sink(buf, 7);
    return (long)buf[3] * 2;
}

// vla: C VLA of n longs. True: sink(a, n); returns a[0] + n.
long vla(long n) {
    long a[n];
    sink(a, n);
    return a[0] + n;
}

// aligned64: alignas(64) local forces sp realignment.
// True: sink(&x, 64); returns x[1] + k.
long aligned64(long k) {
    _Alignas(64) long x[8];
    sink(x, 64);
    return x[1] + k;
}

// protected: char buffer with stack protector. True: strcpy-like copy, returns strlen(buf)+1.
long protected(const char *s) {
    char buf[64];
    strncpy(buf, s, 63); buf[63] = 0;
    return (long)strlen(buf) + 1;
}

// fpsaved: uses d8 across a call. True: returns use(a) * a + b (double math).
double fpsaved(double a, double b) {
    double r = (double)use((long)a);
    return r * a + b;
}

static jmp_buf jb;
// sj: setjmp returns 0 first, nonzero on longjmp. True: if setjmp(jb)!=0 return -1; else sink(0,n); return n+1.
long sj(long n) {
    if (setjmp(jb)) return -1;
    sink(0, n);
    return n + 1;
}
// lj: True: longjmp(jb, v) never returns.
void lj(int v) { longjmp(jb, v); }

// two_args_after_call: x1 must be from arg b, not noise. True: returns use(a) + b.
long two_args(long a, long b) { return use(a) + b; }
