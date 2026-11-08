// A C callee has no signature, so a call shows the argument registers its
// body reads (CalleeRegisterSummary), not every live one. The open readiness
// entry: clang `printf(…); return bump();` with `long bump(void)` rendered
// `bump(printf(…))`.
#include <stdio.h>

static long counter;

__attribute__((noinline)) long bump(void) { return ++counter; }
__attribute__((noinline)) long twice(long a) { return a * 2; }
__attribute__((noinline)) long pick(long a, long b, long c) { return c - a; }

long afterPrint(long x) {
    printf("%ld\n", x);
    return bump();
}

long chained(long x) {
    long y = twice(x);
    return pick(y, 7, x) + bump();
}

// Variadic arguments travel on the stack (Apple arm64): printf takes the format
// in x0 and every value after it from [sp], [sp+8], …
long printTwo(long a, long b) {
    printf("%ld and %ld\n", a, b);
    return a;
}
