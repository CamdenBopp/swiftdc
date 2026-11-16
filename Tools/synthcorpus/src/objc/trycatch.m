// LEVELS: O0 O1 O2 Os
// @try/@catch/@finally on arm64 (zero-cost, Itanium-style unwinding).
//
// The try body is ordinary code; the landing pad is reached only through
// the unwinder (no branch to it in the CFG), begins with objc_begin_catch
// on the exception object, and ends with objc_end_catch. @throw lowers to
// objc_exception_throw, which never returns.
// TRUE behaviours:
//   guarded(o)    returns [o intValue], or -1 if it throws an NSException
//   thrower(r)    raises when r == 0 (objc_exception_throw does not return),
//                 otherwise returns r
#import <Foundation/Foundation.h>

// EXPECT structured * guarded :: intValue]
int guarded(id o) {
    @try {
        return [o intValue];
    } @catch (NSException *e) {
        return -1;
    }
}

// EXPECT structured * thrower :: objc_exception_throw
// EXPECT structured * thrower :: no fall-through
// FORBID structured * thrower :: re:objc_exception_throw\([^\n]*\)\n\s*return arg0
int thrower(int r) {
    if (r == 0) {
        @throw [NSException exceptionWithName:@"Zero" reason:@"r is zero" userInfo:nil];
    }
    return r;
}
