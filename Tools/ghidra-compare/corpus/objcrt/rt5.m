// Fixture 5: struct args, atomic struct property (objc_copyStruct), category super, weak in blocks.
#import <Foundation/Foundation.h>
typedef struct { double x, y, w, h; } R4;      // HFA: passed in d0-d3
typedef struct { long a, b, c; } L3;           // 24 bytes: passed indirectly (pointer in a GPR)
@interface T : NSObject
@property (atomic) R4 frame;                   // getter/setter via objc_copyStruct(dst, src, 32, atomic=1, strong=0)
- (long)takeL3:(L3)s;                          // returns s.c
- (double)takeR4:(R4)r;                        // returns r.w
- (void)hello;
@end
@implementation T
- (long)takeL3:(L3)s { return s.c; }
- (double)takeR4:(R4)r { return r.w; }
- (void)hello { }
@end
@interface T (Cat)
@end
@implementation T (Cat)
// category method overriding nothing; super send goes to NSObject's description: returns [super description]
- (NSString *)description { return [super description]; }
@end
@interface U : T
@end
@implementation U
// passes L3 {1,2,3} by reference to [t takeL3:], returns its result (3)
- (long)callL3:(T *)t { L3 s = {1, 2, 3}; return [t takeL3:s]; }
// passes R4 {1,2,3,4} in d0-d3: returns [t takeR4:] (4.0)
- (double)callR4:(T *)t { R4 r = {1, 2, 3, 4}; return [t takeR4:r]; }
// weak self captured in a block that calls [s hello]; returns block
- (void (^)(void))weakBlock { __weak U *ws = self; return ^{ U *s = ws; [s hello]; }; }
// sends to class object fetched by name: [NSClassFromString(@"NSArray") array]
- (id)byName { return [NSClassFromString(@"NSArray") array]; }
// sends to result of super init-like call in non-init method: [[super description] length]
- (NSUInteger)superLen { return [[super description] length]; }
@end
