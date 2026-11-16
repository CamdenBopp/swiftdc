// When does a tail branch to a C-named callee return its result? Each
// function is an Int-returning Swift function ending in `b <callee>` (-O):
//   viaRandom:  libc `long random(void)`, imported      -> returns it
//   viaTwin:    this image's own `strlen` (tailprototype_twin.c), which
//               shares the library's name but is not it  -> unproven
//   viaVoid:    libc `void srandom(unsigned)`            -> no result
//   viaDouble:  libc `double drand48(void)`              -> not in x0
// The declarations lie about the result on purpose: the binary, not the
// caller's source, has to justify a `return`.
@_silgen_name("random") func c_random() -> Int
@_silgen_name("strlen") func c_strlen(_: UnsafePointer<CChar>) -> Int
@_silgen_name("srandom") func c_srandom(_: UInt32) -> Int
@_silgen_name("drand48") func c_drand48() -> Int
public func viaRandom() -> Int { c_random() }
public func viaTwin(_ p: UnsafePointer<CChar>) -> Int { c_strlen(p) }
public func viaVoid(_ seed: UInt32) -> Int { c_srandom(seed) }
public func viaDouble() -> Int { c_drand48() }
