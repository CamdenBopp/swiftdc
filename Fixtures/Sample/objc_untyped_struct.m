// Objective-C sends with no signature for their receiver, of selectors that
// an implementation in the image takes a struct for. With no signature the
// explicit arguments are laid out one x register each, from x2, by colon
// position. A struct breaks that:
//
// - `span:count:` passes the NSRange in x2-x3 and c in x4, so x2 and x3 are
//   the range's location and length, not `span:` and `count:`.
// - `place:flags:` passes the CGPoint in d0-d1 and f in x2, so x2 is
//   `flags:`, not `place:`. The point is passed through from the caller's
//   own d0-d1, so nothing is written to a v register at the send.
// - `count:span:` passes c in x2 and the NSRange in x3-x4. An argument's
//   register depends only on the arguments before it, so `count:` is still
//   x2; only `span:` is lost.
// - `pair:with:tail:` has two implementations: SDUntypedStructBase passes
//   a in x2 and the NSRange in x3-x4, SDUntypedStructOther the NSRange in
//   x2-x3. With no receiver class either may be the callee, so not even
//   `pair:` is where the layout reads it.
//
// The receivers have no signature: `id` (`sendSpanTo:`, `sendPlaceTo:at:`),
// self of a class that inherits the method from an in-image superclass
// without declaring it (`SDUntypedStructLeaf`'s `sendInheritedSpan`), and
// super from an override that forwards its own arguments (`span:count:` in
// `SDUntypedStructChild`). `tally:` takes only a long, so
// its untyped send `[u tally:5]` keeps its colon layout (the control).
//
// True behaviour: each send passes the literal values written below; a
// struct argument has no single value to render, so the arguments of a send
// that cannot be laid out are `?`.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface SDUntypedStructBase : NSObject {
    long _count;
    long _flags;
}
- (void)span:(NSRange)r count:(long)c;
- (void)place:(CGPoint)p flags:(long)f;
- (void)tally:(long)n;
- (void)count:(long)c span:(NSRange)r;
- (void)pair:(long)a with:(NSRange)r tail:(long)t;
@end

@implementation SDUntypedStructBase
- (void)span:(NSRange)r count:(long)c { _count = c; }
- (void)place:(CGPoint)p flags:(long)f { _flags = f; }
- (void)tally:(long)n { _count = n; }
- (void)count:(long)c span:(NSRange)r { _count = c; }
- (void)pair:(long)a with:(NSRange)r tail:(long)t { _count = a + t; }
@end

@interface SDUntypedStructOther : NSObject
- (void)pair:(NSRange)r with:(long)a tail:(long)t;
@end

@implementation SDUntypedStructOther
- (void)pair:(NSRange)r with:(long)a tail:(long)t {}
@end

@interface SDUntypedStructChild : SDUntypedStructBase
- (void)sendSpanTo:(id)u;
- (void)sendPlaceTo:(id)u at:(CGPoint)p;
- (void)sendTallyTo:(id)u;
- (void)sendCountTo:(id)u;
- (void)sendPairTo:(SDUntypedStructBase *)u;
@end

@implementation SDUntypedStructChild
- (void)span:(NSRange)r count:(long)c { [super span:r count:c]; }
- (void)sendSpanTo:(id)u { [u span:NSMakeRange(3, 4) count:5]; }
- (void)sendPlaceTo:(id)u at:(CGPoint)p { [u place:p flags:7]; }
- (void)sendTallyTo:(id)u { [u tally:5]; }
- (void)sendCountTo:(id)u { [u count:5 span:NSMakeRange(3, 4)]; }
- (void)sendPairTo:(SDUntypedStructBase *)u { [u pair:1 with:NSMakeRange(3, 4) tail:5]; }
@end

@interface SDUntypedStructLeaf : SDUntypedStructBase
- (void)sendInheritedSpan;
@end

@implementation SDUntypedStructLeaf
- (void)sendInheritedSpan { [self span:NSMakeRange(3, 4) count:5]; }
@end
