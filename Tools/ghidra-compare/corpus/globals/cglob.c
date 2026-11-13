// C globals fixture. True behaviour stated per function.
#include <stddef.h>
int gCounter = 5;            // __DATA,__data
int gOther = 7;              // __DATA,__data, adjacent to gCounter
static int sHidden = 3;      // local symbol
const int kTable[8] = {10,20,30,40,50,60,70,80}; // __TEXT,__const
struct Pt { int x; int y; long z; };
struct Pt gPoint = {1,2,3};
extern int extArr[];         // undefined extern array (from libc? no) -> define in another lib
__thread int tlsVar = 9;
_Thread_local long tlsLong;
extern int weakExt __attribute__((weak_import));
__attribute__((weak)) int weakDef = 11;
const char *gName = "hello-global";
int bss[16];

// returns gCounter + 1, increments gCounter
int bump(void) { return ++gCounter; }
// returns gOther (must not be named gCounter)
int readOther(void) { return gOther; }
// returns sHidden * 2
int readHidden(void) { return sHidden * 2; }
// returns kTable[i & 7]
int tableAt(int i) { return kTable[i & 7]; }
// sets gPoint.y = v; returns gPoint.z
long setY(int v) { gPoint.y = v; return gPoint.z; }
// returns tlsVar + 1, sets tlsVar
int tlsBump(void) { return ++tlsVar; }
long tlsLongGet(void) { return tlsLong; }
// returns weakExt if linked, else -1
int weakRead(void) { return &weakExt ? weakExt : -1; }
int weakDefRead(void) { return weakDef; }
const char *nameGet(void) { return gName; }
// bss[i] = v
void bssSet(int i, int v) { bss[i] = v; }
// returns &bss[4] - pointer arithmetic
int *bssPtr(void) { return &bss[4]; }
static int helper(int a) { return a * 3 + gOther; }
int callHelper(int a) { return helper(a) + helper(a+1); }
