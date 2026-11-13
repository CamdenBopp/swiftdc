// LEVELS: O0 O1 O2 Os
// Variadic sends and calls on Darwin arm64.
//
// Apple's arm64 ABI passes every variadic argument on the stack in 8-byte
// slots, ints and doubles alike; only the fixed (named) arguments use
// registers. So in formatInt the format string is x2 (the one named
// argument of stringWithFormat:) and 42 is stored at [sp], never in x3.
// A double variadic is stored as its bit pattern at [sp], never in d0.
// TRUE behaviours:
//   formatInt:     [NSString stringWithFormat:@"n=%d", 42]
//   formatMixed:   [NSString stringWithFormat:@"%d %f %@", n, d, obj]
//                  with n, d, obj at [sp], [sp, #8], [sp, #16]
//   logTwo:        NSLog(@"%@ and %ld", obj, 7L), format in x0, both
//                  variadics on the stack
//   listOf:        [NSArray arrayWithObjects:a, b, nil]: a is the named
//                  argument in x2, b and the nil terminator on the stack
// A render that places a variadic in x3/d0, or prints the call as if its
// register arguments were the whole list, is wrong.
#import <Foundation/Foundation.h>

// EXPECT structured * formatInt :: stringWithFormat:
// EXPECT structured * formatInt :: "n=%d"
// FORBID structured * formatInt :: re:stringWithFormat:\s*"n=%d"\s*\]
NSString *formatInt(void) {
    return [NSString stringWithFormat:@"n=%d", 42];
}

// EXPECT structured * formatMixed :: stringWithFormat:
// EXPECT structured * formatMixed :: "%d %f %@"
// FORBID structured * formatMixed :: re:stringWithFormat:\s*"%d %f %@"\s*\]
// n is [sp] (from w0), d is [sp, #8] (from d0), obj is [sp, #16] (from x1).
// FORBID structured * formatMixed :: re:"%d %f %@", arg1
// FORBID structured * formatMixed :: re:"%d %f %@", [^,\n]+, arg0
// A selector stub (objc_msgSend$sel) loads _cmd itself, so the caller's
// x1 (here still obj, arg1) is not the send's second argument.
// FORBID listing O1,O2,Os formatMixed :: re:stringWithFormat:\s+args\(NSString, arg1,
NSString *formatMixed(int n, double d, id obj) {
    return [NSString stringWithFormat:@"%d %f %@", n, d, obj];
}

// EXPECT structured * logTwo :: NSLog
// EXPECT structured * logTwo :: "%@ and %ld"
// FORBID structured * logTwo :: re:NSLog\("%@ and %ld"\)
void logTwo(id obj) {
    NSLog(@"%@ and %ld", obj, 7L);
}

// EXPECT structured * listOf :: arrayWithObjects:
// EXPECT structured * listOf :: , 0]
// EXPECT structured O1,O2,Os listOf :: arrayWithObjects:arg0, arg1, 0]
// FORBID structured * listOf :: re:arrayWithObjects:[^\n\]]*\barg1\]
// FORBID structured * listOf :: re:arrayWithObjects:arg1
NSArray *listOf(id a, id b) {
    return [NSArray arrayWithObjects:a, b, nil];
}

// A plain C variadic for contrast: printf-family on Darwin also puts the
// variadics on the stack. TRUE: snprintf(buf, 32, "%d", 5).
// EXPECT structured * formatC :: snprintf
// EXPECT structured * formatC :: "%d"
// FORBID structured * formatC :: re:snprintf\([^\n]*"%d"\)
int formatC(char *buf) {
    return snprintf(buf, 32, "%d", 5);
}
