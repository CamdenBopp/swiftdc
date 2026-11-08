// Floating variadic arguments. On Apple arm64 every variadic argument is one
// eight-byte stack slot, and a double travels as its bits, so a slot the
// format names `%f` holds a double: `1.5` is the slot 0x3ff8000000000000.
// True behaviour is each call's source literal. Built by `build.sh` at -O0
// (snprintf and sprintf lower to __snprintf_chk and __sprintf_chk there)
// and -O2 (literal-pool doubles, merged `stp` stores).
#import <Foundation/Foundation.h>
#include <stdio.h>
#pragma clang diagnostic ignored "-Wformat"

NSString *vfDouble(void) { return [NSString stringWithFormat:@"%f", 1.5]; }
// `%ld` and `%@` are not floating; 2.25 and 0.1 are.
NSString *vfMixed(long n, id o) { return [NSString stringWithFormat:@"%ld %f %@ %g", n, 2.25, o, 0.1]; }
NSString *vfBig(void) { return [NSString stringWithFormat:@"%f %f %f", 1e300, 123456789.125, 1e-7]; }
// Zero and negative zero are doubles; an infinity, a NaN and a subnormal
// keep their bits.
NSString *vfSpecials(void) { return [NSString stringWithFormat:@"%f %f %f %f %f", 0.0, -0.0, __builtin_inf(), __builtin_nan(""), 4.9e-324]; }
// The format and the argument disagree: `%f` of the int 3 and `%d` of 1.5
// render the bits they pass, not a double.
NSString *vfIntAsF(void) { return [NSString stringWithFormat:@"%f", 3]; }
NSString *vfDblAsD(void) { return [NSString stringWithFormat:@"%d", 1.5]; }
// `L` and `l` with a floating conversion are still a double on Apple arm64.
void vfMany(void) { printf("%Lf %lf %e %g %a\n", 1.5L, 2.5, 3.5, 4.5, 0.5); }
void vfSnprintf(char *b) { snprintf(b, 64, "%d %f %s", 3, 2.5, "x"); }
void vfSprintf(char *b) { sprintf(b, "%f", 2.5); }
