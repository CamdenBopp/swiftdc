// Untyped Objective-C sends: the selectors are declared here but
// implemented elsewhere, so no signature is available and the explicit
// arguments are laid out by colon position. A double travels in d0, not
// in x2, so the all-integer layout reads the next integer argument (or a
// stale register) as the double and shifts every label after it.
//
// True behaviour: putValue sends put:1.5 at:7, putLoaded put:*p at:7
// (`ldr d0, [x1]`) and putPassed put:x at:7 with x its own double
// parameter (in d0 untouched, so nothing here shows it); takeInts
// sends take:3 and:4 (no floating-point argument); formatLocal sends
// stringWithFormat:@"%f", d with d = 1.5, whose double is a variadic
// argument on the stack though -O0 loads it into d0 first; countAll
// enumerates o, zeroing the enumeration state with 128-bit vector stores
// (`movi v0.2d, #0; stp q0, q0, …`) before countByEnumeratingWithState:
// objects:count:, which takes no floating-point argument; takeAfterBranch
// and takeAfterCall send take:3 and:4 after computing with a double, on
// one path before the send's block or before an intervening call;
// copyThenTake copies a double through d0 (`ldr d0, [x1]; str d0, [x2]`)
// right before take:3 and:4, a temporary and not an argument.
#import <Foundation/Foundation.h>

long gSink;
__attribute__((noinline)) void useDouble(double d) { gSink = (long)d; }

@interface NSObject (Remote)
- (void)put:(double)x at:(long)n;
- (void)take:(long)a and:(long)b;
@end

void putValue(id o) { [o put:1.5 at:7]; }
void putLoaded(id o, double *p) { [o put:*p at:7]; }
void putPassed(id o, double x) { [o put:x at:7]; }
void takeInts(id o) { [o take:3 and:4]; }
void takeAfterBranch(id o, int c, double *p) { if (c) gSink = (long)(*p * 2.0) + 1; [o take:3 and:4]; }
void copyThenTake(id o, double *src, double *dst) { *dst = *src; [o take:3 and:4]; }
void takeAfterCall(id o, double *p) { useDouble(*p * 2.0); [o take:3 and:4]; }
long countAll(id<NSFastEnumeration> o) { long n = 0; for (id x in o) { (void)x; n++; } return n; }
NSString *formatLocal(void) { double d = 1.5; return [NSString stringWithFormat:@"%f", d]; }
