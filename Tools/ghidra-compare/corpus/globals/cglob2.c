// Global value flow into calls. True behaviour per function.
long sink1, sink2;
__attribute__((noinline)) void use(long x) { sink1 = x; }
__attribute__((noinline)) void use2(long x, long y) { sink1 = x; sink2 = y; }
extern void mutate(void);
long gMut = 5;                         // __DATA,__data: mutable, value at call time unknown
const long kConst = 6;                 // __TEXT,__const: provably 6 (may be folded by compiler anyway)
const long kArr[4] = {100, 200, 300, 400}; // __TEXT,__const
long *const kPtr = &gMut;              // __DATA_CONST (rebased pointer): provably &gMut
long *gPtr = &gMut;                    // __DATA,__data: pointer may change
const char *const kStr = "const-str";  // __DATA_CONST pointer to cstring
const char *gStr = "mut-str";          // __DATA,__data pointer, may change
struct S { long a, b; } gS = {1, 2};
volatile long gVol = 3;

// use(gMut): value unknown (must not render 5)
void passMut(void) { use(gMut); }
// use(gMut) twice around mutate(): two separate loads, both unknown
void passMutTwice(void) { use2(gMut, (mutate(), gMut)); }
// use(*kPtr): kPtr is &gMut, value of gMut unknown
void passPtr(void) { use(*kPtr); }
// use(*gPtr): gPtr may change
void passGPtr(void) { use(*gPtr); }
// use((long)kStr) : "const-str"
void passKStr(void) { use((long)kStr); }
// use((long)gStr) : value unknown, must not render "mut-str"
void passGStr(void) { use((long)gStr); }
// use(kArr[i&3])
void passArr(int i) { use(kArr[i & 3]); }
// use(gS.b) unknown
void passField(void) { use(gS.b); }
// gS.a = 9 then use(gS.a) -> 9 (store-to-load forward is fine) 
void storeThenUse(void) { gS.a = 9; use(gS.a); }
// use(gVol) unknown
void passVol(void) { use(gVol); }
// *gPtr = 4; use(gMut): aliasing, gMut unknown (gPtr may point to gMut or not)
void aliasStore(void) { gMut = 1; *gPtr = 4; use(gMut); }
