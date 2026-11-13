// Machine-outliner fixture (-Oz -mllvm -enable-machine-outliner=always).
// True behaviour: each fN(p) calls sink(p[0]+p[1]*7, p[2]^p[3], 99, 100) and
// returns its result. The outliner shares the argument setup and tail call
// between fN as OUTLINED_FUNCTION_n.
__attribute__((noinline)) long sink(long a, long b, long c, long d);
long f1(long *p) { return sink(p[0] + p[1] * 7, p[2] ^ p[3], 99, 100); }
long f2(long *p) { return sink(p[0] + p[1] * 7, p[2] ^ p[3], 99, 100); }
long f3(long *p) { return sink(p[0] + p[1] * 7, p[2] ^ p[3], 99, 100) + 1; }
long f4(long *p) { return sink(p[0] + p[1] * 7, p[2] ^ p[3], 99, 100) + 2; }
long sink(long a, long b, long c, long d) { return a - b + c * d; }
