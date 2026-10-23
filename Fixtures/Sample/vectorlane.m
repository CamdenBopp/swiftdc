// Scalar views of a zeroed vector register. Clang materialises every
// floating zero with `movi v0.2d, #0`, which writes all 128 bits, and then
// passes the double through `str d0, [sp]`: the low eight-byte lane only.
// True behaviour: each call below passes a single 0.0 (and the int 1).
// Built by `build.sh` at -O0 (the `movi; str d0` shape) and -O2.
#import <Foundation/Foundation.h>
#include <stdio.h>

// `movi v0.2d, #0; str d0, [x8]`: one 8-byte variadic slot holding 0.0.
NSString *laneZeroFormat(void) { return [NSString stringWithFormat:@"%f", 0.0]; }

// `movi v0.2d, #0; str d0, [x9]; str x8, [x9, #8]`: 0.0 in the first slot,
// 1 in the second.
void laneZeroPrintf(void) { printf("%f|%d", 0.0, 1); }
