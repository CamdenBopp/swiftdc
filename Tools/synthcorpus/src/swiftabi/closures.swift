// LEVELS: O Osize Onone
// Closures: non-escaping and escaping captures, partial-apply forwarders. A
// thick closure is two words (function, context); a forwarder loads its
// captures from the context in x20 and tail-calls the closure body.
// TRUE behaviour:
//   addK(k, x): at -O, apply is specialized with the closure propagated and
//   called as (x, k) = (arg1, arg0); returns x + k.
//   makeAdder(k): allocates a 24-byte box (heap metadata 0x4010), stores k at
//   +0x10 and returns (forwarder, box). The closure returns x + 17k.
//   captureBoth(s, a, b): allocates a 40-byte box holding a at +0x10 and the
//   String b at +0x18, +0x20, and stores (forwarder, box) into s.f at
//   s + 0x10, s + 0x18.
//   At -Onone the forwarders tail-call the closure body (b), so they return
//   its value.
// EXPECT structured O,Osize Closures.addK :: of Closures.apply(arg1, arg0)
// FORBID structured O,Osize Closures.addK :: of Closures.apply(arg0, arg1)
// EXPECT structured Onone Closures.addK :: re:Closures\.apply\(\?, (\?|arg1)\)
// EXPECT structured * Closures.makeAdder(Swift.Int) -> :: swift_allocObject(0x4010, 24, 7)
// EXPECT structured * Closures.makeAdder(Swift.Int) -> :: + 0x10] = arg0
// EXPECT structured * captureBoth :: = partial apply forwarder for closure #1 () -> Swift.Int in Closures.captureBoth
// EXPECT structured * captureBoth :: + 0x10] = arg1
// EXPECT structured * captureBoth :: swift_allocObject(0x4038, 40, 7)
// EXPECT structured Onone partial apply forwarder for closure #1 (Swift.Int) -> Swift.Int in Closures.addK :: re:return closure #1
// EXPECT structured Onone partial apply forwarder for closure #1 (Swift.Int) -> Swift.Int in Closures.makeAdder :: re:return closure #1
// The deallocating deinit passes self in x20 to deinit (-Onone); the receiver
// is never dropped.
// EXPECT structured O,Osize Store.__deallocating_deinit :: swift_deallocClassInstance(self, 32, 7)
// FORBID structured * Store.__deallocating_deinit :: re:Store\.deinit\(\)
@inline(never) public func apply(_ f: (Int) -> Int, _ x: Int) -> Int { f(x) }
public func addK(_ k: Int, _ x: Int) -> Int { apply({ $0 &+ k }, x) }
@inline(never) public func makeAdder(_ k: Int) -> (Int) -> Int { { $0 &+ k &* 17 } }
public func useAdder(_ x: Int) -> Int { makeAdder(4)(x) }
public final class Store { public var f: (() -> Int)? = nil; public init() {} }
public func captureBoth(_ s: Store, _ a: Int, _ b: String) { s.f = { a &+ b.utf8.count } }
