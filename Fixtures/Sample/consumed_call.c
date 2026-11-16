// A call whose result only decides a branch is inlined into the branch's
// condition and dropped from the statements before it. probeLevel returns
// `sysctl(…) == 0 ? *p : -1`, lowered as `bl sysctl; cbz w0, …` with each
// arm setting w0. A C function proves no result, so neither arm renders,
// the `if` is dropped, and the call went with it: `{ return }`.
//
// True behaviour: probeLevel calls sysctl(p, 2, 0, 0, 0, 0) once, then
// returns *p or -1. probeOrWarn calls sysctl(p, 2, 0, 0, 0, 0) once and
// reportFailure() when it fails: its `if` has a body, so the call stays in the
// condition, once.
#include <sys/sysctl.h>

void reportFailure(void);

int probeLevel(int *p) { return sysctl(p, 2, 0, 0, 0, 0) == 0 ? *p : -1; }
void probeOrWarn(int *p) { if (sysctl(p, 2, 0, 0, 0, 0)) reportFailure(); }
