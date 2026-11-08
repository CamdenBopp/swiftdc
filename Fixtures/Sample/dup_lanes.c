// A general register replicated into vector lanes, stored as a pair of q
// registers and one word read back. `dup v0.2d, x0` puts x0 in each
// eight-byte word; `dup v0.4s, w0` puts w0 in each four-byte lane, so each
// eight-byte word is w0 | w0 << 32, which is not w0.
//
// True behaviour: fillLongs passes get()'s result to sink; fillInts passes
// that result's low four bytes repeated in both halves of the word.
long sunk;
__attribute__((noinline)) void sink(long v) { sunk = v; }
__attribute__((noinline)) void useInts(int *a) { sunk += a[3]; }
__attribute__((noinline)) void useLongs(long *a) { sunk += a[3]; }
__attribute__((noinline)) long get(void) { return sunk; }

void fillInts(void) {
    int x = (int)get();
    int a[8];
    for (int i = 0; i < 8; i++) a[i] = x;
    long w = *(volatile long *)&a[2];
    useInts(a);
    sink(w);
}

void fillLongs(void) {
    long x = get();
    long a[4];
    for (int i = 0; i < 4; i++) a[i] = x;
    long w = *(volatile long *)&a[1];
    useLongs(a);
    sink(w);
}
