// Fixture: callers of large-frame functions. ___chkstk_darwin preserves x0-x8.
// True: caller_big(p,q) calls big3(p, q, 5) and returns its result + 1.
//       caller_small(p) calls small1(p) and returns result + 1.
volatile long g;
__attribute__((noinline)) long big3(long a, long b, long c) {
    char buf[70000]; buf[a & 0xff] = (char)b; g = (long)buf; return buf[c & 0xff] + a + b + c;
}
__attribute__((noinline)) long small1(long a) { char buf[16]; buf[a & 0xf] = 1; g = (long)buf; return buf[3] + a; }
__attribute__((noinline)) double bigf(double a, double b) { char buf[70000]; g = (long)buf; buf[3] = 1; return a * b + buf[3]; }
long caller_big(long p, long q) { return big3(p, q, 5) + 1; }
long caller_small(long p) { return small1(p) + 1; }
double caller_f(double x) { return bigf(x, 2.0) + 1.0; }
