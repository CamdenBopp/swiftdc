// Hot/cold split fixture (-O2 -mllvm -hot-cold-split=true).
// True behaviour: hot(x) returns x+1 when x < 1000; otherwise it calls
// report(x) three times (cold path, outlined into hot.cold.1) and returns -1.
// The .cold.1 piece is a separate function that returns to hot.
extern void report(long);
long hot(long x) {
  if (__builtin_expect(x >= 1000, 0)) {
    report(x); report(x * 2); report(x * 3);
    return -1;
  }
  return x + 1;
}
