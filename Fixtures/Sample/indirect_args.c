// Calls through a register, whose arity nothing records. True behaviour:
// callGlobal(a, b) calls gp(a, b), with a and b still in x0 and x1 from the
// entry, and then sets gS; callReg(g, a, b) calls g(a, b) and returns its
// result plus one.
typedef long (*fn2)(long, long);
long gS;
void (*gp)(long, long);
void callGlobal(long a, long b) { gp(a, b); gS = 1; }
long callReg(fn2 g, long a, long b) { return g(a, b) + 1; }
