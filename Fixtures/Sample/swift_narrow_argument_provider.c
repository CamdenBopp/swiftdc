#include <stdint.h>
static volatile uint64_t calls;
uint64_t argument_opaque_word(uint64_t value) { calls++; return value ^ UINT64_C(0x9f123456789abcde); }
void argument_opaque_reset(void) { calls = 0; }
uint64_t argument_opaque_count(void) { return calls; }
