// C and Objective-C literals holding a quote or a backslash (-O2). A
// rendered literal must spell its bytes: `cBackslash` passes a, backslash,
// n, b, which read as a newline when printed `"a\nb"`, and `cBoth`'s
// backslash and quote printed `"\\""`, which does not parse. The true
// literals are `"a\\nb"`, `"\\\""` and `@"x\\y"`.
#import <Foundation/Foundation.h>
#include <stdio.h>

void cQuote(void) { puts("q\"r"); }
void cBackslash(void) { puts("a\\nb"); }
void cBoth(void) { puts("\\\""); }
void objcBackslash(void) { NSLog(@"x\\y"); }
