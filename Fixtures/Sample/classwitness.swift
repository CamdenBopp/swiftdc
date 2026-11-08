// A generic class's methods reach its type parameters' value witnesses
// through self's metadata (-O): `ldr x21, [x20]` loads self's isa, `ldr x2,
// [x21, #0x58]` the generic argument B (Holder's arguments start at word
// 10, the descriptor's immediate-members offset: A at 0x50, B at 0x58),
// `ldur x8, [x2, #-0x8]; ldr x8, [x8, #0x18]` B's assignWithCopy:
// `self.b = x` is `assignWithCopy value witness for B(…)`.
public final class Holder<A, B> {
    var a: A; var b: B
    public init(_ a: A, _ b: B) { self.a = a; self.b = b }
    @inline(never) public func setB(_ x: B) { b = x }
    @inline(never) public func setA(_ x: A) { a = x }
}
// A class nested in a generic type: its metadata holds Outer's T and then
// its own U, which its members' names print as A1, not B, so a witness
// through U's metadata is not named by position.
public struct Outer<T> {
    public final class Inner<U> {
        var u: U
        public init(_ u: U) { self.u = u }
        @inline(never) public func setU(_ x: U) { u = x }
    }
}
