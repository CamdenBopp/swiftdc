// Awaits whose callee is reached through a register (closure, witness,
// class method): the suspension is a `br xN`, not a call to a symbol.
public protocol Source { func next() async -> Int }

@inline(never) public func sideEffect(_ x: Int) { print("sideEffect", x) }

public func viaClosure(_ body: () async -> Int) async -> Int {
    sideEffect(1)
    let v = await body()
    sideEffect(v)
    return 2
}

public func viaProtocol(_ s: any Source) async -> Int {
    sideEffect(1)
    let v = await s.next()
    sideEffect(v)
    return 2
}

open class Base {
    public init() {}
    open func fetch() async -> Int { 7 }
}

public func viaClass(_ b: Base) async -> Int {
    sideEffect(1)
    let v = await b.fetch()
    sideEffect(v)
    return 2
}
