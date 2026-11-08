// Calls to runtime entry points whose known C arity was wrong in the table,
// or missing for a function that takes nothing. Each prototype is the
// header's: `exit(int)` (_stdlib.h:165), `__error(void)` (sys/errno.h:80),
// `pthread_main_np(void)` (pthread.h:539), `arc4random(void)`
// (_stdlib.h:287), `dispatch_group_create(void)` (dispatch/group.h:60),
// `objc_end_catch(void)` and `objc_terminate(void)` (objc/objc-exception.h:56,
// :60), and the weak-reference entry points of Swift's
// include/swift/Runtime/ObjCBridge.h:46-50: `objc_moveWeak(id *, id *)`,
// `objc_copyWeak(id *, id *)`, `objc_loadWeakRetained(id *)`.
//
// True behaviour: quit passes 3 to exit. loadSlot passes only the slot's
// address, and copySlot and moveSlot only their two slots. Each function
// after them calls an entry point that takes nothing while x0 still holds
// the result of malloc(8), which is not passed.
#include <dispatch/dispatch.h>
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>

typedef void *id;
extern id objc_loadWeakRetained(id *);
extern void objc_copyWeak(id *, id *);
extern void objc_moveWeak(id *, id *);
extern void objc_end_catch(void);
extern void objc_terminate(void);

struct holder { long tag; id delegate; };

void quit(void) { exit(3); }
id loadSlot(struct holder *h) { return objc_loadWeakRetained(&h->delegate); }
void copySlot(id *to, id *from) { objc_copyWeak(to, from); }
void moveSlot(id *to, id *from) { objc_moveWeak(to, from); }

// A volatile store keeps p alive past the call, so -O2 cannot drop the
// malloc and x0 still holds it at the call.
static void *volatile kept;
int lastErrno(void) { void *p = malloc(8); int e = errno; kept = p; return e; }
void *mainOr(void) { void *p = malloc(8); if (pthread_main_np()) return p; free(p); return 0; }
unsigned roll(void) { void *p = malloc(8); unsigned r = arc4random(); kept = p; return r; }
dispatch_group_t makeGroup(void) { void *p = malloc(8); dispatch_group_t g = dispatch_group_create(); kept = p; return g; }
void endCatch(void) { void *p = malloc(8); objc_end_catch(); kept = p; }
void terminate(void) { void *p = malloc(8); objc_terminate(); kept = p; }
