// A send returning a CGRect leaves it in d0-d3 (-O2). vertexFromRect passes
// [self rect]'s origin to glVertex2d: d0 and d1 are fields of the send's
// result, so neither argument is the send. vertexScaled passes [self
// scale], a double, whole in d0. offsetFrame passes
// [self rect]'s origin as CGRectOffset's offsets: `mov v8, v0; mov v9, v1`
// after the send, then `mov v4, v8; mov v5, v9` before the call, so d4 holds
// one field of the send's result, not the send.
//
// vertexInterval passes [date timeIntervalSinceNow], which only Foundation
// declares, an NSTimeInterval (double). vertexSize passes [object size]: this
// class's size returns a double, but NSImage's returns an NSSize in d0-d1,
// and the receiver is unknown.
//
// vertexLane passes [object lane]: SDLanes's lane returns a double and
// SDPoint's a CGPoint, both in this image.
//
// True behaviour: vertexLane calls glVertex2d([object lane], 0.5);
// vertexInterval calls glVertex2d([date
// timeIntervalSinceNow], 0.5); vertexSize calls glVertex2d([object size],
// 0.5) with whichever size the receiver has; vertexFromRect calls glVertex2d(r.origin.x, r.origin.y)
// where r = [self rect]; vertexScaled calls glVertex2d([self scale], 0.5);
// offsetFrame returns CGRectOffset([self closeRect],
// r.origin.x, r.origin.y) where r = [self rect]; scaledFrame returns
// CGRectInset([self closeRect], [self scale], 0.5), and scale returns a
// double, whole in d0.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#define GL_SILENCE_DEPRECATION
#import <OpenGL/gl.h>

@interface SDLanes : NSObject
- (CGRect)rect;
- (CGRect)closeRect;
- (double)scale;
- (double)size;
- (double)lane;
@end

@interface SDPoint : NSObject
- (CGPoint)lane;
@end

@implementation SDPoint
- (CGPoint)lane { return CGPointMake(1, 2); }
@end

@implementation SDLanes
- (CGRect)rect { return CGRectMake(1, 2, 3, 4); }
- (CGRect)closeRect { return CGRectMake(5, 6, 7, 8); }
- (double)scale { return 2.0; }
- (CGRect)offsetFrame {
    CGRect r = [self rect];
    return CGRectOffset([self closeRect], r.origin.x, r.origin.y);
}
- (CGRect)scaledFrame { return CGRectInset([self closeRect], [self scale], 0.5); }
- (void)vertexFromRect {
    CGRect r = [self rect];
    glVertex2d(r.origin.x, r.origin.y);
}
- (void)vertexScaled { glVertex2d([self scale], 0.5); }
- (double)size { return 3.0; }
- (void)vertexInterval:(NSDate *)date { glVertex2d([date timeIntervalSinceNow], 0.5); }
- (void)vertexSize:(id)object { glVertex2d([object size], 0.5); }
- (double)lane { return 4.0; }
- (void)vertexLane:(SDLanes *)object { glVertex2d([object lane], 0.5); }
@end
