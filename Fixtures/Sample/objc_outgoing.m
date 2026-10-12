#import <Foundation/Foundation.h>

// Distinct integer/FP/object banks in an Objective-C message send. These
// methods remain dynamically dispatched at both optimization levels.
@interface SDOutgoingProbe : NSObject {
    long _whole;
    double _fraction;
    id _object;
    long _tail;
}
- (void)whole:(long)whole fraction:(double)fraction object:(__unsafe_unretained id)object tail:(long)tail;
- (void)forwardWhole:(long)whole fraction:(double)fraction object:(__unsafe_unretained id)object tail:(long)tail;
- (void)constants;
- (double)floatResult;
- (float)singleResult;
- (void)adjustFraction:(double)value;
- (void)a:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h ratio:(double)ratio;
- (void)forwardA:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h ratio:(double)ratio;
@end
@implementation SDOutgoingProbe
- (void)whole:(long)whole fraction:(double)fraction object:(__unsafe_unretained id)object tail:(long)tail {
    _whole = whole;
    _fraction = fraction;
    _object = object;
    _tail = tail;
}
- (void)forwardWhole:(long)whole fraction:(double)fraction object:(__unsafe_unretained id)object tail:(long)tail {
    [self whole:whole fraction:fraction object:object tail:tail];
}
- (void)constants {
    [self whole:11 fraction:2.5 object:nil tail:33];
}
- (void)a:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h ratio:(double)ratio {
    _whole = a + b + c + d + e + f + g + h;
    _fraction = ratio;
}
- (void)forwardA:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h ratio:(double)ratio {
    [self a:a b:b c:c d:d e:e f:f g:g h:h ratio:ratio];
}
- (double)floatResult { return 2.5; }
- (float)singleResult { return 1.25f; }
- (void)adjustFraction:(double)value { [self whole:11 fraction:value + 2.5 object:nil tail:33]; }
@end

// Native callable oracle: tests execute these Objective-C dispatches rather
// than trusting only decompiler text.
double SDOutgoingNativeDouble(void) { return [[SDOutgoingProbe new] floatResult]; }
float SDOutgoingNativeFloat(void) { return [[SDOutgoingProbe new] singleResult]; }
_Static_assert(sizeof(long double) == sizeof(double), "Darwin arm64 long-double ABI changed");
