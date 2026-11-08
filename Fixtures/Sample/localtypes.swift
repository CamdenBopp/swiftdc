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

// A local class: its vtable names its methods in a stripped binary, and
// the name must not place it in `Outer`.
extension Outer {
    public func makeCounter() -> AnyObject {
        class LocalCounter {
            var count = 0
            @inline(never) func bump() -> Int { count += 1; return count }
        }
        class LocalDouble: LocalCounter {
            @inline(never) override func bump() -> Int { count += 2; return count }
        }
        let counter: LocalCounter = name.isEmpty ? LocalCounter() : LocalDouble()
        _ = counter.bump()
        return counter
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

// A private class: its context is its file, and the renderer names it with
// the private discriminator when it knows one.
private class PrivateBox {
    var value = 0
    @inline(never) func grow() -> Int { value += 1; return value }
}
private final class PrivateBigBox: PrivateBox {
    @inline(never) override func grow() -> Int { value += 10; return value }
}
public func useBox(_ big: Bool) -> Int { (big ? PrivateBigBox() : PrivateBox()).grow() }

// Class members in a vtable: `kind` and `make()` are not instance members,
// and a stripped binary's names must say `static`.
open class Registry {
    public init() {}
    open class var kind: String { "base" }
    open class func make() -> Registry { Registry() }
    open func describe() -> String { "registry" }
}
open class SpecialRegistry: Registry {
    open override class var kind: String { "special" }
    open override class func make() -> Registry { SpecialRegistry() }
}

public struct Holder {
    public var source: (any Source<String>)?
    public var pair: (any Source<Int>)?
    public init() {}
}
