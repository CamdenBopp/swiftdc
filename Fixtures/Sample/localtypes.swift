// Types declared inside a function sit under an anonymous context
// descriptor, which an optimized build records without a name. Rendering
// skipped such a context, so `Local` printed as `LocalTypes.Outer.Local`,
// a member type of `Outer`, which it is not. Constrained existential fields
// (`any Source<String>`) print through their extended existential shape.
public protocol Source<Element> { associatedtype Element; func next() -> Element? }

public struct Outer {
    public var name = ""
    public init() {}
    public func make() -> Any {
        struct Local { var count: Int; var label: String }
        return Local(count: 1, label: name)
    }
}

public func freeMake() -> Any {
    struct FreeLocal { var flag: Bool }
    return FreeLocal(flag: true)
}

// A local type in a private function: the renderer prints its private
// discriminator, `(PrivateLocal in _H)`, under an unknown context.
private func privateMake() -> Any {
    struct PrivateLocal { var level: Int }
    return PrivateLocal(level: 2)
}
public func callPrivate() -> Any { privateMake() }

public struct Holder {
    public var source: (any Source<String>)?
    public var pair: (any Source<Int>)?
    public init() {}
}
