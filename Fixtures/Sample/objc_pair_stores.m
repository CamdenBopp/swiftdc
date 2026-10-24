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

// A value forwarded from a store into part of an ivar, stored again by a
// pair store over two ivars (-O2): `str x2, [x0, #0x8]` puts v in _a.x,
// the first 8 bytes of the 24-byte _a, and `stp x2, x2, [x0, #0x18]`
// writes _a.z and _b. After the first store x2 holds _a's first eight
// bytes, not all of _a. True behaviour: _a.x, _a.z and _b become v.
typedef struct { long x, y, z; } SDTripleLong;
@interface SDTailForward : NSObject {
@public
    SDTripleLong _a;
    long _b;
}
- (void)tailForward:(long)v;
@end

@implementation SDTailForward
- (void)tailForward:(long)v { _a.x = v; _a.z = v; _b = v; }
@end

// Values forwarded from stores into parts of an ivar, stored again into
// whole ivars (-O2). spreadParts:and: is `stp x2, x3, [x0, #0x8]` over the
// 16-byte struct _s, then `stp x2, x3, [x0, #0x18]` over _t and _u: x2 and
// x3 then hold _s's two halves, not _s, and the second store rendered
// `(self->_t, self->_u) = (self->_s, self->_s[8...])`. tailInt: is the
// four-byte version of SDTailForward over a 12-byte struct of ints, whose
// masked value rendered `(self->_a & 0xffffffff)`. True behaviour:
// spreadParts:and: sets _s = {v, w}, _t = v and _u = w; tailInt: sets
// _a.x, _a.z and _b to v.
typedef struct { long x, y; } SDWidePair;
typedef struct { int x, y, z; } SDIntTriple;
@interface SDForwardParts : NSObject {
@public
    SDWidePair _s;
    long _t, _u;
}
- (void)spreadParts:(long)v and:(long)w;
@end

@implementation SDForwardParts
- (void)spreadParts:(long)v and:(long)w { _s.x = v; _s.y = w; _t = v; _u = w; }
@end

@interface SDTailInt : NSObject {
@public
    SDIntTriple _a;
    int _b;
}
- (void)tailInt:(int)v;
@end

@implementation SDTailInt
- (void)tailInt:(int)v { _a.x = v; _a.z = v; _b = v; }
@end

// One vector register stored over the end of one ivar and the start of
// the next (-O2): `dup v0.2d, x2; stur q0, [x0, #0x18]; stur q0, [x0, #0x8]`
// writes _s.y and _t, then _a and _s.x. Neither store covers a field
// first, so neither printed a statement. True behaviour: _a, _s.x, _s.y
// and _t all become v.
@interface SDStraddle : NSObject {
@public
    long _a;
    SDWidePair _s;
    long _t;
}
- (void)fill:(long)v;
@end

@implementation SDStraddle
- (void)fill:(long)v { _a = v; _s.x = v; _s.y = v; _t = v; }
@end
