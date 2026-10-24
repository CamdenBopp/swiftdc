// In-image functions named like C library functions, with other bodies: a
// vendored or instrumented replacement. Built with -fno-builtin so clang
// keeps the calls. A table kept by a library function's name is evidence
// only for that function.
//
// memset and memcpy copy nothing. The value tracker models a call to the
// library's memset or memcpy as the stores it performs.
//
// True behaviour: useFill and useCopy both pass 1 to sink, because neither
// call writes the local; the 0 and the x passed to the calls never reach it.
long count;
__attribute__((noinline)) void *memcpy(void *d, const void *s, unsigned long n) { count += n + (long)s; return d; }
__attribute__((noinline)) void *memset(void *d, int c, unsigned long n) { count += c + (long)n; return d; }

long sunk;
__attribute__((noinline)) void sink(long value) { sunk = value; }

void useFill(void) {
    volatile long a = 1;
    memset((void *)&a, 0, 8);
    sink(a);
}

void useCopy(long x) {
    volatile long a[3] = {1, x, 2};
    memcpy((void *)&a[0], (const void *)&a[1], 8);
    sink(a[0]);
}
