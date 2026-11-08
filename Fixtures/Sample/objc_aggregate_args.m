// Objective-C sends to self whose signatures pass a struct by value. Apple
// arm64 lays them out by kind:
//
// - A homogeneous floating-point aggregate (HFA: one to four members of one
//   floating type, nested structs flattened) takes one v register per member
//   while enough remain. `place:` passes p in d0-d1, f in x2 and t in d2;
//   `frame:` passes the CGRect in d0-d3 and n in x2.
// - An HFA that does not fit goes on the stack and closes the v bank: in
//   `a:…rect:after:n:`, a-f fill d0-d5, the CGRect needs four and gets the
//   stack at sp+0..32, `after` follows it at sp+32 (not d6), and n is in x2.
// - Any other struct of 16 bytes or less takes one or two x registers:
//   `span:count:` passes the NSRange in x2-x3 and c in x4. One that does not
//   fit goes on the stack and closes the x bank: in `a:…range:tail:`, a-e fill
//   x2-x6, the NSRange gets sp+0..16, x7 stays unused, and tail is at sp+16.
// - A larger struct is passed as the address of a copy, in one x register:
//   `big:n:` passes that address in x2 and n in x3.
// - A struct on the stack is a stack argument of its own. In
//   `v0:…x7:count:one:` the banks are full, count is at sp+0 and the
//   one-float HFA at sp+4, and at -O clang merges their stores into one
//   eight-byte store at sp+0 (`mov x8, #7; movk x8, #0x3fc0, lsl #48`).
//   That store is count and one together, not count.
//
// True behaviour: each send passes the literal values written below, and the
// struct argument itself (several registers, or an address) has no single
// value to render.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

struct SDBig { long a; long b; long c; };
struct SDOne { float v; };

@interface SDAggregateProbe : NSObject {
    long _flags;
    double _stamp;
    long _tag;
    long _count;
}
- (void)place:(CGPoint)p flags:(long)f stamp:(double)t;
- (void)frame:(CGRect)r tag:(long)n;
- (void)a:(double)a b:(double)b c:(double)c d:(double)d e:(double)e f:(double)f
     rect:(CGRect)r after:(double)after n:(long)n;
- (void)span:(NSRange)r count:(long)c;
- (void)a:(long)a b:(long)b c:(long)c d:(long)d e:(long)e range:(NSRange)r tail:(long)tail;
- (void)big:(struct SDBig)b n:(long)n;
- (void)v0:(double)a v1:(double)b v2:(double)c v3:(double)d v4:(double)e v5:(double)f v6:(double)g v7:(double)h
        x2:(long)i x3:(long)j x4:(long)k x5:(long)l x6:(long)m x7:(long)n count:(int)count one:(struct SDOne)one;
- (void)sendPlace;
- (void)sendFrame;
- (void)sendSpilledRect;
- (void)sendSpan;
- (void)sendSpilledRange;
- (void)sendBig;
- (void)sendOne;
@end

@implementation SDAggregateProbe
- (void)place:(CGPoint)p flags:(long)f stamp:(double)t { _flags = f; _stamp = t; }
- (void)frame:(CGRect)r tag:(long)n { _tag = n; }
- (void)a:(double)a b:(double)b c:(double)c d:(double)d e:(double)e f:(double)f
     rect:(CGRect)r after:(double)after n:(long)n { _stamp = after; _tag = n; }
- (void)span:(NSRange)r count:(long)c { _count = c; }
- (void)a:(long)a b:(long)b c:(long)c d:(long)d e:(long)e range:(NSRange)r tail:(long)tail { _tag = tail; }
- (void)big:(struct SDBig)b n:(long)n { _count = n; }
- (void)v0:(double)a v1:(double)b v2:(double)c v3:(double)d v4:(double)e v5:(double)f v6:(double)g v7:(double)h
        x2:(long)i x3:(long)j x4:(long)k x5:(long)l x6:(long)m x7:(long)n count:(int)count one:(struct SDOne)one {
    _count = count;
}
- (void)sendPlace { [self place:CGPointMake(1.5, 2.25) flags:7 stamp:2.5]; }
- (void)sendFrame { [self frame:CGRectMake(1.5, 2.5, 3.5, 4.5) tag:9]; }
- (void)sendSpilledRect {
    [self a:1.5 b:2.5 c:3.5 d:4.5 e:5.5 f:6.5 rect:CGRectMake(7.5, 8.5, 9.5, 10.5) after:11.5 n:12];
}
- (void)sendSpan { [self span:NSMakeRange(3, 4) count:5]; }
- (void)sendSpilledRange { [self a:1 b:2 c:3 d:4 e:5 range:NSMakeRange(6, 7) tail:8]; }
- (void)sendBig { [self big:(struct SDBig){1, 2, 3} n:4]; }
- (void)sendOne {
    [self v0:1.5 v1:2.5 v2:3.5 v3:4.5 v4:5.5 v5:6.5 v6:7.5 v7:8.5
          x2:1 x3:2 x4:3 x5:4 x6:5 x7:6 count:7 one:(struct SDOne){1.5f}];
}
@end
