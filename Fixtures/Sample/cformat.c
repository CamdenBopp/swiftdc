// C string literals with whitespace escapes, and printf's variadic
// arguments (clang -O2). A format string almost always ends in "\n"; it is
// a literal in a cstring section and reads as one, not as its address.
// True calls: printf("%d %hd %hhd %u %ld %c\n", -1, -2, -3, 4000000000u,
// -4L, 'A') and puts("a\tb\r\n").
#include <stdio.h>
int printNeg(void) { return printf("%d %hd %hhd %u %ld %c\n", -1, (short)-2, (signed char)-3, 4000000000u, -4L, 'A'); }
int tabbed(void) { return puts("a\tb\r\n"); }
