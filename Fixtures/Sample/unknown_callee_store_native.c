// Native execution fixes the observable value independently of analysis:
// an untracked pointer writes context[2]=99; a private pointer leaves it 7.
#include <assert.h>
#include <limits.h>
#include <stdio.h>
extern unsigned long unknown_store_alias_oracle(unsigned long);
extern unsigned long unknown_store_private_oracle(unsigned long);
extern unsigned long unknown_store_crossing_oracle(unsigned long);
extern void unknown_store_buffer_oracle(unsigned long *);
extern unsigned long unknown_store_frame_word(unsigned long) __asm__("_$s12UnknownStore9frameWordyS2uF");
int main(void) {
 const unsigned long guards[]={0,1,37,ULONG_MAX,ULONG_MAX-1,1ul<<63,123456789};
 for(unsigned i=0;i<sizeof(guards)/sizeof(guards[0]);++i) {
  assert(unknown_store_alias_oracle(guards[i])==99);
  assert(unknown_store_private_oracle(guards[i])==7);
  assert(unknown_store_crossing_oracle(guards[i])==99);
  unsigned long result[]={guards[i],7,7,7,7,7,~guards[i]};
  unknown_store_buffer_oracle(&result[1]);
  assert(result[0]==guards[i] && result[1]==99 && result[6]==~guards[i]);
  for(unsigned j=2;j<=5;++j) assert(result[j]==7);
  assert(unknown_store_frame_word(guards[i])==99);
 }
 puts("PASS 35 native unknown-store context/buffer/frame observations");
}
