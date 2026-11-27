// The client allocates an MAKlass itself: it asks the imported accessor
// for the metadata while its own second and third formals are still in x1
// and x2. The accessor takes the request (0) only.
//
// foreignMake(a, b, c) = MAKlass(n: a)
// foreignOnly(a) = MAKlass(n: a &+ 1): nothing is known in x1 at the
// accessor.
// localMake(a, b, c) = MALocal(n: a), through this image's own accessor.
import MetaAccessorKit

public final class MALocal {
    public var n: Int
    public init(n: Int) { self.n = n }
}

@inline(never) public func foreignMake(_ a: Int, _ b: Int, _ c: Int) -> MAKlass {
    MAKlass(n: a)
}

@inline(never) public func localMake(_ a: Int, _ b: Int, _ c: Int) -> MALocal {
    MALocal(n: a)
}

@inline(never) public func foreignOnly(_ a: Int) -> MAKlass {
    MAKlass(n: a &+ 1)
}
