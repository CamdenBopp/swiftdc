// A getter that returns a constant beside a synthesized one, in an ordinary
// image (function starts, symbols). True behaviour: `-period` is custom
// (`mov w0, #-1; ret`: no ivar is read), so the header keeps its line;
// `-count` is synthesized (`ldr w0, [x0, #8]; ret`), implied by its
// @property, and dropped.
#import <Foundation/Foundation.h>
@interface Settings : NSObject
@property (nonatomic, readonly) int period;
@property (nonatomic, readonly) int count;
@end
@implementation Settings
- (int)period { return -1; }
@end
