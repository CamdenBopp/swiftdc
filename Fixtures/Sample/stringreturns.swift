// A String travels in two registers, x0 and x1 (-O). A function returning
// one is read from both words at its `ret`, never from x0 alone:
// - `small()` is "ok": a small string, both words immediates;
// - `large()` is a literal over 15 bytes: x0 its count and flags, x1 its
//   object's address;
// - `Person.current()` is `self.name`: both words loaded from the one
//   String field of self;
// - `Person.forced()` is `self.nickname!`: both words of a String? field,
//   which are not `self.nickname` itself, so `return ?`;
// - `forward()` is `greeting()`'s String result, kept across a call, so
//   bound before the call and returned by name;
// - `fromLocal()` is `describe(&n)`'s result with nothing between: the
//   call itself is returned, and is no statement of its own;
// - `inner()` is the two words of `Box.make()`, a struct holding only a
//   String: the same bits, but that call's result is a Box, so `return
//   Box.make()` would be a different value, and it stays `return ?`;
// - `maybe()` is a String? (`.some("m")`), whose layout this does not
//   model: `return ?`;
// - `either(_:)` picks one of two literals: `flag ? "yes" : "no"`.
public final class Person {
    public var name: String
    public var reads = 0
    public var nickname: String?
    public init(name: String) { self.name = name }
    @inline(never) public func current() -> String {
        reads += 1
        return name
    }
    @inline(never) public func forced() -> String { nickname! }
}

public struct Box {
    public var text: String
    @inline(never) public static func make() -> Box { Box(text: String(repeating: "b", count: Int.random(in: 1...3))) }
}

public final class Counter { public var hits = 0; public init() {} }
public let counter = Counter()
@inline(never) public func sink() { counter.hits &+= 1 }

@inline(never) public func small() -> String { "ok" }
@inline(never) public func large() -> String { "a literal longer than fifteen bytes" }
@inline(never) public func greeting() -> String { String(repeating: "hi", count: Int.random(in: 1...3)) }
@inline(never) public func forward() -> String {
    let value = greeting()
    sink()
    return value
}
@inline(never) public func describe(_ n: inout Int) -> String {
    n += 1
    return String(repeating: "n", count: n)
}
@inline(never) public func fromLocal() -> String {
    var n = Int.random(in: 1...3)
    return describe(&n)
}
@inline(never) public func inner() -> String {
    let box = Box.make()
    sink()
    return box.text
}
@inline(never) public func maybe() -> String? { "m" }
@inline(never) public func either(_ flag: Bool) -> String { flag ? "yes" : "no" }
