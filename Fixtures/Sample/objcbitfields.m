// Three bitfields share one byte, so their ivars share one offset. `middle` is
// `ldrb; ubfx #1`: it reads `_b`, and only the bit says so. `_after` has an
// offset to itself and keeps its name.
#import <Foundation/Foundation.h>

@interface BitFlags : NSObject {
    unsigned _a : 1;
    unsigned _b : 1;
    unsigned _c : 1;
    long _after;
}
- (BOOL)middle;
- (long)after;
@end

@implementation BitFlags
- (BOOL)middle { return _b; }
- (long)after { return _after; }
@end
