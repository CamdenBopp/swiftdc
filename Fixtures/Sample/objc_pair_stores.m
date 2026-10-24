// Paired stores into an object's ivars that cover more than one ivar. The
// ivars sit at _e 8..20 (a 12-byte struct), _f 20..24, _c 24..32 and
// _d 32..40.
//
// - setBoth:d: is `stp x2, x3, [x0, #0x18]`: x2 fills _c and x3 fills _d,
//   a tuple of two whole ivars (the control).
// - packC: is `stp x2, x9, [x0, #0x18]` with x9 never written: _c takes a,
//   and _d takes whatever x9 held.
// - packE:f: is `stp x2, x3, [x0, #0x8]`: the store covers _e and _f
//   exactly, but x2 is only the first 8 bytes of _e, and x3 is _e's last
//   4 bytes and then _f.
//
// - SDPairParts's setTail:b: is clang's own `stp w2, w3, [x0, #0x10]` over
//   _a[2] (the last 4 bytes of the 12-byte _a at 8..20) and _b at 20..24:
//   the store covers no whole field first, so it named nothing.
//
// The inline stores fix the registers; nothing else in the methods runs.
// True behaviour: setBoth:d: sets _c = x and _d = y; packC: sets _c = a and
// _d to an unknown value; packE:f: sets _e's first 8 bytes to a, its last
// 4 to the low half of b, and _f to the high half of b; setTail:b: sets
// _a[2] = x and _b = y.
#import <Foundation/Foundation.h>

typedef struct { int x, y, z; } SDTriple;

@interface SDPairStores : NSObject {
@public
    SDTriple _e;
    int _f;
    long _c;
    long _d;
}
- (void)setBoth:(long)x d:(long)y;
- (void)packC:(long)a;
- (void)packE:(long)a f:(long)b;
@end

@implementation SDPairStores
- (void)setBoth:(long)x d:(long)y { _c = x; _d = y; }
- (void)packC:(long)a {
    __asm__ volatile("stp %0, x9, [%1, #0x18]" :: "r"(a), "r"(self) : "x9", "memory");
}
- (void)packE:(long)a f:(long)b {
    __asm__ volatile("stp %0, %1, [%2, #0x8]" :: "r"(a), "r"(b), "r"(self) : "memory");
}
@end

@interface SDPairParts : NSObject {
@public
    int _a[3];
    int _b;
}
- (void)setTail:(int)x b:(int)y;
@end

@implementation SDPairParts
- (void)setTail:(int)x b:(int)y { _a[2] = x; _b = y; }
@end

// A struct of two words returned from one ivar: `ldp x0, x1, [x0, #0x8];
// ret` returns _range whole. rangeHead returns _range's first word with
// another ivar's, and rangeShifted _range's second word with another's.
// wordOfRange returns one word, _range.location, though its inline paired
// load leaves _range.length in x1. True behaviour: range returns _range;
// rangeHead returns {_range.location, _other}; rangeShifted
// {_range.length, _other}; wordOfRange _range.location.
@interface SDPairReturns : NSObject {
@public
    NSRange _range;
    NSUInteger _other;
}
- (NSRange)range;
- (NSRange)rangeHead;
- (NSRange)rangeShifted;
- (NSUInteger)wordOfRange;
@end

@implementation SDPairReturns
- (NSRange)range { return _range; }
- (NSRange)rangeHead { return NSMakeRange(_range.location, _other); }
- (NSRange)rangeShifted { return NSMakeRange(_range.length, _other); }
- (NSUInteger)wordOfRange {
    NSUInteger word;
    __asm__ volatile("ldp %0, x1, [%1, #0x8]" : "=r"(word) : "r"(self) : "x1");
    return word;
}
@end

// Eight ints zeroed at once: clang stores one zeroed q0 twice (`movi
// v0.2d, #0; stur q0, [x0, #0x18]; stur q0, [x0, #0x8]`), each store over
// four ints. After the first, q0 holds what _v.._s hold, all sixteen
// bytes of them. True behaviour: every ivar becomes 0.
@interface SDPairZeros : NSObject {
@public
    int _w, _x, _y, _z, _v, _u, _t, _s;
}
- (void)clear;
@end

@implementation SDPairZeros
- (void)clear { _w = _x = _y = _z = _v = _u = _t = _s = 0; }
@end
