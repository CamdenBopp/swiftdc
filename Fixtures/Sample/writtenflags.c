// A compare that writes its own operand: `subs w19, w19, #2; b.hi`
// compares the value before the subtraction with 2, while w19 already
// holds the value after it at the branch. down2 at -O2 (`for (int i = n;
// i > 0; i -= 2)`) is `subs w19, w19, #2; b.hi`: taken iff the old i >ᵁ 2,
// that is iff the new i >ᵁ 0. sum at -O1 counts n down with `subs x9, x9,
// #1; b.ne`: taken iff the new x9 != 0.
extern void use(int);
__attribute__((noinline)) void down2(int n) { for (int i = n; i > 0; i -= 2) use(i); }
__attribute__((noinline)) long sum(int *a, int n) { long s = 0; for (int i = 0; i < n; i++) s += a[i]; return s; }

// A compare whose operand another instruction rewrites before the branch:
// two_steps at -O2 is `cmp w21, w19; add w21, w21, #3; b.lt` (taken iff i
// before the add is below j), and each_bit `cmp w19, #2; lsr w19,
// w19, #1; b.lo` (taken iff the value before the shift is below 2). By the
// register's name, both read the value after it.
extern int check(int);
__attribute__((noinline)) void two_steps(int n) { int i = 0, j = n; while (i < j) { use(i - j); i += 3; j -= 1; } }
__attribute__((noinline)) int each_bit(unsigned x) { int c = 0; do { c += check(x & 1); x >>= 1; } while (x); return c; }
