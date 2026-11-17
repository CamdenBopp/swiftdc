// -Onone retains Int-returning reabstraction thunks with x8 sret despite their
// scalar printed result. Optimized builds may remove those thunks. Every native
// start call must return its input plus seven at all three optimization levels.
@inline(never) public func apply<T,R>(_ f: (T) -> R, _ x: T) -> R { f(x) }
@inline(never) public func value(_ n: Int) -> Int { n &+ 7 }
@inline(never) public func start(_ n: Int) -> Int { apply(value,n) }
