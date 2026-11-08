// An autoreleased object used twice, built without ARC (-O2): clang emits
// `objc_alloc_init(NSMutableString)`, then `objc_autorelease`, and uses
// the autorelease's result twice. objc_autorelease returns the object it
// is handed, and modelled as returning something else its result printed
// as the allocation at each use: `[[NSMutableString alloc] init]` three
// times, as if three objects were made.
//
// enumerateAutoreleased enumerates an object it loads and autoreleases,
// which nothing here knows: the autorelease's result is still a value,
// and the mutation callback fast enumeration calls takes it.
//
// True behaviour: autoreleasedTwice allocates one string, autoreleases
// it, appends to it and returns its length; enumerateAutoreleased counts
// the elements of the autoreleased *p.
#import <Foundation/Foundation.h>

NSUInteger autoreleasedTwice(void) {
    NSMutableString *s = [[[NSMutableString alloc] init] autorelease];
    [s appendString:@"a"];
    return [s length];
}

NSUInteger enumerateAutoreleased(id *p) {
    NSUInteger n = 0;
    for (id x in [[*p retain] autorelease]) { (void)x; n++; }
    return n;
}
