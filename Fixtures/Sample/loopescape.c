// Loops whose header learns a fact only over the back edge (C, -O0).
//
// lateEscape: &i escapes at the end of the body through a plain store to a
// global, so from the second lap poke() may write i. True behaviour: with
// poke adding 100 through g, the loop runs twice and returns 102.
//
// staleEntryPointer: p holds &j on entry and &i after the first lap, so
// from the second lap `*p += 100` writes i, not j. True behaviour: the
// loop runs twice and returns 202 (i = 102, j = 100).
long *g;
__attribute__((noinline)) void poke(void) { if (g) *g += 100; }

long lateEscape(void) {
    long i = 0;
    while (i < 5) { poke(); i++; g = &i; }
    return i;
}

long staleEntryPointer(void) {
    long i = 0, j = 0;
    long *p = &j;
    while (i < 5) { *p += 100; i++; p = &i; }
    return i + j;
}
