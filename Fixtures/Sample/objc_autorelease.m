// An autoreleased object used twice, built without ARC (-O2): clang emits
// `objc_alloc_init(NSMutableString)`, then `objc_autorelease`, and uses
// the autorelease's result twice. objc_autorelease returns the object it
// is handed, and modelled as returning something else its result printed
// as the allocation at each use: `[[NSMutableString alloc] init]` three
// times, as if three objects were made.
//
// True behaviour: one string is allocated, autoreleased, appended to and
// asked its length, which is returned.
#import <Foundation/Foundation.h>

NSUInteger autoreleasedTwice(void) {
    NSMutableString *s = [[[NSMutableString alloc] init] autorelease];
    [s appendString:@"a"];
    return [s length];
}
