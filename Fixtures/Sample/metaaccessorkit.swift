// A class of another image, not generic: its metadata accessor takes the
// request word and nothing else. The initializer is inlinable, so a client
// allocates the object itself and asks this image for the metadata.
public final class MAKlass {
    public var n: Int
    @inlinable public init(n: Int) { self.n = n }
}
