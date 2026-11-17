#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
extern unsigned long sub_BLInput_caller(unsigned long);
extern double sub_BLInput_fpCaller(double);
static uint64_t bits(double x) { uint64_t u; memcpy(&u,&x,sizeof(u)); return u; }
extern unsigned long sub_BLInput_canonicalGPCaller(unsigned long);
extern double sub_BLInput_canonicalFPCaller(double);
extern unsigned long sub_BLInput_zeroGPCaller(void);
extern double sub_BLInput_zeroFPCaller(void);
extern unsigned long sub_BLInput_overwriteGPCaller(void);
extern double sub_BLInput_overwriteFPCaller(void);
extern unsigned long sub_BLInput_liveGPCaller(void);
extern double sub_BLInput_liveFPCaller(void);
extern unsigned long sub_BLInput_sparseGPCaller(unsigned long, unsigned long, unsigned long, unsigned long);
extern double sub_BLInput_sparseFPCaller(double, double, double, double, double, double, double, double);
extern unsigned long sub_BLInput_mixedCaller(unsigned long, double);
extern unsigned long sub_BLInput_liveMixedCaller(void);
// Both source orders use GP0 and FP0 and reach the same assembler entry.
// Binary register placement alone cannot distinguish the two prototypes.
extern unsigned long sub_BLInput_mixedFPFirst(double, unsigned long) __asm__("_sub_BLInput_mixedCaller");
extern unsigned long sub_BLInput_resultGPCaller(void);
extern double sub_BLInput_resultFPCaller(void);
int main(void) {
    const unsigned long inputs[] = {0, 1, 37, ULONG_MAX, ULONG_MAX-1, 1ul<<63, 123456789};
    for (unsigned i=0;i<sizeof(inputs)/sizeof(inputs[0]);++i)
    {
        assert(sub_BLInput_caller(inputs[i]) == inputs[i]+1);
        assert(sub_BLInput_canonicalGPCaller(inputs[i]) == inputs[i]+1);
        assert(sub_BLInput_sparseGPCaller(5,7,11,inputs[i]) == inputs[i]+1);
    }
    const double fp[] = {-2.25, -0.0, 0.0, 0.5, 1.25, 37.0, 0x1p500};
    for (unsigned i=0;i<sizeof(fp)/sizeof(fp[0]);++i)
    {
        assert(bits(sub_BLInput_fpCaller(fp[i])) == bits(fp[i]*2));
        assert(bits(sub_BLInput_canonicalFPCaller(fp[i])) == bits(fp[i]*2));
        assert(bits(sub_BLInput_sparseFPCaller(0,1,2,3,4,5,6,fp[i])) == bits(fp[i]*2));
        assert(sub_BLInput_mixedCaller(inputs[i],fp[i]) == (inputs[i]^bits(fp[i]*2)));
        assert(sub_BLInput_mixedFPFirst(fp[i],inputs[i]) == (inputs[i]^bits(fp[i]*2)));
    }
    assert(sub_BLInput_zeroGPCaller() == 91);
    assert(bits(sub_BLInput_zeroFPCaller()) == bits(1.0));
    assert(sub_BLInput_overwriteGPCaller() == 74);
    assert(bits(sub_BLInput_overwriteFPCaller()) == bits(6.0));
    assert(sub_BLInput_liveGPCaller() == 74);
    assert(bits(sub_BLInput_liveFPCaller()) == bits(6.0));
    assert(sub_BLInput_liveMixedCaller() == (73ul^bits(6.0)));
    assert(sub_BLInput_resultGPCaller() == 92);
    assert(bits(sub_BLInput_resultFPCaller()) == bits(2.0));
    puts("PASS 65 native GP/FP BL-forwarded input observations");
}
