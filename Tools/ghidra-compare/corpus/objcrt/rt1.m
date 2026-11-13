// Fixture: ObjC runtime idioms. True behaviour noted per method.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
typedef struct { double x, y, w, h; } Rect4;   // 32 bytes: returned via x8
@interface Base : NSObject
- (NSInteger)value;                 // returns 7
- (Rect4)rect;                      // {1,2,3,4}
- (double)scale;                    // 2.5
@end
@implementation Base
- (NSInteger)value { return 7; }
- (Rect4)rect { Rect4 r = {1,2,3,4}; return r; }
- (double)scale { return 2.5; }
@end
@interface Kid : Base
@property (atomic, strong) NSString *aname;     // objc_getProperty/objc_setProperty_atomic
@property (nonatomic, weak) id delegate;        // weak load/store
@property (atomic, copy) NSString *title;
@end
static int gInit;
@implementation Kid
@dynamic title;
+ (void)initialize { if (self == [Kid class]) gInit = 1; }   // stores 1 to gInit iff self == Kid
+ (void)load { gInit = 2; }                                   // stores 2
// super: receiver self, class Kid's super, selector value; returns super's +1
- (NSInteger)value { return [super value] + 1; }
// super struct return via x8: returns super rect with x doubled
- (Rect4)rect { Rect4 r = [super rect]; r.x *= 2; return r; }
// super double: returns super scale * 3
- (double)scale { return [super scale] * 3.0; }
// class method: returns [NSString stringWithFormat:@"%d-%@", n, s]
+ (NSString *)fmt:(int)n s:(NSString *)s { return [NSString stringWithFormat:@"%d-%@", n, s]; }
// @synchronized(self) { count++ } ; returns count
- (int)locked:(int *)count { @synchronized(self) { (*count)++; } return *count; }
// @try: calls [o description]; on NSException returns @"caught"; @finally sets *flag=1
- (NSString *)tryit:(id)o flag:(int *)flag {
  @try { return [o description]; }
  @catch (NSException *e) { return @"caught"; }
  @finally { *flag = 1; }
}
// throws: [NSException raise...] style via @throw
- (void)thrower { @throw [NSException exceptionWithName:@"N" reason:@"R" userInfo:nil]; }
// weak: loads weak delegate, sends -hash, returns it (0 if nil)
- (NSUInteger)weakHash { id d = self.delegate; return [d hash]; }
// local __weak init/destroy: returns [w length] of weak copy of s
- (NSUInteger)weakLocal:(NSString *)s { __weak NSString *w = s; return [w length]; }
// autoreleasepool: returns count of a fresh array
- (NSUInteger)pool { NSUInteger c; @autoreleasepool { NSArray *a = [NSArray arrayWithObjects:@"a", @"b", nil]; c = a.count; } return c; }
// alloc/init/new/class/isKind/responds
- (id)allocs { return [[NSMutableArray alloc] init]; }
- (id)news { return [NSMutableDictionary new]; }
- (BOOL)isStr:(id)o { return [o isKindOfClass:[NSString class]]; }
- (BOOL)resp:(id)o { return [o respondsToSelector:@selector(count)]; }
- (Class)cls:(id)o { return [o class]; }
// fast enumeration: sums [x integerValue] over arr
- (NSInteger)sum:(NSArray *)arr { NSInteger t = 0; for (NSNumber *x in arr) t += [x integerValue]; return t; }
// available: returns 1 if macOS 14+, else 0
- (int)avail { if (@available(macOS 14, *)) return 1; return 0; }
// associated object: sets key &gInit to v, retain nonatomic
- (void)assoc:(id)v { objc_setAssociatedObject(self, &gInit, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)getAssoc { return objc_getAssociatedObject(self, &gInit); }
// performSelector: performs @selector(description) on o
- (id)perf:(id)o { return [o performSelector:@selector(description)]; }
// literals
- (NSArray *)arr { return @[@"x", @42, @(3.5)]; }
- (NSDictionary *)dict:(id)v { return @{@"k": v}; }
- (NSNumber *)boxed:(int)n { return @(n + 1); }
// dispatch_once: returns a static singleton NSObject
+ (id)shared { static id s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [NSObject new]; }); return s; }
// float send: returns [o floatValue] + 1
- (float)fl:(NSNumber *)o { return [o floatValue] + 1.0f; }
// struct send to other object: returns [b rect].w
- (double)rectW:(Base *)b { return [b rect].w; }
@end
