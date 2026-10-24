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

// A C call shaped like Swift's literal initializer (address, count, 1).
// Only that initializer's pointer is read as a counted literal; this one
// is a C string with a control character, so it stays an address.
const char *countLikeText;
long countLikeCount;
__attribute__((noinline)) void countLike(const char *text, long count, int flag) {
    countLikeText = text;
    countLikeCount = count + flag;
}
void cCountLike(void) { countLike("\a b", 3, 1); }
