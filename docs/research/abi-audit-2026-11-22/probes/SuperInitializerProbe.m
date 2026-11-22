#import <Foundation/Foundation.h>

__attribute__((noinline)) void consumeDescription(id value) {
    NSLog(@"%@", value);
}

@interface ABISuperProbe : NSObject
@end

@implementation ABISuperProbe
- (instancetype)init {
    consumeDescription([super description]);
    return [super init];
}
@end
