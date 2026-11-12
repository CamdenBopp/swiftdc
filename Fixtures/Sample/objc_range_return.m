// SDK sends that return an NSRange, an integer struct of two words that
// comes back in x0 and x1. x0 is .location alone, so the send is not the
// value: `return [s rangeOfString:@"x"]` for `.location` named the whole
// struct, and `([s rangeOfString:@"q"] != 0x7fffffffffffffff)` an NSNotFound
// test of it.
//
// True behaviour: loc returns the location of "x" in s; locPlusOne that
// plus one; found returns whether "q" occurs in s; keep stores the
// selected range's location into _u.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface RangeUser : NSObject { @public NSUInteger _u; }
- (NSUInteger)loc:(NSString *)s;
- (NSUInteger)locPlusOne:(NSString *)s;
- (BOOL)found:(NSString *)s;
- (void)keep:(NSTextView *)view;
@end

@implementation RangeUser
- (NSUInteger)loc:(NSString *)s { return [s rangeOfString:@"x"].location; }
- (NSUInteger)locPlusOne:(NSString *)s { return [s rangeOfString:@"x"].location + 1; }
- (BOOL)found:(NSString *)s { return [s rangeOfString:@"q"].location != NSNotFound; }
- (void)keep:(NSTextView *)view { _u = [view selectedRange].location; }
@end
