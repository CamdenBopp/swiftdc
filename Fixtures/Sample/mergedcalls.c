// Direct calls inside a stripped executable with no LC_FUNCTION_STARTS:
// with no symbols and no recorded boundaries, pub and its static helpers
// decode as one body, and each `bl` lands inside it. The target of a `bl`
// is in the instruction, so it is a direct call to a known address, only
// unnamed: rendered as `indirect_call(?, …)` it claimed a target was not
// known.
//
// True behaviour: pub(x) returns h2(x) + h1(x + 1), h2(x) is h1(x) ^ 7,
// and h1(x) is 3x + 1.
__attribute__((noinline)) static int h1(int x) { return x * 3 + 1; }
__attribute__((noinline)) static int h2(int x) { return h1(x) ^ 7; }
__attribute__((noinline)) int pub(int x) { return h2(x) + h1(x + 1); }
int main(int c, char **v) { return pub(c); }
