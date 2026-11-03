// A generic class's methods call a requirement of a type parameter's
// conformance through the witness table in self's metadata (-O). Gauge<M:
// Meter>'s key arguments start at the descriptor's immediate-members offset:
// M's metadata, then the `M: Meter` witness table one word later. A witness
// table's word 0 is its conformance descriptor and requirement N is word N+1
// (WitnessTableFirstRequirementOffset), so `ldr x1, [isa, #wt]; ldr x9, [x1,
// #8*(N+1)]; blr x9` calls Meter's requirement N on M: `m.reading()` is
// `Meter.reading() witness for A`.
public protocol Meter {
    func reading() -> Int
    func scaled(by k: Int) -> Int
    var label: Int { get }
    // An async requirement's slot holds an async function pointer record,
    // and a mutable property's modify is a coroutine: neither is called as
    // a plain function through its slot, and neither is named.
    func fetch() async -> Int
    var level: Int { get set }
    // A tuple result holding a generic value comes back through buffers
    // that take x0 first: the call is named, and its arguments are not read.
    func split<T: Equatable>(_ t: T) -> (T, Int)
}

// A refined protocol reaches Meter's requirements through its base-protocol
// slot (requirement 0 of Precise): the call is two tables away, through a
// requirement that is no method, and is not named by position. Declared
// here, its descriptor follows Meter's, so a word past Meter's requirement
// count reads Precise's header.
public protocol Precise: Meter {
    func error() -> Int
}

public final class Gauge<M: Meter> {
    var m: M
    public init(_ m: M) { self.m = m }
    @inline(never) public func reading() -> Int { m.reading() }
    @inline(never) public func scaled(_ k: Int) -> Int { m.scaled(by: k) }
    @inline(never) public func label() -> Int { m.label }
    @inline(never) public func bump() { m.level += 1 }
    @inline(never) public func split(_ k: Int) -> Int { m.split(k).1 }
}

// Two parameters, the second constrained: its table follows both
// parameters' metadata (A at word 0 of the arguments, B at 1, B: Meter at 2).
public final class Pair<A, B: Meter> {
    var a: A; var b: B
    public init(_ a: A, _ b: B) { self.a = a; self.b = b }
    @inline(never) public func reading() -> Int { b.reading() }
}

public final class Lab<P: Precise> {
    var p: P
    public init(_ p: P) { self.p = p }
    @inline(never) public func reading() -> Int { p.reading() }
    @inline(never) public func error() -> Int { p.error() }
}

// A protocol defined in another image: its requirements are not in this
// one, so a call through its table is not named here.
public final class Keyed<K: Hashable> {
    var k: K
    public init(_ k: K) { self.k = k }
    @inline(never) public func hash() -> Int { k.hashValue }
}
