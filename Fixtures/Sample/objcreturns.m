// Objective-C methods whose return is not one x register (-O2, ARC).
// True behaviour: -scaled: returns _scale * k in d0; -big returns a 40-byte
// struct through x8; -rect: a CGRect in d0-d3; -count returns _n in x0.
#import <Foundation/Foundation.h>
typedef struct { long a, b, c, d, e; } S5;
@interface Rets : NSObject { double _scale; long _n; }
- (double)scaled:(double)k;
- (S5)big;
- (CGRect)rect:(double)x;
- (long)count;
@end
@implementation Rets
- (double)scaled:(double)k { return _scale * k; }
- (S5)big { return (S5){1, 2, 3, 4, 5}; }
- (CGRect)rect:(double)x { return CGRectMake(x, 1, 2, 3); }
- (long)count { return _n; }
@end
