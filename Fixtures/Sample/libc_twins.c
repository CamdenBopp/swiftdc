// In-image functions named like C library functions, with other bodies: a
// vendored or instrumented replacement. Built with -fno-builtin so clang
// keeps the calls. A table kept by a library function's name is evidence
// only for that function.
//
// memset and memcpy copy nothing. The value tracker models a call to the
// library's memset or memcpy as the stores it performs.
//
// printf takes two longs and fprintf a label and two longs, all in
// registers. A call to the library's printf or fprintf passes its variadic
// arguments on the stack, as the format describes.
//
// True behaviour: useFill and useCopy both pass 1 to sink, because neither
// call writes the local; the 0 and the x passed to the calls never reach it.
// usePrintf calls printf(x, 4) and useFprintf fprintf("%ld\n", x, 9).
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

__attribute__((noinline)) int printf(long a, long b) { count += a * b; return 0; }
__attribute__((noinline)) int fprintf(const char *label, long a, long b) { count += a + b + label[0]; return 0; }
int usePrintf(long x) { return printf(x, 4); }
int useFprintf(long x) { return fprintf("%ld\n", x, 9); }
