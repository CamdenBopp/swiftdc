// 32-bit signed comparisons (-O2). True behaviour: s_cmp calls sinkA(x)
// when a + b >= -100000 (as ints) and sinkB(x + 1) otherwise; s_neg calls
// sinkA(x) when c < 0, by `tbnz w0, #31`; s_ge returns c >= 0 ? 1 : 2.
extern void sinkA(long);
extern void sinkB(long);
__attribute__((noinline, visibility("default"))) void s_cmp(int a, int b, long x) {
    if (a + b >= -100000) sinkA(x); else sinkB(x + 1);
}
__attribute__((noinline, visibility("default"))) void s_neg(int c, long x) {
    if (c < 0) sinkA(x);
}
__attribute__((noinline, visibility("default"))) long s_ge(int c) { return c >= 0 ? 1 : 2; }
