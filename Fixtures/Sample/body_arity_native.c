// Native C prototypes independently fix the source argument counts. The
// assembly targets preserve ABI registers and call the opaque void import once.
#include <assert.h>
#include <limits.h>
#include <stdio.h>
extern unsigned long body_arity_call_one(unsigned long);
extern unsigned long body_arity_call_zero(void);
extern unsigned long body_arity_call_third(unsigned long);
extern double body_arity_call_float(void);
extern double body_arity_call_mixed(void);
extern unsigned long body_arity_call_closed_one(void);
extern double body_arity_call_closed_float(void);
extern unsigned long body_arity_call_alias(void);
extern unsigned long body_arity_call_framed_one(void);
extern double body_arity_call_framed_float(void);
extern double body_arity_float(double);
extern double body_arity_mixed(unsigned long, double);
extern unsigned long body_arity_effect_count(void);
int main(void) {
 const unsigned long words[]={0,1,37,ULONG_MAX,ULONG_MAX-8,1ul<<63,123456789};
 const double fp[]={-2.5,0,1.25,37.5,0.125,-1.0,1024.0};
 unsigned observations=0;
 for(unsigned i=0;i<7;++i) {
  unsigned long before=body_arity_effect_count();
  assert(body_arity_call_one(words[i])==words[i]+9); ++observations;
  assert(body_arity_call_zero()==9); ++observations;
  assert(body_arity_call_third(words[i])==words[i]+9); ++observations;
  assert(body_arity_call_float()==2.0); ++observations;
  assert(body_arity_call_mixed()==12.0); ++observations;
  assert(body_arity_float(fp[i])==fp[i]+1.0); ++observations;
  assert(body_arity_mixed(words[i],fp[i])==(double)words[i]+fp[i]); ++observations;
  assert(body_arity_effect_count()==before+7);
  assert(body_arity_call_closed_one()==20); ++observations;
  assert(body_arity_call_closed_float()==2.0); ++observations;
  assert(body_arity_call_alias()==20); ++observations;
  assert(body_arity_call_framed_one()==20); ++observations;
  assert(body_arity_call_framed_float()==2.0); ++observations;
  assert(body_arity_effect_count()==before+7);
 }
 assert(observations==84 && body_arity_effect_count()==49);
 puts("PASS 84 native body-arity observations and 49 opaque effects");
}
