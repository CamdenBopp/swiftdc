// A field is loaded, then overwritten, then its OLD value is tested:
// `ldr x0, [x20, #0x10]; str xzr, [x20, #0x10]; cbz x0`. Named by the field
// at the test, the condition reads the new value, `self.v = 0; if (self.v
// != 0)`, which is never true.
//
// True behaviour: take() reads v, sets v to 0, and calls sink(old) when the
// old value was not 0. peek() reads v, calls bump(), which changes v, and
// calls sink(old) when the old value was not 0. Chain.forward() tests
// next for nil straight after loading it, so the test reads self.next. Chain's deinit releases `next` (an Optional) when it
// is not nil.
@inline(never) public func sink(_ x: Int) { print(x) }

public final class Cell {
    public var v: Int = 5
    public init() {}
    @inline(never) public func take() {
        let old = v
        v = 0
        if old != 0 { sink(old) }
    }
    @inline(never) public func bump() { v &+= 1 }
    @inline(never) public func peek() {
        let old = v
        bump()
        if old != 0 { sink(old) }
    }
}

@inline(never) public func visit(_ c: Chain) { print(ObjectIdentifier(c)) }

public final class Chain {
    public var next: Chain?
    public init(next: Chain?) { self.next = next }
    @inline(never) public func forward() {
        if let n = next { visit(n) }
    }
}
