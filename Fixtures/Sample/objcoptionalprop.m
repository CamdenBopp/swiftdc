// An Objective-C protocol's property list carries no optional flag: a
// property is optional when its getter is listed among the protocol's
// optional methods. `name` is @required (getter in the instance methods),
// `nickname` and `custom` (getter `isCustom`) are @optional, and
// `shared` is an optional class property.
#import <Foundation/Foundation.h>

@protocol OPThing <NSObject>
@property (readonly) NSString *name;
@optional
@property (readonly) NSString *nickname;
@property (readonly, getter=isCustom) BOOL custom;
@property (class, readonly) NSInteger shared;
@end

@interface OPBox : NSObject <OPThing>
@end

@implementation OPBox
- (NSString *)name { return @"box"; }
@end
