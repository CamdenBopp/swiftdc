// Calls to runtime entry points of known C arity whose every operand is
// loaded through an unknown pointer. Nothing about the call is tracked, so
// no call site is recorded, and a renderer that reads arity from the
// recorded values printed `memmove()`: a call that takes nothing.
//
// True behaviour: moveJob calls memmove(j->dst, j->src, j->n), freeJob
// calls free(j->dst), clearJob calls bzero(j->dst, j->n) and growJob
// calls malloc(j->n), findJob calls memchr(j->dst, (int)j->n, j->n) and
// sizeJob calls malloc_size(j->dst); each passes all of its parameters. -O0 checks the
// length, so moveJob calls __memmove_chk(…, -1) there, and clearJob
// ___bzero_chk.
#include <stdlib.h>
#include <string.h>
#include <malloc/malloc.h>

struct job { void *dst; void *src; size_t n; };

void moveJob(struct job *j) { memmove(j->dst, j->src, j->n); }
void freeJob(struct job *j) { free(j->dst); }
void clearJob(struct job *j) { bzero(j->dst, j->n); }
void *growJob(struct job *j) { return malloc(j->n); }
void *findJob(struct job *j) { return memchr(j->dst, (int)j->n, j->n); }
size_t sizeJob(struct job *j) { return malloc_size(j->dst); }
