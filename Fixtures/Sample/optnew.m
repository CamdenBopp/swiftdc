// `[C new]` compiles to objc_opt_new(C). The runtime sends +new when the
// class overrides it, so the call is `new`, not `alloc` then `init`:
//   Counted overrides +new to count instances; make() is [Counted new].
//   makeInit() is [[Counted alloc] init] (objc_alloc_init): the control.
#import <Foundation/Foundation.h>
@interface Counted : NSObject
@end
static long made;
@implementation Counted
+ (instancetype)new { made += 1; return [super new]; }
@end
Counted *make(void) { return [Counted new]; }
Counted *makeInit(void) { return [[Counted alloc] init]; }
