// An Objective-C struct ivar copied into another with one 16-byte register:
// at -O2 `_saved = _current` is `ldr q0, [x0, #current]; str q0, [x0,
// #saved]`, a single store whose one value is both words of the source.
//
// `mixed` (-O0) reads the second word of `_pair` twice, once as a byte and
// once whole, so a value loaded from that offset has no one width.
//
// True behaviour: saved becomes current; mixed returns the low byte of
// pair.b plus pair.b.
#import <Foundation/Foundation.h>

struct SDWords { long a; long b; };

@interface SDFieldCopy : NSObject {
    NSPoint _current;
    NSPoint _saved;
    struct SDWords _pair;
}
- (void)save;
- (long)mixed;
@end

@implementation SDFieldCopy
- (void)save { _saved = _current; }
- (long)mixed { return *(unsigned char *)&_pair.b + _pair.b; }
@end
