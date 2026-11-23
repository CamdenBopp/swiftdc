// Returning functions that share a spelling with the Swift error runtime
// and nothing else. See errorlookalike.s.
static volatile long seen;
// A longer name with the hook's prefix. Returns.
void swift_willThrowLookalike(long x) { seen = x; }
// A longer name with the allocator's prefix. Returns null.
void *swift_allocErrorLog(long x) { seen = x; return (void *)0; }
// The allocator's exact name, defined in this image. Returns null.
void *swift_allocError(long x) { seen = x + 1; return (void *)0; }
