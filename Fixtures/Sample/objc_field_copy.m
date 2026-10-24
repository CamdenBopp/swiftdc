// An Objective-C struct ivar copied into another with one 16-byte register:
// at -O2 `_saved = _current` is `ldr q0, [x0, #current]; str q0, [x0,
// #saved]`, a single store whose one value is both words of the source.
//
// True behaviour: saved becomes current.
#import <Foundation/Foundation.h>

@interface SDFieldCopy : NSObject {
    NSPoint _current;
    NSPoint _saved;
}
- (void)save;
@end

@implementation SDFieldCopy
- (void)save { _saved = _current; }
@end
