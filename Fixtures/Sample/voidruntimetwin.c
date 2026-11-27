// In-image functions that share the names of runtime entry points that
// return nothing, and return a value. See voidruntimetwin.s.
//
// The runtime's swift_job_run, swift_willThrow and swift_willThrowTypedImpl
// are void. These are not those functions: each returns a value computed
// from its argument, with its own multiplier and constant so no two bodies
// are the same code.
long swift_job_run(long job) { return job * 3 + 37; }
long swift_willThrow(long x) { return x * 5 + 41; }
long swift_willThrowTypedImpl(long x) { return x * 7 + 43; }
// The control: the same shape under a name no table knows.
long plain_result(long x) { return x * 9 + 47; }
