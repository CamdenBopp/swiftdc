// Calls to runtime entry points of known C arity whose every operand is
// loaded through an unknown pointer. Nothing about the call is tracked, so
// no call site is recorded, and a renderer that reads arity from the
// recorded values printed `memmove()`: a call that takes nothing.
//
// True behaviour: moveJob calls memmove(j->dst, j->src, j->n) and freeJob
// calls free(j->dst); each passes all of its parameters. -O0 checks the
// length, so moveJob calls __memmove_chk(…, -1) there.
#include <stdlib.h>
#include <string.h>

struct job { void *dst; void *src; size_t n; };

void moveJob(struct job *j) { memmove(j->dst, j->src, j->n); }
void freeJob(struct job *j) { free(j->dst); }
