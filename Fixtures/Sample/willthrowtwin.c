// An in-image function that shares the name of the runtime's throw hook
// and nothing else. The runtime's swift_willThrow takes the error in x21,
// nothing in x0, and returns nothing. This one reads x0 and returns
// x * 5 + 41; it does not touch x21. See willthrowtwin.s.
long swift_willThrow(long x) { return x * 5 + 41; }
