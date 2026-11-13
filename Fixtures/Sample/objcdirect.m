// Direct Objective-C methods (`__attribute__((objc_direct))`) are called by
// their symbol and take no `_cmd`: self in x0, the first keyword in x1.
// Their IMPs are in no method list. Read like ordinary methods, a call
// `[box mix:5 with:9]` (`mov w1, #5; mov w2, #9; bl -[DMBox mix:with:]`)
// rendered `[? mix:9 with:?]`, and the body named b `arg0`.
//
// True behaviour: mix:with: returns v * a - b, recursing with a - 100 and
// b + 1 while a > 100; extra: (a category's direct method) returns v + x;
// useTwo sends mix:5 with:9; useVar sends mix:a with:b; useExtra sends
// extra:7.
#import <Foundation/Foundation.h>

@interface DMBox : NSObject { int _v; }
- (int)mix:(int)a with:(int)b __attribute__((objc_direct));
@end
@interface DMBox (Extra)
- (int)extra:(int)x __attribute__((objc_direct));
@end

@implementation DMBox
- (int)mix:(int)a with:(int)b {
    if (a > 100) return [self mix:a - 100 with:b + 1];
    return _v * a - b;
}
@end
@implementation DMBox (Extra)
- (int)extra:(int)x { return _v + x; }
@end

int useTwo(DMBox *box) { return [box mix:5 with:9]; }
int useVar(DMBox *box, int a, int b) { return [box mix:a with:b]; }
int useExtra(DMBox *box) { return [box extra:7]; }
