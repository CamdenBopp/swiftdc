#include <stdint.h>
#include <stdio.h>
extern int boxedProjectionForeignDirect(void *);
extern int boxedProjectionForeignIndirect(void *);
extern int boxedProjectionGenuineOptimized(void *);
extern int boxedProjectionGenuineDebug(void *);
extern int boxedProjectionGenuineIndirect(void *);
extern int boxedProjectionMutatingLookalike(void *);
extern int boxedProjectionMutableCall(void *);
extern void boxedProjectionSetMutableTarget(uintptr_t);
extern uintptr_t __swift_project_boxed_opaque_existential_0(void *);

int main(void) {
    uintptr_t witness[16] = {0};
    uintptr_t metadata[2] = {(uintptr_t)witness, 0};
    void *type = &metadata[1];
    struct { int (*call)(void *); int expected; unsigned boxed; } cases[] = {
        {boxedProjectionForeignDirect,42,0}, {boxedProjectionForeignIndirect,42,0},
        {boxedProjectionGenuineOptimized,8,0}, {boxedProjectionGenuineDebug,8,0},
        {boxedProjectionGenuineIndirect,8,0}, {boxedProjectionMutatingLookalike,42,1},
        {boxedProjectionMutableCall,42,0},
    };
    boxedProjectionSetMutableTarget((uintptr_t)__swift_project_boxed_opaque_existential_0);
    unsigned count = 0;
    for (unsigned i=0; i<sizeof(cases)/sizeof(*cases); ++i) {
        witness[10] = cases[i].boxed ? (1u<<17) | 7u : 0;
        int value = cases[i].call(type);
        if (value != cases[i].expected) {
            fprintf(stderr,"FAIL projection case %u: %d != %d\n",i,value,cases[i].expected);
            return 1;
        }
        ++count;
    }
    printf("PASS %u projection-call observations\n",count);
    return 0;
}
