// x20 is callee-saved, so a receiver placed there for one call is still
// there for the next: `c.m1() &+ c.m2()` is `mov x20, x0; bl m1; bl m2`,
// both with self = c. x20 was read only when written since the last call
// (a callee whose self is not in x20 would otherwise inherit a stale one),
// so the second call read `SelfAgain.Box.m2()`.
//
// True behaviour: twice(c) returns c.m1() + c.m2(), both on c. thenStatic(c)
// returns c.m1() + Box.make(), a static method that takes no self.
// withPair(c, p) returns c.m1() + p.sum(1): a struct's method takes its
// self's words after its formals, not in x20, so it has no x20 receiver.
// withMode(c, m) returns c.m1() + m.code(): an enum's method takes its
// value in x0, not in x20.

import SelfAgainKit

@inline(never) public func twice(_ c: Box) -> Int { c.m1() &+ c.m2() }
@inline(never) public func thenStatic(_ c: Box) -> Int { c.m1() &+ Box.make() }
@inline(never) public func withPair(_ c: Box, _ p: Pair) -> Int { c.m1() &+ p.sum(1) }
@inline(never) public func withMode(_ c: Box, _ m: Mode) -> Int { c.m1() &+ m.code() }
