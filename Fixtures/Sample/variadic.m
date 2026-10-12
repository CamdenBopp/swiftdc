// Fixture for variadic message sends: a format's arguments travel on the
// stack (Apple arm64), one 8-byte slot per conversion. Built by `build.sh` into
// `libVariadic.dylib` (-O1).
#import <Foundation/Foundation.h>
__attribute__((noinline)) long churn(long a, long b, long c, long d) { return a * b + c * d; }
// x3-x7 hold churn's arguments (still live at the send); the format's two
// conversions are passed on the stack.
NSString *describe(long a, long b, long c, long d) {
    long k = churn(a, b, c, d);
    return [NSString stringWithFormat:@"%ld %ld", k, a];
}
