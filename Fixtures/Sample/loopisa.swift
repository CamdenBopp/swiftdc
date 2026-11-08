// A generic class's method loads self's isa before a loop and reads a
// witness table through it after (-O, library evolution): `ldr x22, [x20];
// loop: bl step; tbnz w0, loop; ldr x1, [x22, #wt]; ldr x9, [x1, #k]; blr
// x9`. At the loop header x22 is self's field 0 from the entry and a
// snapshot of it from the back edge (the call may write self's fields, but
// not its class), and self stays in x20 on both: the isa is still self's,
// so `c.close()` is `Link.close() witness for A`.
public protocol Link {
    func close() throws
}

public final class Listener<C: Link> {
    var c: C
    var n: Int = 0
    public init(_ c: C) { self.c = c }
    @inline(never) func step() -> Bool { n += 1; return n < 10 }
    @inline(never) public func run() throws {
        while step() {}
        try c.close()
    }
}
