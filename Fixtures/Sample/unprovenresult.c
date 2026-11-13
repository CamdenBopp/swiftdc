// C functions no signature describes and no caller calls: whether each
// returns a value is not in the binary, so swiftdc shows what x0 holds at
// each `ret` as a comment, never as a returned value.
//   konst:   `mov w0, #42; ret`            x0 = 42
//   scaled:  a * 3 + b                     x0 = ((arg0 * 3) + arg1)
//   twoArgs: use(a) + b                    no comment: built from a call's
//            result, which a comment would show as a second call
//   quiet:   void, x0 untouched            no comment: x0 is still arg0,
//            which every function that leaves x0 alone would show
// -O2, external `use` so the call stays.
extern long use(long);
long konst(void) { return 42; }
long scaled(long a, long b) { return a * 3 + b; }
long twoArgs(long a, long b) { return use(a) + b; }
void quiet(long a, long b) { *(volatile long *)b = a; }
