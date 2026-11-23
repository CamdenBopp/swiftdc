// LEVELS: O0 O1 O2 Os
// Struct returns from Objective-C methods on arm64.
//
// arm64 has no objc_msgSend_stret: every send goes through objc_msgSend.
// A homogeneous aggregate of up to four doubles (CGRect) returns in
// d0..d3. A 16-byte integer struct (NSRange) returns in x0,x1. A larger
// non-HFA struct (SRBig, 24 bytes) returns indirectly: the caller passes
// the result buffer in x8, which is NOT an argument, and self/_cmd stay in
// x0/x1.
// TRUE behaviours:
//   -[SRShape frame]        returns {x, y, w, h} in d0..d3
//   -[SRShape span]         returns {loc, len} in x0, x1
//   -[SRShape big]          writes {a, b, c} through x8
//   readBig(s)              sends `big` to s; x8 is the caller's buffer,
//                           so `big` takes no argument
//   areaOf(s)               sends `frame` and multiplies w * h
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef struct { long a; long b; long c; } SRBig;

@interface SRShape : NSObject
@property CGFloat x, y, w, h;
@property NSUInteger loc, len;
- (CGRect)frame;
- (NSRange)span;
- (SRBig)big;
@end

@implementation SRShape
- (CGRect)frame { return CGRectMake(_x, _y, _w, _h); }
- (NSRange)span { return NSMakeRange(_loc, _len); }
- (SRBig)big { SRBig r = { (long)_loc, (long)_len, 3 }; return r; }
@end

// EXPECT structured * readBig :: big]
// FORBID structured * readBig :: re:\bbig:
long readBig(SRShape *s) {
    SRBig r = [s big];
    return r.a + r.b + r.c;
}

// EXPECT structured * areaOf :: frame]
// FORBID structured * areaOf :: re:\bframe:
double areaOf(SRShape *s) {
    CGRect r = [s frame];
    return r.size.width * r.size.height;
}

// EXPECT structured * spanEnd :: span]
// FORBID structured * spanEnd :: re:\bspan:
NSUInteger spanEnd(SRShape *s) {
    NSRange r = [s span];
    return r.location + r.length;
}

// -[SRShape big] at -O1 and up copies _loc and _len with one 128-bit
// load and store (ldur q0, [x0, #0x28]; str q0, [x8]). The stored value
// is both fields, so naming it self->_loc alone is wrong.
// FORBID structured * big] :: re:mem128\[&result\] = self->_loc\s*$
// FORBID structured * big] :: re:\[&result\] = self->_len\s*\n\s*mem64\[&result \+ 0x8\]
//
// A send to a statically nil receiver of a struct returned through x8:
// ARC code zeroes the result on the nil path; -O0 keeps the send behind
// a nil test, -O1 and up fold the whole function to `return 0`.
// TRUE: bigOfNil returns 0.
// EXPECT structured O0 bigOfNil :: big]
long bigOfNil(void) {
    SRShape *s = nil;
    return [s big].c;
}
