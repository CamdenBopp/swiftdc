// A float constant inside a float expression (-O2). 100.0 has no fmov
// immediate encoding, so it is built in x8 and moved:
// `mov x8, #0x4059000000000000; fmov d1, x8; fdiv d0, d0, d1`. Nothing in
// the expression said it was a float (CFAbsoluteTimeGetCurrent is a C
// call), so the constant rendered as its bit pattern, an integer divide by
// 4.6e18. `fmul` by the encodable 0.25 is the same shape.
//
// True behaviour: scaledTime calls glVertex2d(t / 100.0, 0.5) and
// quarterTime glVertex2d(t * 0.25, 2.0), t the current absolute time.
#define GL_SILENCE_DEPRECATION
#include <OpenGL/gl.h>
#include <CoreFoundation/CoreFoundation.h>

void scaledTime(void) { glVertex2d(CFAbsoluteTimeGetCurrent() / 100.0, 0.5); }
void quarterTime(void) { glVertex2d(CFAbsoluteTimeGetCurrent() * 0.25, 2.0); }
