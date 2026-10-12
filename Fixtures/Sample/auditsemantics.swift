// Reductions of source-grounded audit failures: ordering and loop exits.
@inline(never) public func next(_ x: Int) -> Int { print("next", x); return x &+ 1 }
@inline(never) public func log(_ x: Int) { print("log", x) }

public func ordered(_ x: Int) -> Int {
    let value = next(x)
    log(x)
    return value
}

public func branched(_ x: Int) -> Int {
    let value = next(x)
    if x > 0 { log(x) }
    return value
}

public func adjacent(_ x: Int) -> Int { next(x) }

public func walk(_ values: [Int]) {
    for value in values { log(value) }
}

open class Counter {
    public init() {}
    open var value: Int = 0
    public func storeThenLog(_ x: Int) { value = x; log(x) }
}

// x20 parked for a value live across the call (here `b`, reused below)
// is a callee-saved home, not `self`: `keep` is a free function.
@inline(never) public func keepBox(_ o: AnyObject, _ n: Int) { print(o, n) }
@inline(never) public func makeBox() -> AnyObject { [Int]() as AnyObject }
public func parked(_ a: AnyObject) -> [AnyObject] {
    let b = makeBox()
    keepBox(b, 3)
    return [a, b, a]
}

// Callees that take nothing in x0–x7, each called while x0 holds a value:
// a class instance getter (self in x20), a static getter on a struct (the
// metatype rides in x20) and a private method (named `(tick in _HASH)`).
public final class Gauge {
    var raw: Int = 3
    public var reading: Int { @inline(never) get { raw &* 2 } }
    @inline(never) private func tick() { log(raw &+ 1) }
    public func run() -> Int {
        let a = next(1)
        tick()
        return a &+ reading
    }
}
public struct Units { public static var scale: Int { @inline(never) get { Int.random(in: 1..<9) } } }
public func scaled(_ g: Gauge) -> Int {
    let a = next(2)
    return a &* Units.scale &+ g.reading
}

// An Int-returning call compared with 1 or tested on bit 0 is not a truth
// test; a Bool-returning one is.
@inline(never) public func level(_ n: Int) -> Int { n &* 3 }
@inline(never) public func ready(_ n: Int) -> Bool { n > 4 }
public func isOne(_ n: Int) { if level(n) == 1 { log(1) }; log(0) }
public func isEven(_ n: Int) { if level(n) % 2 == 0 { log(2) }; log(0) }
public func isReady(_ n: Int) { if ready(n) { log(3) }; log(0) }
