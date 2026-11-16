// fcmp with NaN: ordered vs unordered conditions.
extern void sink(int);
// No float condition may render as an ordered integer compare that
// mishandles NaN. f_nle_branch: `fcmp; b.ls` skips the call iff a <= b
// (ordered); the call runs for a > b OR unordered, so `a > b` as the
// call's condition drops NaN.
// FORBID structured * _f_nle_branch :: re:(d0|arg0) > (d1|arg1)

// TRUE: 1 iff a < b; false when either is NaN (b.mi / cset mi).
int f_lt(double a, double b) { return a < b; }
// TRUE: 1 iff !(a < b): a >= b or unordered (cset pl).
int f_not_lt(double a, double b) { return !(a < b); }
// TRUE: 1 iff a >= b; false on NaN (b.ge).
int f_ge(double a, double b) { return a >= b; }
// TRUE: 1 iff a != b; true for NaN (cset ne).
int f_ne(float a, float b) { return a != b; }
// TRUE: 1 iff a == b; false for NaN.
int f_eq(float a, float b) { return a == b; }
// TRUE: 1 iff x is NaN (fcmp x, x; cset vs).
int f_isnan(double x) { return x != x; }
// TRUE: sink(1) iff a > 0.0 (false for NaN), else sink(2).
void f_branch(double a) { if (a > 0.0) sink(1); else sink(2); }
// TRUE: sink(3) iff !(a <= b): unordered or greater.
void f_nle_branch(double a, double b) { if (!(a <= b)) sink(3); }
// TRUE: returns the larger by `a > b ? a : b` (fcsel gt).
double f_max(double a, double b) { return a > b ? a : b; }
