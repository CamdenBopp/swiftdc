// Variadic SDK selectors whose names end in no `…WithFormat:` /
// `…WithObjects:` suffix. Each takes its variadic arguments on the stack
// (`str x1, [sp]`), but laid out as fixed selectors they rendered with
// their format alone and no `…`: `[s stringByAppendingFormat:@"+%ld"]`.
//
// True behaviour: suffixed(s, n) appends "+<n>"; fail(n) raises "Name"
// with "bad <n>"; localized(n) formats n with no locale.
#import <Foundation/Foundation.h>

NSString *suffixed(NSString *s, long n) { return [s stringByAppendingFormat:@"+%ld", n]; }
void fail(long n) { [NSException raise:@"Name" format:@"bad %ld", n]; }
NSString *localized(long n) { return [[NSString alloc] initWithFormat:@"%ld" locale:nil, n]; }
