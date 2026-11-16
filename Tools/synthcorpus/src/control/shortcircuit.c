// Short-circuit && and || with side effects: the right side must stay
// conditional on the left.
extern int check(int);
extern void sink(int);
// and_calls: the second check is reached only when the first is nonzero.
// EXPECT structured O0 _and_calls :: re:if \(check\(…\)\) \{\n\s+if \(check\(…\)\) \{\n\s+sink
// EXPECT structured O1,O2,Os _and_calls :: re:if \(!check\(…\)\) \{\n\s+return\n\s+\} else \{\n\s+if \(!check\(…\)\)
// or_calls: the second check runs only when the first returned 0.
// EXPECT structured * _or_calls :: re:if \(check\(…\)\) \{\n\s+loc_\w+:\n\s+sink\(…\)
// FORBID structured * _or_calls :: re:^\s+check\(…\)$
// guard_call: x > 0 (signed) guards the call.
// EXPECT structured O0 _guard_call :: >>ˢ 32) > 0)
// EXPECT structured O1,O2,Os _guard_call :: >>ˢ 32) < 1)
// FORBID structured * _guard_call :: re:ᵁ [01]\)

// TRUE: check(1) always; check(2) only if check(1) != 0; sink(1) iff both.
void and_calls(void) { if (check(1) && check(2)) sink(1); }

// TRUE: check(3) always; check(4) only if check(3) == 0; sink(2) iff either.
void or_calls(void) { if (check(3) || check(4)) sink(2); }

// TRUE: returns x > 0 && check(x) (check only when x > 0).
int guard_call(int x) { return x > 0 && check(x); }

// TRUE: p null → 0 without dereference; else returns *p == 7.
int null_guard(const int *p) { return p && *p == 7; }

// Mixed: TRUE: sink(3) iff (check(5) || check(6)) && check(7); check(6) only
// when check(5)==0; check(7) only when one of the first two is nonzero.
void mixed_calls(void) { if ((check(5) || check(6)) && check(7)) sink(3); }
