// A stored-field shortcut, select and call result must retain the Int8 view.
public final class NarrowBox {
    public var wide: Int64 = 0
    public init() {}
    @inline(never) public func storeNarrow(_ x: Int64) -> Int8 {
        wide = x
        return Int8(truncatingIfNeeded: x)
    }
}
@inline(never) public func chooseNarrow(_ x: Int64, _ y: Int64) -> Int8 {
    Int8(truncatingIfNeeded: x < 0 ? x : y)
}
@inline(never) public func wideProducer(_ x: Int64) -> Int64 { x &+ 7 }
@inline(never) public func producerNarrow(_ x: Int64) -> Int8 {
    Int8(truncatingIfNeeded: wideProducer(x))
}
