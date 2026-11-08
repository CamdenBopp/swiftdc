#import <Foundation/Foundation.h>

// A typed, non-self receiver. The target's method metadata fixes its mixed
// integer/FP calling convention; the caller's GP bank alone does not.
@interface SDNonselfTarget : NSObject
- (void)whole:(long)whole ratio:(double)ratio tail:(long)tail;
- (double)twice:(double)value;
@end

static long capturedWhole;
static double capturedRatio;
static long capturedTail;

@implementation SDNonselfTarget
- (void)whole:(long)whole ratio:(double)ratio tail:(long)tail {
    capturedWhole = whole;
    capturedRatio = ratio;
    capturedTail = tail;
}
- (double)twice:(double)value { return value * 2.0; }
@end

@interface SDNonselfCaller : NSObject {
    SDNonselfTarget *_target;
}
- (instancetype)initWithTarget:(SDNonselfTarget *)target;
- (void)forwardWhole:(long)whole ratio:(double)ratio tail:(long)tail;
- (double)forwardTwice:(double)value;
- (double)forwardUntyped:(id)target value:(double)value;
@end

@implementation SDNonselfCaller
- (instancetype)initWithTarget:(SDNonselfTarget *)target {
    if ((self = [super init])) { _target = target; }
    return self;
}
- (void)forwardWhole:(long)whole ratio:(double)ratio tail:(long)tail {
    [_target whole:whole ratio:ratio tail:tail];
}
- (double)forwardTwice:(double)value { return [_target twice:value]; }
- (double)forwardUntyped:(id)target value:(double)value {
    // The cast is source-only. The method encoding retains `id`, so the
    // binary does not prove the receiver class at this dynamic send.
    return [(SDNonselfTarget *)target twice:value];
}
@end

// Native execution checks which bank the dynamic send actually consumes.
double SDNonselfNativeWhole(void) {
    SDNonselfTarget *target = [SDNonselfTarget new];
    SDNonselfCaller *caller = [[SDNonselfCaller alloc] initWithTarget:target];
    [caller forwardWhole:11 ratio:2.5 tail:33];
    return capturedWhole + capturedRatio + capturedTail;
}

double SDNonselfNativeTwice(void) {
    SDNonselfTarget *target = [SDNonselfTarget new];
    SDNonselfCaller *caller = [[SDNonselfCaller alloc] initWithTarget:target];
    return [caller forwardTwice:1.25];
}
