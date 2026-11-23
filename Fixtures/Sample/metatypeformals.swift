// A metatype passed as a source argument (-O and -Onone).
//
// A metatype formal is one word holding type metadata, in its own
// position among the formals. A generic function also takes its type
// parameters' metadata, after the formals: that is plumbing, the formal
// is not. Each caller's true behaviour is its source.

public struct Crate<T> { public var value: T }
public final class Kind {}

@inline(never) public func keep<T>(_ t: T.Type) -> T.Type { t }
@inline(never) public func sized<T>(_ n: Int, _ t: T.Type) -> Int { n &+ MemoryLayout<T>.size }
@inline(never) public func describe(_ t: Any.Type) -> Int { ObjectIdentifier(t).hashValue }
@inline(never) public func leading(_ t: Kind.Type, _ n: Int) -> Int { n &+ ObjectIdentifier(t).hashValue }
@inline(never) public func trailing(_ n: Int, _ t: Any.Type) -> Int { n &+ ObjectIdentifier(t).hashValue }

// A generic formal: x0 is the metatype, and T's metadata follows it.
@inline(never) public func useKeep() -> Int.Type { keep(Int.self) }
// 7, then the metatype, then T's metadata.
@inline(never) public func useSized() -> Int { sized(7, Crate<Int>.self) }
// The only argument is a metatype.
@inline(never) public func useDescribe() -> Int { describe(Crate<Int>.self) }
// A class metatype before a value: never the trailing position.
@inline(never) public func useLeading() -> Int { leading(Kind.self, 5) }
// A metatype in the last position.
@inline(never) public func useTrailing() -> Int { trailing(9, String.self) }
// One call's result bound, the other nested in the return.
@inline(never) public func useBoth() -> Int { trailing(9, String.self) &+ describe(Int.self) }
