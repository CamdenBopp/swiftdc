// Fixture 2: struct/variadic/float sends, class-method self, super in +method and -init.
#import <Foundation/Foundation.h>
typedef struct { long a, b, c, d, e; } Big;      // 40 bytes, non-HFA: returned via x8 (indirect)
typedef struct { long a, b; } Pair;               // 16 bytes: returned in x0/x1
@interface P : NSObject
- (Big)big:(long)k;               // returns {k,k+1,k+2,k+3,k+4}
- (Pair)pair:(long)k;             // returns {k, 2k}
+ (NSString *)name;               // returns @"P"
- (instancetype)initWithN:(long)n;
@property (nonatomic) long n;
@end
@implementation P
- (Big)big:(long)k { Big r = {k,k+1,k+2,k+3,k+4}; return r; }
- (Pair)pair:(long)k { Pair p = {k, 2*k}; return p; }
+ (NSString *)name { return @"P"; }
// super init: self = [super init]; if self, _n = n; return self
- (instancetype)initWithN:(long)n { if ((self = [super init])) { _n = n; } return self; }
@end
@interface Q : P
@end
@implementation Q
// class-method super: returns [[super name] stringByAppendingString:@"Q"]
+ (NSString *)name { return [[super name] stringByAppendingString:@"Q"]; }
// class method on self: returns [self name]   (receiver is the Class Q or subclass)
+ (NSString *)selfName { return [self name]; }
// x8 struct send: returns [p big:3].e  (== 7)
- (long)bigE:(P *)p { return [p big:3].e; }
// x8 super struct: returns [super big:k].c
- (long)superBigC:(long)k { return [super big:k].c; }
// pair: returns [p pair:5].b (== 10)
- (long)pairB:(P *)p { return [p pair:5].b; }
// variadic with double and long: [NSString stringWithFormat:@"%f %ld %@", d, n, s]
- (NSString *)vfmt:(double)d n:(long)n s:(NSString *)s { return [NSString stringWithFormat:@"%f %ld %@", d, n, s]; }
// variadic many args (spill): arrayWithObjects:a,b,c,d,e,f,g,h,i,nil
- (NSArray *)many:(id)a b:(id)b c:(id)c d:(id)d e:(id)e f:(id)f { return [NSArray arrayWithObjects:a, b, c, d, e, f, a, b, nil]; }
// float args: [NSNumber numberWithDouble:x * 2]
- (NSNumber *)dbl:(double)x { return [NSNumber numberWithDouble:x * 2]; }
// mixed arg send: [o setValue:@(n) forKey:@"k"] then returns [o valueForKey:@"k"]
- (id)kvc:(id)o n:(long)n { [o setValue:@(n) forKey:@"k"]; return [o valueForKey:@"k"]; }
// performSelector:withObject: on o with arg x
- (id)perf2:(id)o x:(id)x { return [o performSelector:@selector(isEqual:) withObject:x]; }
// @available unfoldable (future): returns 1 iff macOS >= 99
- (int)future { if (@available(macOS 99, *)) return 1; return 0; }
// respondsToSelector on self with a dynamic selector arg
- (BOOL)resp:(SEL)s { return [self respondsToSelector:s]; }
// ARC: alloc on runtime Class argument: returns [[c alloc] initWithN:4]
- (id)make:(Class)c { return [[c alloc] initWithN:4]; }
// float send with float arg: CGFloat-free: [o numberWithFloat:f] where o is class NSNumber
- (id)nf:(float)f { return [NSNumber numberWithFloat:f]; }
@end
