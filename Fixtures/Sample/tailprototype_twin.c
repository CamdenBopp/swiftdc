// A vendored function with a C library's name: not the library's strlen,
// so the SDK prototype says nothing about what it returns. It calls out,
// so its x0 at return is whatever `note` left.
extern void note(const char *);
__attribute__((noinline)) void strlen(const char *s) { note(s); note(s + 1); }
