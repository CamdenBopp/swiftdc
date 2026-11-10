// A requirement called on an opaque existential argument goes through the
// container's witness table: `ldp x19, x21, [x0, #0x18]` (metadata, table),
// the projected value in x20, `ldr x8, [x21, #8 * (k + 1)]`, and the
// metadata and table passed last. `measure(Square(3))` is 9 (requirement 0,
// area), `grow(Square(3), by: 4)` is 12 (requirement 1, scale). A
// class-bound protocol's existential is two registers, and Error's is a
// box: neither is this layout, and neither is named. The callers are in
// another module (existentialwitness_oracle.swift): a caller here lets the
// optimizer turn each existential into a generic specialization.
public protocol Shape {
    func area() -> Int
    func scale(_ k: Int) -> Int
}

public protocol Named: AnyObject { func name() -> Int }

public struct Square: Shape {
    public var side: Int
    public init(_ side: Int) { self.side = side }
    public func area() -> Int { side * side }
    public func scale(_ k: Int) -> Int { side * k }
}

public final class Tag: Named {
    public init() {}
    public func name() -> Int { 5 }
}

public struct Failure: Error { public init() {} }

@inline(never) public func measure(_ shape: any Shape) -> Int { shape.area() }
@inline(never) public func grow(_ shape: any Shape, by k: Int) -> Int { shape.scale(k) }
@inline(never) public func callName(_ named: any Named) -> Int { named.name() }
// A class-bound existential is two registers (object, table): `k` is x2.
@inline(never) public func callNameThen(_ named: any Named, _ k: Int) -> Int { named.name() &+ k }
@inline(never) public func describe(_ error: any Error) -> Int { error._code }

// A method's class-bound existential parameter: self in x20, the object in
// x0 and its table in x1, as for a free function.
public final class Registry {
    public var base: Int
    public init(_ base: Int) { self.base = base }
    @inline(never) public func lookup(_ named: any Named) -> Int { named.name() &+ base }
}
