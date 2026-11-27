// A library that is not the Swift runtime, exporting two functions under
// runtime-style names. Both return five words, which the C ABI delivers
// through the caller's x8. swift_slowAlloc is also the runtime's name for
// a function returning one pointer; swift_opaqueResult is no runtime's.
struct Five { unsigned long long a, b, c, d, e; };
struct Five swift_opaqueResult(void) { return (struct Five){21, 22, 23, 24, 25}; }
struct Five swift_slowAlloc(void) { return (struct Five){31, 32, 33, 34, 35}; }
