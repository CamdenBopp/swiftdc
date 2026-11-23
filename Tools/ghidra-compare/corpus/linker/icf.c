// ICF fixture. True behaviour: twin_a and twin_b are identical (x*3+11) and are
// folded by -Wl,-deduplicate into one body. use_a calls twin_a, use_b calls twin_b.
// A render naming twin_a at use_b's call site is a misattribution only if the
// two have distinct behaviour; here both names are correct for the body, so the
// sound render names the call target address with both names or either.
// different_c is NOT identical (x*3+12) and must not be merged.
__attribute__((noinline, visibility("hidden"))) long twin_a(long x) { return x * 3 + 11; }
__attribute__((noinline, visibility("hidden"))) long twin_b(long x) { return x * 3 + 11; }
__attribute__((noinline, visibility("hidden"))) long different_c(long x) { return x * 3 + 12; }
long use_a(long x) { return twin_a(x) + 1; }
long use_b(long x) { return twin_b(x) + 2; }
long use_c(long x) { return different_c(x) + 3; }
