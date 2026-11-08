// An ARC factory: build one object, configure it once, return it. Under
// -fobjc-arc the method exits with a tail `b objc_autoreleaseReturnValue`
// (not a `ret`), with the built object in x0:
//
//   bl  objc_alloc_init      ; the one allocation
//   mov x20, x0
//   bl  objc_msgSend$setLimit:
//   mov x0, x20
//   b   objc_autoreleaseReturnValue
//
// True behaviour of every `+k…`: one allocation, configured, then returned.
// The object is used twice (the configuring send and the return), so it is
// one value: `let r0 = [[…] init…]`, `[r0 setLimit:…]`, `return r0`. Spelled
// out at each use it reads as two allocations.
//
// `+k0` returns a fresh object with no other use, and `-peerCopy` returns
// the result of one send: each has one use and must stay inline, never bound.
#import <Foundation/Foundation.h>

@interface SDFactory : NSObject
@property (nonatomic) long limit;
@property (nonatomic, strong) SDFactory *peer;
- (instancetype)initWithLimit:(long)l;
@end

@implementation SDFactory
- (instancetype)initWithLimit:(long)l { if ((self = [super init])) _limit = l; return self; }
// alloc/init through objc_alloc_init, configured with a setter.
+ (instancetype)k1:(long)v { SDFactory *f = [[self alloc] init]; f.limit = v; return f; }
// A custom init: an ordinary send, not a runtime idiom.
+ (SDFactory *)k2 { SDFactory *f = [[SDFactory alloc] initWithLimit:3]; f.limit = 4; return f; }
// +new through objc_opt_new.
+ (NSMutableArray *)k3 { NSMutableArray *a = [NSMutableArray new]; [a addObject:@"x"]; return a; }
// alloc then initWithCapacity:.
+ (NSMutableArray *)k4 { NSMutableArray *a = [[NSMutableArray alloc] initWithCapacity:4]; [a addObject:@"y"]; return a; }
// The object built and returned with no other use: one use, so it stays
// inline as `return [[self alloc] init]`, never bound.
+ (instancetype)k0 { return [[self alloc] init]; }
// A result used once, by the return alone: stays inline.
- (SDFactory *)peerCopy { return [self.peer peer]; }
@end
