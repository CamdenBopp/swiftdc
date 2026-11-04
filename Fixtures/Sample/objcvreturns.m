// Objective-C methods whose result is not in x0, so x0 at the `ret` is
// whatever the last call left there (built -O2 and -O0, ARC).
// True behaviour: -a4 is `bl sinkL; fmov d0, #2.5; ret`, so sinkL runs and
// 2.5 comes back in d0. -a1 returns d0 and d1, -rect d0-d3, -size d0 and d1,
// -big stores through x8. Each runs its sink first. -tailD and -tailL run
// sinkL, then tail-branch to a callee taking no argument, so x0 at the `b`
// is stale there too. -keep is the x0 control: it returns 3.
// -d is one `bl`, then `fadd d0, d0, d0`: one send, used twice. -f is the
// same in s0, and -sum: uses one send twice around a call.
#import <Foundation/Foundation.h>
typedef struct { double x, y; } V2;
typedef struct { long a, b, c, d, e; } Big;
volatile long gl;
volatile double gd;
__attribute__((noinline)) void sinkL(long x) { gl = x; }
__attribute__((noinline)) void sinkD(double x) { gd = x; }
__attribute__((noinline)) double mkD(void) { return gd; }
__attribute__((noinline)) long mkL(void) { return gl; }

@interface VBase : NSObject
- (V2)v2:(long)k;
- (double)d;
- (float)f;
@end
@implementation VBase
- (V2)v2:(long)k { V2 v = {k, k}; return v; }
- (double)d { return 1.5; }
- (float)f { return 1.5f; }
@end

@interface VRets : VBase
@end
@implementation VRets
- (double)a4 { sinkL(1); return 2.5; }
- (V2)a1 { sinkL(2); V2 v = {1, 2}; return v; }
- (V2)v2:(long)k { V2 v = [super v2:k]; sinkD(v.y); return v; }
- (float)a5 { sinkL(3); return 1.5f; }
- (CGRect)rect { sinkL(4); return CGRectMake(1, 2, 3, 4); }
- (CGSize)size { sinkL(5); return CGSizeMake(1, 2); }
- (Big)big { sinkL(6); Big b = {1, 2, 3, 4, 5}; return b; }
- (double)tailD { sinkL(7); return mkD(); }
- (long)tailL { sinkL(8); return mkL(); }
- (long)keep { sinkL(9); return 3; }
- (double)d { return [super d] * 2; }
- (float)f { return [super f] * 2; }
- (double)sum:(double)x { double a = [self d]; sinkD(a); return a + a + x; }
@end
