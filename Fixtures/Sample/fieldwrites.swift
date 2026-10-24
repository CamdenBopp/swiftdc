// Stores into a final class's fields that do not fill one field with one
// register. `rename` stores the String "a  b" with `stp x8, x9, [x20,
// #0x10]`: the low word is the bytes "a  b" (0x62202061), the high word the
// small-string count and flags, and neither alone is the field's value.
// `retitle` stores a large literal the same way (its count and flags, then
// its object address), `relabel` a String parameter whose words are not
// known, and `setHalf` writes only the first word of the two-word `pair`.
// `collapse` copies one two-word field into another (`ldp x8, x9; stp x8,
// x9`), `mirror` a four-word struct in two-register pieces, and
// `copyFirst` one word of one field into one word of another, and `clear`
// zeroes a two-word field with `stp xzr, xzr`. `secondOfPair` reads only
// the second word of `pair` (`ldr x0, [x20, #0x28]`).
//
// True behaviour: name becomes "a  b", then "a literal past fifteen bytes",
// then the argument; pair.a becomes the argument and pair.b is unchanged;
// end becomes start, back becomes front, back.a becomes front.a, and start
// becomes all zeros; secondOfPair returns pair.b.
public struct FieldPair { public var a: Int; public var b: Int }

public struct FieldQuad { public var a: Int; public var b: Int; public var c: Int; public var d: Int }

public final class FieldWrites {
    public var name: String = ""
    public var pair = FieldPair(a: 0, b: 0)
    public var start = FieldPair(a: 0, b: 0)
    public var end = FieldPair(a: 0, b: 0)
    public var front = FieldQuad(a: 0, b: 0, c: 0, d: 0)
    public var back = FieldQuad(a: 0, b: 0, c: 0, d: 0)
    public init() {}
    @inline(never) public func rename() { name = "a  b" }
    @inline(never) public func retitle() { name = "a literal past fifteen bytes" }
    @inline(never) public func relabel(_ s: String) { name = s }
    @inline(never) public func setHalf(_ x: Int) { pair.a = x }
    @inline(never) public func collapse() { end = start }
    @inline(never) public func mirror() { back = front }
    @inline(never) public func copyFirst() { back.a = front.a }
    @inline(never) public func clear() { start = FieldPair(a: 0, b: 0) }
    @inline(never) public func secondOfPair() -> Int { pair.b }
}
