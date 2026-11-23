// LEVELS: O0 O1 O2 Os
// Direct methods: __attribute__((objc_direct)).
//
// A direct method has no selector in the method list and is called as a
// plain C function -[DMBox secret] (bl to the symbol), not through
// objc_msgSend. The caller still passes self in x0; the callee itself
// checks self for nil (direct methods keep nil-messaging semantics),
// and _cmd is NOT passed: x1 holds the first explicit argument.
// TRUE behaviours:
//   -[DMBox secret]          returns _v
//   -[DMBox addTo:]          returns _v + arg (arg in x1, not x2)
//   useDirect(b)             calls -[DMBox addTo:] with 5 as its argument
//                            (inlined at -O1 and up: 2 * _v + 5 when b
//                            is non-nil, else 0)
//   useTwo(b)                calls -[DMBox mix:with:] with a=5 in x1 and
//                            b=9 in x2; a msgSend-style mapping that reads
//                            the first keyword from x2 would show mix:9
#import <Foundation/Foundation.h>

@interface DMBox : NSObject { int _v; }
- (int)secret __attribute__((objc_direct));
- (int)addTo:(int)arg __attribute__((objc_direct));
- (int)mix:(int)a with:(int)b __attribute__((objc_direct));
@end

@implementation DMBox
- (int)secret { return _v; }
- (int)addTo:(int)arg { return _v + arg; }
// Recursive so the inliner keeps a real call at -O1 and up (objc_direct
// methods ignore noinline).
- (int)mix:(int)a with:(int)b {
    if (a > 100) return [self mix:a - 100 with:b + 1];
    return _v * a - b;
}
@end

// The direct methods are local symbols, named in every unstripped build.
// FORBID listing * * :: re:(?m)^sub_[0-9a-f]+:$
// EXPECT structured O0 useDirect :: addTo:5
// FORBID structured * useDirect :: objc_msgSend
// FORBID structured * useDirect :: re:addTo:[^\n]*\?\s*,\s*5
int useDirect(DMBox *b) {
    return [b addTo:5] + [b secret];
}

// Constant arguments fold the call away at -O1 and up.
// EXPECT structured O0 useTwo :: mix:5 with:9
// FORBID structured * useTwo :: re:mix:(?!\?|5\b)\S
// FORBID structured * useTwo :: re:with:(?!\?|9\b)\S
int useTwo(DMBox *b) {
    return [b mix:5 with:9];
}

// useVar's own x and y arrive in w1 and w2, exactly where mix:with: wants
// a and b, so -O1 and up emit no moves. TRUE: [b mix:x with:y], that is
// mix:arg1 with:arg2 (arg0 is b).
// -O2 and -Os inline one level of the recursion.
// EXPECT structured O1 useVar :: mix:arg1 with:arg2
// FORBID structured * useVar :: re:mix:[^\n]*arg2[^\n]*with:
// FORBID structured * useVar :: re:mix:\(?arg2
int useVar(DMBox *b, int x, int y) {
    return [b mix:x with:y];
}
