#include <stdint.h>
#include <stdio.h>
extern int projectionAliasS1B0M0(void *);
extern int projectionAliasS1B0M1(void *);
extern int projectionAliasS1B0M2(void *);
extern int projectionAliasS1B0M3(void *);
extern int projectionAliasS1B0M4(void *);
extern int projectionAliasS1B0M5(void *);
extern int projectionAliasS1B0M6(void *);
extern int projectionAliasS1B1M0(void *);
extern int projectionAliasS1B1M1(void *);
extern int projectionAliasS1B1M2(void *);
extern int projectionAliasS1B1M3(void *);
extern int projectionAliasS1B1M4(void *);
extern int projectionAliasS1B1M5(void *);
extern int projectionAliasS1B1M6(void *);
extern int projectionAliasS1B2M0(void *);
extern int projectionAliasS1B2M1(void *);
extern int projectionAliasS1B2M2(void *);
extern int projectionAliasS1B2M3(void *);
extern int projectionAliasS1B2M4(void *);
extern int projectionAliasS1B2M5(void *);
extern int projectionAliasS1B2M6(void *);
extern int projectionAliasS2B0M0(void *);
extern int projectionAliasS2B0M1(void *);
extern int projectionAliasS2B0M2(void *);
extern int projectionAliasS2B0M3(void *);
extern int projectionAliasS2B0M4(void *);
extern int projectionAliasS2B0M5(void *);
extern int projectionAliasS2B0M6(void *);
extern int projectionAliasS2B1M0(void *);
extern int projectionAliasS2B1M1(void *);
extern int projectionAliasS2B1M2(void *);
extern int projectionAliasS2B1M3(void *);
extern int projectionAliasS2B1M4(void *);
extern int projectionAliasS2B1M5(void *);
extern int projectionAliasS2B1M6(void *);
extern int projectionAliasS2B2M0(void *);
extern int projectionAliasS2B2M1(void *);
extern int projectionAliasS2B2M2(void *);
extern int projectionAliasS2B2M3(void *);
extern int projectionAliasS2B2M4(void *);
extern int projectionAliasS2B2M5(void *);
extern int projectionAliasS2B2M6(void *);
extern int projectionAliasUnrelatedFrameWord(void *);
extern int projectionAliasTwoProducers(void *);
extern int projectionAliasIndirectResult(void *);
extern int projectionAliasLogicalResultWrites(void *);
extern int projectionAliasLogicalResultIgnored(void *);
extern int projectionAliasTupleResultWrites(void *);
int main(void) {
    uintptr_t witness[16] = {0};
    uintptr_t metadata[2] = {(uintptr_t)witness, 0};
    struct { const char *name; int (*call)(void *); int boxed; int expected; } cases[] = {
        {"projectionAliasS1B0M0",projectionAliasS1B0M0,0,8},
        {"projectionAliasS1B0M1",projectionAliasS1B0M1,0,42},
        {"projectionAliasS1B0M2",projectionAliasS1B0M2,0,42},
        {"projectionAliasS1B0M3",projectionAliasS1B0M3,0,42},
        {"projectionAliasS1B0M4",projectionAliasS1B0M4,0,42},
        {"projectionAliasS1B0M5",projectionAliasS1B0M5,0,8},
        {"projectionAliasS1B0M6",projectionAliasS1B0M6,0,42},
        {"projectionAliasS1B1M0",projectionAliasS1B1M0,1,8},
        {"projectionAliasS1B1M1",projectionAliasS1B1M1,1,42},
        {"projectionAliasS1B1M2",projectionAliasS1B1M2,1,42},
        {"projectionAliasS1B1M3",projectionAliasS1B1M3,1,42},
        {"projectionAliasS1B1M4",projectionAliasS1B1M4,1,42},
        {"projectionAliasS1B1M5",projectionAliasS1B1M5,1,8},
        {"projectionAliasS1B1M6",projectionAliasS1B1M6,1,42},
        {"projectionAliasS1B2M0",projectionAliasS1B2M0,2,8},
        {"projectionAliasS1B2M1",projectionAliasS1B2M1,2,42},
        {"projectionAliasS1B2M2",projectionAliasS1B2M2,2,42},
        {"projectionAliasS1B2M3",projectionAliasS1B2M3,2,42},
        {"projectionAliasS1B2M4",projectionAliasS1B2M4,2,42},
        {"projectionAliasS1B2M5",projectionAliasS1B2M5,2,8},
        {"projectionAliasS1B2M6",projectionAliasS1B2M6,2,42},
        {"projectionAliasS2B0M0",projectionAliasS2B0M0,0,8},
        {"projectionAliasS2B0M1",projectionAliasS2B0M1,0,42},
        {"projectionAliasS2B0M2",projectionAliasS2B0M2,0,42},
        {"projectionAliasS2B0M3",projectionAliasS2B0M3,0,42},
        {"projectionAliasS2B0M4",projectionAliasS2B0M4,0,42},
        {"projectionAliasS2B0M5",projectionAliasS2B0M5,0,8},
        {"projectionAliasS2B0M6",projectionAliasS2B0M6,0,42},
        {"projectionAliasS2B1M0",projectionAliasS2B1M0,1,8},
        {"projectionAliasS2B1M1",projectionAliasS2B1M1,1,42},
        {"projectionAliasS2B1M2",projectionAliasS2B1M2,1,42},
        {"projectionAliasS2B1M3",projectionAliasS2B1M3,1,42},
        {"projectionAliasS2B1M4",projectionAliasS2B1M4,1,42},
        {"projectionAliasS2B1M5",projectionAliasS2B1M5,1,8},
        {"projectionAliasS2B1M6",projectionAliasS2B1M6,1,42},
        {"projectionAliasS2B2M0",projectionAliasS2B2M0,2,8},
        {"projectionAliasS2B2M1",projectionAliasS2B2M1,2,42},
        {"projectionAliasS2B2M2",projectionAliasS2B2M2,2,42},
        {"projectionAliasS2B2M3",projectionAliasS2B2M3,2,42},
        {"projectionAliasS2B2M4",projectionAliasS2B2M4,2,42},
        {"projectionAliasS2B2M5",projectionAliasS2B2M5,2,8},
        {"projectionAliasS2B2M6",projectionAliasS2B2M6,2,42},
        {"projectionAliasUnrelatedFrameWord",projectionAliasUnrelatedFrameWord,0,165},
        {"projectionAliasTwoProducers",projectionAliasTwoProducers,0,49},
        {"projectionAliasIndirectResult",projectionAliasIndirectResult,0,42},
        {"projectionAliasLogicalResultWrites",projectionAliasLogicalResultWrites,0,42},
        {"projectionAliasLogicalResultIgnored",projectionAliasLogicalResultIgnored,0,8},
        {"projectionAliasTupleResultWrites",projectionAliasTupleResultWrites,0,42},
    };
    for (unsigned i=0; i<sizeof cases/sizeof *cases; ++i) {
        witness[10] = cases[i].boxed ? (1u<<17) | 7u : 0;
        int actual = cases[i].call(&metadata[1]);
        printf("%s expected=%d actual=%d\n", cases[i].name, cases[i].expected, actual);
        if (actual != cases[i].expected) return 1;
    }
    puts("PASS 48 returned-projection-alias observations");
    return 0;
}
