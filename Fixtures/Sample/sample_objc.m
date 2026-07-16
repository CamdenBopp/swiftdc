// Pure Objective-C fixture for IMP recovery, selector/type decoding, category
// ownership, Objective-C argument registers, and direct ivar-offset naming.

#import <Foundation/Foundation.h>

@interface SDObjCCounter : NSObject {
    NSInteger _count;
    NSString *_name;
    BOOL _enabled;
}

@property(nonatomic, copy) NSString *name;
@property(nonatomic, getter=isEnabled) BOOL enabled;

- (instancetype)initWithName:(NSString *)name count:(NSInteger)count;
- (NSInteger)incrementBy:(NSInteger)delta;
- (NSInteger)incrementIfEnabled:(NSInteger)delta;
- (NSInteger)incrementIfPositive:(NSInteger)delta;
- (NSString *)greetingWithPrefix:(NSString *)prefix;
- (NSInteger)seventhValueA:(NSInteger)a
                         b:(NSInteger)b
                         c:(NSInteger)c
                         d:(NSInteger)d
                         e:(NSInteger)e
                         f:(NSInteger)f
                         g:(NSInteger)g;

@end

@implementation SDObjCCounter

- (instancetype)initWithName:(NSString *)name count:(NSInteger)count {
    self = [super init];
    if (self) {
        _name = [name copy];
        _count = count;
        _enabled = YES;
    }
    return self;
}

- (NSInteger)incrementBy:(NSInteger)delta {
    _count += delta;
    return _count;
}

- (NSInteger)incrementIfEnabled:(NSInteger)delta {
    if (!_enabled) {
        return _count;
    }
    _count += delta;
    return _count;
}

- (NSInteger)incrementIfPositive:(NSInteger)delta {
    if (delta > 0) {
        _count += delta;
    }
    return _count;
}

- (NSString *)greetingWithPrefix:(NSString *)prefix {
    return [prefix stringByAppendingString:_name];
}

- (NSInteger)seventhValueA:(NSInteger)a
                         b:(NSInteger)b
                         c:(NSInteger)c
                         d:(NSInteger)d
                         e:(NSInteger)e
                         f:(NSInteger)f
                         g:(NSInteger)g {
    return g;
}

@end

@interface SDObjCCounter (Formatting)
- (NSString *)formattedCount;
@end

@implementation SDObjCCounter (Formatting)
- (NSString *)formattedCount {
    return [NSString stringWithFormat:@"%ld", (long)_count];
}
@end

// The linker can fold a category into a class defined in the same image. A
// category on an external class must remain in __objc_catlist, exercising the
// standalone category parser and owner spelling.
@interface NSString (SDSampleExtras)
- (NSString *)sd_stringByAddingBang;
@end

@implementation NSString (SDSampleExtras)
- (NSString *)sd_stringByAddingBang {
    return [self stringByAppendingString:@"!"];
}
@end
