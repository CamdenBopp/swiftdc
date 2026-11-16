// C integer probes. Comments state true behaviour.
extern void sink(long);
long promote(int a, int b) { return (long)a * b; }            // 32x32 signed -> 64: smull
long promoteU(unsigned a, unsigned b) { return (long)a * b; }  // umull
int  wrap32(int a, int b) { return a * b; }                    // low 32 bits, w-reg
unsigned long zext(unsigned a) { return a; }                   // mov w0,w0
long sext(int a) { return a; }                                 // sxtw
int  ult32(unsigned a, unsigned b) { return a < b; }           // unsigned
int  slt32(int a, int b) { return a < b; }
int  ucmpneg(unsigned a) { return a > 0xfffffff0u; }           // unsigned vs big const
int  sdiv32(int a, int b) { return a / b; }                    // no trap in C; sdiv w
unsigned udiv32(unsigned a, unsigned b) { return a / b; }
int  srem32(int a, int b) { return a % b; }
long sdivc(long a) { return a / -3; }
long mod16(long a) { return a % 16; }
unsigned long umod16(unsigned long a) { return a % 16; }
long sarv(long a, long n) { return a >> n; }                   // asr x0, x0, x1 (n mod 64)
unsigned long shrv(unsigned long a, unsigned n) { return a >> n; }
int  sar32(int a, int n) { return a >> n; }                    // asr w (n mod 32)
long bigimm(void) { return 0xffff0000ffff0000L; }
long negimm(long a) { return a * -7; }
int  cnt(unsigned long a) { return __builtin_popcountl(a); }
int  clz32(unsigned a) { return __builtin_clz(a); }
int  ctz(unsigned long a) { return __builtin_ctzl(a); }
long absl(long a) { return a < 0 ? -a : a; }
int  bitf(unsigned a) { return (a >> 3) & 0x1f; }
int  sbitf(int a) { return (a << 20) >> 27; }                  // sbfx w bits 7..11
int  ovf(long a, long b, long *r) { return __builtin_add_overflow(a, b, r); }
unsigned short u16add(unsigned short a, unsigned short b) { return a + b; }
signed char s8ret(int a) { return (signed char)a; }
long fromS8(signed char c) { return c * 2; }                   // c already extended by caller (Apple ABI)
long fromU16(unsigned short c) { return c + 1; }
int  between(long a) { return a > 5 && a < 100; }
int  ubetween(unsigned long a, unsigned long b) { return a > b && b > 3; }
void callu(unsigned a) { sink((long)(int)a); }                 // sign-reinterpret then extend
long cselU(unsigned long a, unsigned long b) { return a >= b ? 11 : 22; }
long cselS(long a, long b) { return a >= b ? 11 : 22; }
long branchU(unsigned long a, unsigned long b) { if (a > b) sink(1); return 3; }
long branchS(long a, long b) { if (a > b) sink(1); return 3; }
