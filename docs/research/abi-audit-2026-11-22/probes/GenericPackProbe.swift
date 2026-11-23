public final class PackBox<A, each T> {
    public init() {}

    @inline(never)
    public func typeOfA() -> Any.Type { A.self }

    @inline(never)
    public func identityA(_ value: A) -> A { value }
}
