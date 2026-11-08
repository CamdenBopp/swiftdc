// A synthesized setter whose extent, with no LC_FUNCTION_STARTS and local
// symbols stripped, runs on through a 6 KB static function to the end of
// __text, as accessors in Electron Framework run to the next IMP. True
// behaviour: `-setValue:` is synthesized (`str w2, [x0, #8]; ret`), so its
// line is implied by the @property and dropped from the header.
#import <Foundation/Foundation.h>
#define R4(x) x x x x
#define R64(x) R4(R4(R4(x)))
@interface Box : NSObject
@property (nonatomic) int value;
@end
@implementation Box
@end
__attribute__((noinline, used)) static int bulk(volatile int *p) { R64(R4(*p += 3; *p ^= 5;)) return *p; }
