// Signatureless C callees whose bodies read floating-point argument
// registers (clang -O2). AAPCS64 counts v0-v7 apart from x0-x7, so a body
// reading d0-d2 has three parameters its x-register reads do not show:
// `takef3(x, 2.5, 4.0)` passes d0-d2 and must not render `takef3()`.
// `mixed(k, x, 7)` passes k in x0, x in d0 and 7 in x1; the body cannot say
// how the banks interleave, so it must not render `mixed(?, 7)`, the 7 in
// the Double's place. `afterWrite` writes d1 before reading it: one
// parameter, not two.
__attribute__((noinline)) double takef3(double a, double b, double c) { return a * b + c; }
__attribute__((noinline)) double mixed(long k, double a, long j) { return (double)k * a + (double)j; }
__attribute__((noinline)) long ints(long a, long b) { return a * 3 + b; }
double callf3(double x) { return takef3(x, 2.5, 4.0); }
double callMixed(long k, double x) { return mixed(k, x, 7); }
long callInts(long a) { return ints(a, 9); }
__attribute__((noinline)) double afterWrite(double a) { return a * 3.0 + 1.0; }
double callAfterWrite(double x) { return afterWrite(x); }
