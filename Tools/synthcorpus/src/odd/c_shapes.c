// LEVELS: O0 O1 O2 Os
// The compiler-generated forms of three odd shapes.
//
// alloca_use(n): `__builtin_alloca(n)` lowers to a `sub sp, sp, xN` on a
// rounded size (and a `mov sp, …` restore at -O0). True behaviour: returns
// use(p) where p[0] == 1.
//
// checked(x): ends in a call to abort() on the x < 0 path, with no `ret`
// after it (abort is noreturn). True behaviour: returns x when x >= 0.
//
// protect(n): a 64-byte local array passed out, so the stack protector
// guards the frame; the failure path calls __stack_chk_fail and never
// returns. True behaviour: returns use(buf) after filling buf with n.
#include <stdlib.h>
#include <string.h>
extern long use(char *);
long alloca_use(long n) { char *p = __builtin_alloca(n); p[0] = 1; return use(p); }
long checked(long x) { if (x < 0) abort(); return x; }
long protect(long n) { char buf[64]; memset(buf, (int)n, sizeof buf); return use(buf); }

// EXPECT structured * alloca_use :: use(
// EXPECT structured * checked :: abort
// FORBID structured * checked :: return ?
// EXPECT structured * protect :: use(
// FORBID structured * protect :: return ?
// At -O0 the noreturn call is followed by the success path's code (clang
// emits `bl _abort` and the join block right after it), so the bytes fall
// through but execution never does. abort and __stack_chk_fail are known
// noreturn: a render that lets either path fall out of its `if` into the
// `return` claims a path that does not exist.
// FORBID structured * checked :: re:abort\(\)\n\s*\}\n\s*return
// FORBID structured * protect :: re:__stack_chk_fail\(\)\n\s*\}\n\s*return
// FORBID structured * alloca_use :: re:__stack_chk_fail\(\)\n\s*\}\n\s*return
