// LEVELS: O0 O1 O2 Os
// Counters that do not start from a constant, two counters stepping
// differently, and a counter read after the loop.
// TRUE behaviour:
//   from_call():      i = start() (opaque); sink(i) while i < 50, i += 1
//   from_field(b):    i = b->lo; sink(i) while i < b->hi, i += 1; b->hi is
//                     re-read every lap only at -O0 (it may alias nothing
//                     else, so -O1+ may hoist it)
//   two_steps(n):     i = 0, j = n; while i < j: sink(i - j); i += 3, j -= 1
//   after_loop(n):    i = 0; while i * i < n: i += 1; return i (the first i
//                     with i*i >= n); 0 for n <= 0
//   last_hit(a, n):   scans a[0..n), returns the last index k with a[k] == 7,
//                     or -1. The returned value is the counter of a past lap.
// two_steps at -O1/-O2/-Os: `cmp w21, w19; add w21, w21, #3; b.lt`. The
// flags come from w21 *before* the add, so a raw `w21` at the branch (its
// value there, three past the compared one) is one step off.
// FORBID structured O1,O2,Os two_steps :: if (w21 < w19)
// after_loop at -O1+: `add w0, w0, #1; mul w9, w0, w0; cmp w9, w8; b.lt`.
// An empty loop body under a test on w0 hides the step: an infinite loop.
// FORBID structured O1,O2,Os after_loop :: re:while \([^\n]*\) \{\n\s*\}
// A counter seeded by a call or a field load still steps every lap:
// FORBID structured O1,O2,Os from_call :: re:^(?![\s\S]*\b(w19|i) (=|\+=) )[\s\S]*if \(w19 != 0x32\)
// FORBID structured O1,O2,Os from_field :: re:^(?![\s\S]*\b(w20|i) (=|\+=) )[\s\S]*\(w20 < w8\) \{\n\s*continue
// EXPECT structured * from_call :: start(
// EXPECT structured * from_field :: sink(
// EXPECT structured * two_steps :: sink(
volatile int sunk;
__attribute__((noinline)) void sink(int x) { sunk = x; }
extern int start(void);
struct bounds { int lo, hi; };

void from_call(void) { for (int i = start(); i < 50; i++) sink(i); }
void from_field(struct bounds *b) { for (int i = b->lo; i < b->hi; i++) sink(i); }
void two_steps(int n) { for (int i = 0, j = n; i < j; i += 3, j -= 1) sink(i - j); }
int after_loop(int n) { int i = 0; while (i * i < n) i++; return i; }
long last_hit(const int *a, long n) {
    long k = -1;
    for (long i = 0; i < n; i++) if (a[i] == 7) k = i;
    return k;
}
