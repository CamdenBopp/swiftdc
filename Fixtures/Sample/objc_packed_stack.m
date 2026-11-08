// Objective-C sends whose explicit arguments spill to the stack. Apple arm64
// packs stack arguments to their own alignment: after six int arguments in
// x2-x7, `g` is at sp+0 and `h` at sp+4, and at -O clang merges the two
// stores into one (`mov x8, #7; movk x8, #8, lsl #32; str x8, [sp]`). That
// slot is not `g`: its low word is g = 7 and its high word h = 8.
//
// `pairs:` passes a 16-byte struct on the stack (two slots, at sp+0 and
// sp+8) before `h` at sp+16: three aligned stores for two arguments, so one
// slot per argument would read g's second word as h.
//
// True behaviour: every send passes a=1 ... f=6, g=7, h=8 (`pairs:` passes
// g = {7, 9}). The typed sends (to self, whose class declares the
// selectors) and the untyped ones (a receiver of unknown class) pass the
// same values.
#import <Foundation/Foundation.h>

struct Pair { long x; long y; };

@interface Packer : NSObject
- (long)ints:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h;
- (long)longs:(long)a b:(long)b c:(long)c d:(long)d e:(long)e f:(long)f g:(long)g h:(long)h;
- (long)mixed:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(long)g h:(int)h;
- (long)pairs:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(struct Pair)g h:(long)h;
- (long)sendInts;
- (long)sendLongs;
- (long)sendMixed;
@end

@implementation Packer
- (long)ints:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h { return g + h; }
- (long)longs:(long)a b:(long)b c:(long)c d:(long)d e:(long)e f:(long)f g:(long)g h:(long)h { return g + h; }
- (long)mixed:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(long)g h:(int)h { return g + h; }
- (long)pairs:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(struct Pair)g h:(long)h { return g.x + h; }
// Typed: g and h packed into one slot (decline both); one slot each.
- (long)sendInts { return [self ints:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]; }
- (long)sendLongs { return [self longs:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]; }
- (long)sendMixed { return [self mixed:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]; }
@end

// Untyped: the receiver's class is unknown, so the sizes are too.
long untypedInts(Packer *p) { return [p ints:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]; }
long untypedLongs(Packer *p) { return [p longs:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]; }
long untypedMixed(Packer *p) { return [p mixed:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8]; }
long untypedPairs(Packer *p) { return [p pairs:1 b:2 c:3 d:4 e:5 f:6 g:(struct Pair){7, 9} h:8]; }
