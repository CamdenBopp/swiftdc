#import <Foundation/Foundation.h>

@interface SDVoidProbe : NSObject
- (void)write:(long)x;
- (long)captureVoidResult;
@end
@implementation SDVoidProbe
- (void)write:(long)x { NSLog(@"%ld", x); }
- (long)captureVoidResult {
    [self write:7];
    // Observe the unspecified physical return register without giving the
    // void message a source return value. The decompiler must decline it.
    long raw;
    __asm__ volatile("mov %0, x0" : "=r"(raw));
    return raw;
}
@end
