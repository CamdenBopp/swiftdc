// LEVELS: O0 O1 O2 Os
// Super sends, class methods and categories.
//
// [super m] lowers to objc_msgSendSuper2 with x0 = &{self, cls} (an
// objc_super2 on the stack whose second word is the CURRENT class, from
// the class ref; the runtime starts lookup at cls->superclass). The
// receiver of the message is self, the selector is x1. A class method's
// self is the class object. A category method is an ordinary method of
// the extended class whose name carries the category: -[SPBase(Extra) twice].
// TRUE behaviours:
//   -[SPChild init]          calls [super init] (SPBase's init), then
//                            sets _level = 2
//   -[SPChild describe]      returns [super describe] + 10
//   +[SPChild make]          returns [[self alloc] init] (self = the class)
//   -[SPBase(Extra) twice]   returns [self describe] * 2
//   callTwice(b)             sends twice to b
#import <Foundation/Foundation.h>

@interface SPBase : NSObject { @public int _level; }
- (int)describe;
@end
@implementation SPBase
- (int)describe { return _level; }
- (int)scaled:(int)k by:(double)f { return (int)(_level * k * f); }
@end

@interface SPChild : SPBase
+ (instancetype)make;
- (int)scaled:(int)k by:(double)f;
@end

@implementation SPChild
// EXPECT structured * -[SPChild init] :: super
// FORBID structured * -[SPChild init] :: re:\n[^\n]*\[SPChild init\]
- (instancetype)init {
    if ((self = [super init])) { _level = 2; }
    return self;
}
// EXPECT structured * -[SPChild describe] :: super
// EXPECT structured * -[SPChild describe] :: describe]
// FORBID structured * -[SPChild describe] :: re:\[self describe\]
- (int)describe {
    return [super describe] + 10;
}
// A super send with arguments: x0 = &objc_super, x1 = selector, k in x2,
// f in d0. TRUE: [super scaled:k + 1 by:f].
// EXPECT structured * -[SPChild scaled:by:] :: super
// EXPECT structured * -[SPChild scaled:by:] :: scaled:
// FORBID structured * -[SPChild scaled:by:] :: re:\[self scaled:
// FORBID structured * -[SPChild scaled:by:] :: re:scaled:(local_|&)
- (int)scaled:(int)k by:(double)f {
    return [super scaled:k + 1 by:f];
}
// EXPECT structured * +[SPChild make] :: alloc]
// EXPECT structured * +[SPChild make] :: init]
+ (instancetype)make {
    return [[self alloc] init];
}
@end

@interface SPBase (Extra)
- (int)twice;
@end
@implementation SPBase (Extra)
// EXPECT structured * twice] :: describe]
- (int)twice { return [self describe] * 2; }
@end

// EXPECT structured * callTwice :: twice]
int callTwice(SPBase *b) { return [b twice]; }

// A class message to a known class: receiver is the class ref.
// EXPECT structured * makeChild :: make]
// FORBID structured * makeChild :: re:\[SPBase make\]
id makeChild(void) { return [SPChild make]; }
