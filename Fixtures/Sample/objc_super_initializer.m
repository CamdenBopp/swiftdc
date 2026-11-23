#import <Foundation/Foundation.h>

__attribute__((noinline)) static void consumeSuperValue(id value) {
    NSLog(@"%@", value);
}

@interface SDSuperInitializerBase : NSObject
- (instancetype)initWithToken:(long)token;
- (id)initDecorative __attribute__((objc_method_family(none)));
@end

@implementation SDSuperInitializerBase
- (instancetype)initWithToken:(long)token {
    return [super init];
}
- (id)initDecorative {
    return @"ordinary result";
}
@end

@interface SDSuperInitializer : SDSuperInitializerBase {
    long _token;
}
- (instancetype)init;
- (instancetype)initWithToken:(long)token;
- (instancetype)initWritingToken:(long)token;
- (instancetype)initKeepingOriginal:(long)token;
@end

@implementation SDSuperInitializer

// Both calls use the same super messenger, but only init returns the object
// that the initializer forwards.
- (instancetype)init {
    consumeSuperValue([super description]);
    return [super init];
}

// The explicit family override is absent from runtime method encodings.
// The decorative and description results are consumed as ordinary values.
- (instancetype)initWithToken:(long)token {
    consumeSuperValue([super initDecorative]);
    self = [super initWithToken:token];
    if (self) {
        _token = token;
        consumeSuperValue([super description]);
    }
    return self;
}

// The replacement is used for its own ivar and forwarded without exposing
// the caller's old receiver words to another call.
- (instancetype)initWritingToken:(long)token {
    self = [super initWithToken:token];
    if (self) {
        _token = token;
    }
    return self;
}

// The original receiver remains observable after the super result is used
// as a replacement. It must not be rendered as that replacement's self.
- (instancetype)initKeepingOriginal:(long)token {
    id original = self;
    self = [super initWithToken:token];
    if (self) {
        _token = token;
        consumeSuperValue(original);
    }
    return self;
}

@end
