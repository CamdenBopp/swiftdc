// Two classes of another image, neither generic.
public final class CCOne {
    public var n: Int
    public init(n: Int) { self.n = n }
}

public final class CCTwo {
    public var n: Int
    public init(n: Int) { self.n = n }
}

// ccMake(k, n): a CCOne when k is even, a CCTwo when odd.
@inline(never) public func ccMake(_ k: Int, _ n: Int) -> AnyObject {
    k & 1 == 0 ? CCOne(n: n) : CCTwo(n: n)
}
