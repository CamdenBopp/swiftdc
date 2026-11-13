// Fixture: a branch on an argument after ___chkstk_darwin.
// True: cbig(n): if n != 0 then sink(buf, n); cbig_small: same with a 16-byte buffer.
volatile long g;
__attribute__((noinline)) void sink(void *p, long n) { g = (long)p ^ n; }
void cbig(long n) { char buf[70000]; if (n) sink(buf, n); }
void csmall(long n) { char buf[16]; if (n) sink(buf, n); }
// vla_cond: True: if n != 0, sink(a, n)
void vla_cond(long n, long m) { long a[n]; if (m) sink(a, m); }
