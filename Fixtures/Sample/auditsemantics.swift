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
