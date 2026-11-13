// csel / cset / csinc / cneg / csneg producing values used later.
extern void sink(int);
extern void sinkl(long);

// TRUE: sink(a < b ? a : b) then returns max (signed).
int minmax(int a, int b) { int lo = a < b ? a : b; sink(lo); return a > b ? a : b; }

// cneg: TRUE: |x| (signed), then sink(|x| + 1).
int absval(int x) { int r = x < 0 ? -x : x; sink(r + 1); return r; }

// csinc: TRUE: returns (a == b) ? c : d + 1.
int pick_inc(int a, int b, int c, int d) { return a == b ? c : d + 1; }

// cset used as a count: TRUE: returns (a < b) + (c >u d) + (e == 0).
int count_flags(int a, int b, unsigned c, unsigned d, int e) {
  return (a < b) + (c > d) + (e == 0);
}

// csinv / csneg: TRUE: returns x >= 0 ? y : ~y, and sinks x > 5 ? z : -z.
int inv_neg(int x, int y, int z) { sink(x > 5 ? z : -z); return x >= 0 ? y : ~y; }

// Unsigned clamp: TRUE: returns x >u 255 ? 255 : x.
unsigned clamp255(unsigned x) { return x > 255 ? 255 : x; }

// Signed clamp to [-128, 127].
int clamp_s8(int x) { return x < -128 ? -128 : (x > 127 ? 127 : x); }

// Sign function: TRUE: -1, 0 or 1.
int sign_of(long x) { return (x > 0) - (x < 0); }
