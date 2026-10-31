// A custom getter, `return [self->_inner value]` (a tail call through
// objc_msgSend), whose extent, with no LC_FUNCTION_STARTS and local symbols
// stripped, runs on through a 6 KB static function, as in Brave's
// BraveSoftwareUpdateAgent. True behaviour: `-value` is custom, so the
// header keeps its line. Classifying by the whole extent, or declining an
// extent past a limit (which the rewriter reads as synthesized), would get
// one of the two accessorextent fixtures wrong.
#import <Foundation/Foundation.h>
#define R4(x) x x x x
#define R64(x) R4(R4(R4(x)))
@interface Inner : NSObject
- (int)value;
@end
@interface Outer : NSObject {
    Inner *_inner;
}
@property (nonatomic, readonly) int value;
@end
@implementation Outer
- (int)value { return [_inner value]; }
@end
__attribute__((noinline, used)) static int bulk(volatile int *p) { R64(R4(*p += 3; *p ^= 5;)) return *p; }
