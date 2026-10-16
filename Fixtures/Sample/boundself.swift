// A call whose result is bound (`let r0 = …`) because its indirect result
// is read back word by word (-O): `make()` returns a five-word struct
// through x8, and `readWide` reads two of its words. The binding is the
// call, so it names `self`. True behaviour: returns w.a &+ w.e of
// h.make(), self = h.
public struct Wide {
    public var a, b, c, d, e: Int
    public init(a: Int, b: Int, c: Int, d: Int, e: Int) { self.a = a; self.b = b; self.c = c; self.d = d; self.e = e }
}
public final class Holder {
    public var wide: Wide
    public init(_ w: Wide) { wide = w }
    @inline(never) public func make() -> Wide { wide }
}
public func readWide(_ h: Holder) -> Int { let w = h.make(); return w.a &+ w.e }
