// Witnesses of another image's protocols that a stripped image's metadata
// can read but must not name (-O, strip -x copy).
//
// True behaviour: `Box<A>`'s `==` witness is `protocol witness for static
// Swift.Equatable.== infix(A, A) -> Swift.Bool in conformance
// WitnessNaming.Box<A> : …`; a name built from the type's descriptor reads
// `WitnessNaming.Box` and is not that symbol, so it is declined. `Mode` and
// the private `Key` have identical witness bodies, which the linker folds
// onto one address; `Key` has no name metadata can qualify, so the shared
// body is not credited to `Mode` alone.
public struct Box<T: Equatable>: Equatable {
    public var value: T
}

public enum Mode: Hashable {
    case on, off
}

private enum Key: Hashable {
    case on, off
}

@inline(never)
func same<E: Equatable>(_ a: E, _ b: E) -> Bool { a == b }

public func boxesMatch(_ a: Int, _ b: Int) -> Bool {
    same(Box(value: a), Box(value: b))
}

public func hashables() -> [AnyHashable] {
    [AnyHashable(Mode.on), AnyHashable(Key.off)]
}
