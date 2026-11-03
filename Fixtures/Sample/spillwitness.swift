// A generic class method keeps self's isa in a callee-saved register
// across calls (-O): `ldr x27, [x20]`, then `__chkstk_darwin` calls that
// size the stack buffers, then `ldr x23, [x27, #0x58]` reads the class's
// generic argument B (Store's arguments start at 0x50: A at 0x50, B at
// 0x58). The register still holds the isa after the calls, and metadata
// never changes, so `ldur x22, [x23, #-0x8]; ldr x8, [x22, #0x30]; blr x8`
// is B's getEnumTagSinglePayload: `table[k]` yields a B?.
@inline(never) public func touch() { }
public final class Store<K: Hashable, V> {
    var table: [K: V] = [:]
    var last: V?
    public init() {}
    @inline(never) public func put(_ k: K, _ v: V) {
        if let old = table[k] { last = old }
        touch()
        table[k] = v
        touch()
        last = v
    }
}
