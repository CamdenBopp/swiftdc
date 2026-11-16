// The declarations name exported wrappers; helpers deliberately use the
// machine outliner's nonstandard callee-saved register convention.
#include <assert.h>
#include <stdio.h>
extern long keepGP(void) __asm__("_$s15OutlinedResults6keepGPSiyF");
extern double keepFP(void) __asm__("_$s15OutlinedResults6keepFPSdyF");
extern long gpAcrossFP(void) __asm__("_$s15OutlinedResults10gpAcrossFPSiyF");
extern double fpAcrossGP(void) __asm__("_$s15OutlinedResults10fpAcrossGPSdyF");
extern long keepProducer(void) __asm__("_$s15OutlinedResults12keepProducerSiyF");
extern long writeGP(void) __asm__("_$s15OutlinedResults7writeGPSiyF");
extern double writeFP(void) __asm__("_$s15OutlinedResults7writeFPSdyF");
extern long outlined_result_effects;
int main(void) {
    for (int round = 0; round < 3; ++round) {
        assert(keepGP() == 42);
        assert(keepFP() == 3.0);
        assert(gpAcrossFP() == 42);
        assert(fpAcrossGP() == 3.0);
        assert(keepProducer() == 42);
        assert(writeGP() == 16);
        assert(writeFP() == 4.0);
        assert(outlined_result_effects == 7 * (round + 1));
    }
    puts("PASS 21 outlined result observations; 21 helper effects");
}
