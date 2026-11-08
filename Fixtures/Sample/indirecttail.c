/* Indirect tail calls: a `br` through a register out of the function. */
struct mem { void (*free)(void *); };
struct map { struct mem *mem; void *refs; };
/* Lowered to: blr for the first free, then `br x1` for the second
   (an indirect tail call). */
void map_free(struct map *m) {
    m->mem->free(m->refs);
    m->mem->free(m);
}
int apply(int (*f)(int), int x) { return f(x + 1); }

#include <stdio.h>
typedef int (*operation)(int);
static int fallback(int x) { return x - 1; }
static volatile unsigned selector;
__attribute__((noinline)) operation choose(operation f) {
    puts("choose");
    return selector & 1 ? f : fallback;
}
int choose_and_apply(operation f, int x) { return choose(f)(x); }
