// Sends with no signature for their receiver, of selectors that only the
// SDK declares, so no implementation in this image says how they pass their
// arguments. Each method receives the receiver in x2 and passes its own
// floating-point arguments straight through, so x2 (and up) still hold the
// method's arguments at the send:
//
// - `setAlphaValue:` takes the CGFloat in d0 and `setFrameOrigin:` the
//   NSPoint in d0-d1: x2 is the receiver, not the argument.
// - `removeIndexesInRange:` takes the NSRange in x2-x3: x2 is the location
//   alone.
// - `performSelector:withObject:afterDelay:` takes the selector and object
//   in x2-x3 and the delay in d0, so the first two are where the layout
//   reads them and x4 still holds the object.
// - `objectAtIndex:` takes one NSUInteger, so its send keeps its argument
//   (the control).
//
// True behaviour: each send passes the values named in its source line.
#import <AppKit/AppKit.h>

@interface SDSDKSender : NSObject
- (void)dim:(id)window by:(double)alpha;
- (void)move:(id)view x:(double)x y:(double)y;
- (void)unindex:(id)set at:(long)location length:(long)length;
- (void)later:(id)target action:(SEL)action object:(id)object delay:(double)delay;
- (id)fetch:(id)array at:(unsigned long)index;
@end

@implementation SDSDKSender
- (void)dim:(id)window by:(double)alpha { [window setAlphaValue:alpha]; }
- (void)move:(id)view x:(double)x y:(double)y { [view setFrameOrigin:NSMakePoint(x, y)]; }
- (void)unindex:(id)set at:(long)location length:(long)length {
    [set removeIndexesInRange:NSMakeRange(location, length)];
}
- (void)later:(id)target action:(SEL)action object:(id)object delay:(double)delay {
    [target performSelector:action withObject:object afterDelay:delay];
}
- (id)fetch:(id)array at:(unsigned long)index { return [array objectAtIndex:index]; }
@end
