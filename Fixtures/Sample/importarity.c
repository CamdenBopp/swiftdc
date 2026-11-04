/* C imports with no prototype in the binary: nothing here bounds their arity
   (-O2, resolved at load time).

   t1: `bl g0; b h0`. Nothing sets x0 for h0, so it is not h0's argument.
   t4: `b ext` forwards x0 untouched: ext(a) is a real argument, and a
       trimmed list read it as ext().
   d4: `mov w0, #1; bl ext`. x1 still holds the entry value of b, which is
       not an argument of ext.
   c2: `bl extd; fadd d0, d0, d0; b sinkD`: sinkD takes twice extd's result,
       not the result. */
long g0(void); void h0(void); void sinkD(double); double extd(void); long ext(long);
void t1(void) { g0(); h0(); }
void c2(void) { sinkD(extd() * 2); }
void t4(long a) { ext(a); }
long d4(long a, long b) { return ext(1) + b; }
