// Imported void function: no input words. Its body lives in another image,
// so a caller's register-read summary can only bound possible forwarded reads.
static unsigned long effects;
void body_arity_opaque_effect(void) { ++effects; }
unsigned long body_arity_effect_count(void) { return effects; }
