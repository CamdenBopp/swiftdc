#include <assert.h>
#include <limits.h>
#include <stdio.h>
extern long probe(long) __asm__("_$s14OutlineScratch5probeyS2iF");
extern void outline_unchanged_probe(unsigned long *);
int main(void) {
    const long words[] = {LONG_MIN, -1000000, -1, 0, 1, 37, LONG_MAX};
    for (unsigned i = 0; i < sizeof(words)/sizeof(words[0]); ++i)
        assert(probe(words[i]) == words[i]);
    for (unsigned i = 0; i < sizeof(words)/sizeof(words[0]); ++i) {
        unsigned long before[5], after[5];
        for (unsigned j=0;j<5;++j) before[j]=after[j]=(unsigned long)words[i]+j;
        outline_unchanged_probe(after);
        for (unsigned j=0;j<5;++j) assert(before[j]==after[j]);
    }
    puts("PASS 14 native x8 scratch-word/buffer observations");
}
