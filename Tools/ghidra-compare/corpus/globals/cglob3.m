// Extern globals through the GOT; CFString globals. True behaviour per function.
#import <Foundation/Foundation.h>
extern long extVal;          // GOT bind: value at runtime unknown
extern long extArr[];        // GOT bind
extern const char *extStr;
long sink1;
__attribute__((noinline)) void use(long x) { sink1 = x; }
__attribute__((noinline)) void useObj(id x) { sink1 = (long)x; }
// use(&extVal): the address of extVal
void passAddr(void) { use((long)&extVal); }
// use(extVal): its value, unknown
void passVal(void) { use(extVal); }
// use(extArr[2]): unknown
void passArr2(void) { use(extArr[2]); }
// use(&extArr[2])
void passArrAddr(void) { use((long)&extArr[2]); }
// use((long)extStr): unknown pointer value
void passStr(void) { use((long)extStr); }
// extVal = 3
void storeExt(void) { extVal = 3; }
NSString *const kCF = @"cf-const";   // __DATA_CONST? pointer to CFString
NSString *gCF = @"cf-mut";           // __DATA: may change
// useObj(@"cf-const")
void passKCF(void) { useObj(kCF); }
// useObj(gCF): unknown
void passGCF(void) { useObj(gCF); }
// useObj(@"direct")
void passLit(void) { useObj(@"direct"); }
