/* Calls through a function pointer the program can change (-O2).

   `next` lives in __DATA,__data with countdown as its initial value, and
   `retarget` stores another function there. countdown lowers to
   `adrp x8, _next@PAGE; ldr x1, [x8]; br x1`: the call goes to whatever
   `next` holds when it runs, which the slot's initial bytes (a rebase to
   countdown) do not decide.
   True behaviour: countdown(n) returns 0 when n <= 0, otherwise the result
   of calling the function `next` holds with n - 1. The callee is unknown.

   `hook` is the same shape with an imported initial value: a chained-fixup
   bind to puts in __DATA,__data. `announce` calls whatever `hook` holds.

   `pinned` is the control: the same C, but placed in __DATA_CONST, which
   dyld makes read-only once fixups are applied. Its initial value is the
   only value it can hold, so `viaPinned` calls `twice`. */
#include <stdio.h>

long countdown(long n);
long twice(long n) { return n * 2; }

long (*next)(long) = countdown;
void retarget(void) { next = twice; }
long countdown(long n) { if (n <= 0) return 0; return next(n - 1); }

int (*hook)(const char *) = puts;
void silence(int (*replacement)(const char *)) { hook = replacement; }
int announce(const char *s) { return hook(s); }

long (*pinned)(long) __attribute__((section("__DATA_CONST,__const"))) = twice;
long viaPinned(long n) { return pinned(n + 1); }
