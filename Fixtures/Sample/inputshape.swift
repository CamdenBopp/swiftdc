// Input shapes that are not an arm64 linked image: this source builds as an
// x86_64 dylib, an arm64 + x86_64 universal dylib, and a relocatable object.
//
// True behaviour: `sum4` adds four integers and `Tally.add` adds to a stored
// Int. On x86_64 `sum4`'s first instruction is `pushq %rbp`, bytes that decode
// as nonsense under an ARM64 decoder. In the object, `__objc_classlist[0]`
// holds 0 until the linker applies its relocation.
public func sum4(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Int {
    a &+ b &+ c &+ d
}

public final class Tally {
    public var total: Int
    public init(total: Int) { self.total = total }
    public func add(_ amount: Int) -> Int {
        total &+= amount
        return sum4(total, amount, 1, 2)
    }
}

public struct Pair {
    public var first: Int
    public var second: Int
}
