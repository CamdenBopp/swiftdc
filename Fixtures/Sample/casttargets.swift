// Dynamic casts whose target type has a parenthesis in it, or is generic
// over the caller's own parameter (-O and -Onone).
//
// The runtime cast takes the target's type metadata. A concrete target is
// one complete type, whatever its spelling holds. A target built from the
// caller's generic parameter comes from the type's metadata accessor, whose
// arguments are that parameter: the type's bare name is not the target.
// Each function's true behaviour is its source.

public final class Shelf<T> { public init() {} }
public final class Plain { public init() {} }

// The target is Shelf<(Int, Int)>: a tuple inside the generic argument.
@inline(never) public func isTupleShelf(_ x: AnyObject) -> Bool { x is Shelf<(Int, Int)> }
// The target is Shelf<(Int) -> Int>: a function type inside it.
@inline(never) public func asFunctionShelf(_ x: AnyObject) -> Shelf<(Int) -> Int>? { x as? Shelf<(Int) -> Int> }
// The control: no parenthesis in the target.
@inline(never) public func asIntShelf(_ x: AnyObject) -> Shelf<Int>? { x as? Shelf<Int> }
// A non-generic class: its accessor takes nothing.
@inline(never) public func asPlain(_ x: AnyObject) -> Plain? { x as? Plain }
// The target is a tuple.
@inline(never) public func asTuple(_ x: Any) -> (Int, String)? { x as? (Int, String) }
// The target is Shelf<T> for the caller's T: not nameable here.
@inline(never) public func asGenericShelf<T>(_ x: Any, _: T.Type) -> Shelf<T>? { x as? Shelf<T> }
