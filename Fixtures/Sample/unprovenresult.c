// C functions no signature describes and no caller calls: whether each
// returns a value is not in the binary, so swiftdc shows what x0 holds at
// each `ret` as a comment, never as a returned value.
//   konst:   `mov w0, #42; ret`            x0 = 42
//   scaled:  a * 3 + b                     x0 = ((arg0 * 3) + arg1)
//   twoArgs: use(a) + b                    let r0 = use(…); x0 = (r0 + arg1):
//            the call bound, so it is spelled once
//   lastCall: use(a); use(b);              no comment: x0 is only the last
//            call's result, which every function ending in a call leaves
//   quiet:   void, x0 untouched            no comment: x0 is still arg0,
//            which every function that leaves x0 alone would show
// -O2, external `use` so the call stays.
extern long use(long);
long konst(void) { return 42; }
long scaled(long a, long b) { return a * 3 + b; }
long twoArgs(long a, long b) { return use(a) + b; }
// hidden: built from a call swiftdc hides as runtime bookkeeping and so
// cannot bind; a comment would be the only place the call appeared.
extern void *swift_task_alloc(unsigned long);
long hidden(unsigned long n) { return (long)swift_task_alloc(n) + 8; }
// eitherCall: x0 is one call's result or the other's, by path: leftover,
// exactly as after a single call (a function returning one of them
// compiles the same).
extern long other(long);
void eitherCall(long a, long b) { long r = a ? use(a) : other(a); *(volatile long *)b = r; }
void lastCall(long a, long b) { use(a); *(volatile long *)b = use(b); }
void quiet(long a, long b) { *(volatile long *)b = a; }
