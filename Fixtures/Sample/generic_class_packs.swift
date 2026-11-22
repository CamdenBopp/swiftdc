// Pack shape lengths precede generic metadata in a class's key arguments.
// identityA copies A at every optimization level: the pack's length word
// must not shift its value-witness name to B. PlainBox is the scalar control.
public final class PackBox<A, each T> {
    public init() {}

    @inline(never)
    public func typeOfA() -> Any.Type { A.self }

    @inline(never)
    public func identityA(_ value: A) -> A { value }
}

public final class PlainBox<A, B> {
    public init() {}

    @inline(never)
    public func typeOfA() -> Any.Type { A.self }

    @inline(never)
    public func typeOfB() -> Any.Type { B.self }

    @inline(never)
    public func identityA(_ value: A) -> A { value }
}
