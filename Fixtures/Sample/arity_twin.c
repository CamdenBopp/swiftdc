// An in-image function that shares a name with a libc entry of known arity.
// libc's arc4random takes nothing; this one takes a pointer and a value and
// stores the value through the pointer. The known-arity table is evidence
// only for the library function, so a call to this one passes what its body
// reads (x0 and x1), and a frame address passed in x0 escapes into it.
//
// useTwinStale leaves 9 in x2 at the call, which only the body bounds out;
// relay tail-branches to the twin with its own x0 and x1, so it reads them
// through it.
//
// True behaviour: useTwin and useTwinStale pass (x, 7); useTwinFrame passes
// 7 to sink, because the call stores 7 into its local first; useRelay passes
// (p, 5) to relay.
__attribute__((noinline)) long arc4random(long *slot, long value) { *slot = value; return 0; }

long useTwin(long *x) { return arc4random(x, 7); }

long sunk;
__attribute__((noinline)) void sink(long value) { sunk = value; }

void useTwinFrame(void) {
    volatile long local = 5;
    arc4random((long *)&local, 7);
    sink(local);
}

long useTwinStale(long *p) {
    __asm__ volatile("mov x2, #9" ::: "x2");
    return arc4random(p, 7);
}

__attribute__((noinline)) long relay(long *p, long v) { return arc4random(p, v); }

long useRelay(long *p) { return relay(p, 5); }
