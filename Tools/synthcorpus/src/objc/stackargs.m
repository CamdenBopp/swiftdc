// LEVELS: O0 O1 O2 Os
// Objective-C sends with more explicit arguments than registers.
//
// objc_msgSend takes self in x0 and _cmd in x1, so only six integer
// arguments fit (x2..x7). On Darwin arm64 the rest go on the stack at
// their natural size and alignment (not 8-byte slots): in
// -[SCStack sumA:b:c:d:e:f:g:h:] a..f are in x2..x7, g at [sp] and h at
// [sp, #4] as 32-bit ints. TRUE: callNine sends sumA:b:c:d:e:f:g:h: to
// the receiver with 1..8 in order, so the result is 36.
//
// Doubles take v0..v7 independently of the integer registers: in
// mixA:x:b:y:c:z: the ints a,b,c are x2,x3,x4 and the doubles x,y,z are
// d0,d1,d2. TRUE: callMixed passes a=10 x=1.5 b=20 y=2.5 c=30 z=3.5.
//
// A 16-byte struct of two longs (SCPair) takes two integer registers when
// two are left. In pairTail:::: the four longs fill x2..x5, so the pair
// goes in x6,x7 (lo, hi). In pairSpill:: the six longs fill x2..x7 and
// the pair goes entirely on the stack at [sp], [sp, #8] (a struct is not
// split between registers and stack). TRUE: callSpill passes the pair
// {7, 8} on the stack.
#import <Foundation/Foundation.h>

typedef struct { long lo; long hi; } SCPair;

@interface SCStack : NSObject
- (int)sumA:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h;
- (double)mixA:(int)a x:(double)x b:(int)b y:(double)y c:(int)c z:(double)z;
- (long)pairTail:(long)a b:(long)b c:(long)c d:(long)d p:(SCPair)p;
- (long)pairSpill:(long)a b:(long)b c:(long)c d:(long)d e:(long)e f:(long)f p:(SCPair)p;
@end

@implementation SCStack
- (int)sumA:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h {
    return a + b + c + d + e + f + g + h;
}
- (double)mixA:(int)a x:(double)x b:(int)b y:(double)y c:(int)c z:(double)z {
    return a * x + b * y + c * z;
}
- (long)pairTail:(long)a b:(long)b c:(long)c d:(long)d p:(SCPair)p {
    return a + b + c + d + p.lo * p.hi;
}
- (long)pairSpill:(long)a b:(long)b c:(long)c d:(long)d e:(long)e f:(long)f p:(SCPair)p {
    return a + b + c + d + e + f + p.lo - p.hi;
}
@end

// g and h are the two 32-bit halves of the one 64-bit store at [sp]
// (mov x8, #7; movk x8, #8, lsl #32; str x8, [sp]).
// EXPECT structured * callNine :: sumA:1 b:2 c:3 d:4 e:5 f:6
// EXPECT structured * callNine :: g:7 h:8
// FORBID structured * callNine :: re:\bg:(?!\?|7\b)\S
// FORBID structured * callNine :: re:\bh:(?!\?|8\b)\S
// The listing's argument list must not end at x7 as if complete: g and h
// are on the stack, so the list needs them or a trailing `…`.
// FORBID listing * callNine :: re:sumA:b:c:d:e:f:g:h:\s+args\([^)\n]*\b6\)
int callNine(SCStack *s) {
    return [s sumA:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8];
}

// EXPECT structured * callMixed :: mixA:10
// EXPECT structured * callMixed :: b:20
// EXPECT structured * callMixed :: c:30
// FORBID structured * callMixed :: re:\bx:(?!\?|1\.5\b)\S
// FORBID structured * callMixed :: re:\bb:(?!\?|20\b)\S
// FORBID structured * callMixed :: re:\by:(?!\?|2\.5\b)\S
// FORBID structured * callMixed :: re:\bz:(?!\?|3\.5\b)\S
double callMixed(SCStack *s) {
    return [s mixA:10 x:1.5 b:20 y:2.5 c:30 z:3.5];
}

// EXPECT structured * callTail :: pairTail:1 b:2 c:3 d:4 p:
long callTail(SCStack *s) {
    SCPair p = { 5, 6 };
    return [s pairTail:1 b:2 c:3 d:4 p:p];
}

// EXPECT structured * callSpill :: pairSpill:1 b:2 c:3 d:4 e:5 f:6 p:
// FORBID structured * callSpill :: re:\bp:(?!\?|\{\s*7,\s*8\s*\})\S
// FORBID listing * callSpill :: re:pairSpill:b:c:d:e:f:p:\s+args\([^)\n]*\b6\)
long callSpill(SCStack *s) {
    SCPair p = { 7, 8 };
    return [s pairSpill:1 b:2 c:3 d:4 e:5 f:6 p:p];
}
