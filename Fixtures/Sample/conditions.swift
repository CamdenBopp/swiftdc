// Branch conditions whose flags do not come from a plain `cmp`/`tst`, and
// unsigned range checks. Reduced from an app audit (2026-10-12); each
// comment gives the lowering at -O / -Osize and the true condition.

@inline(never) public func ga() { print("a") }
@inline(never) public func gc() { print("c") }

// `cmp x1, x0; ccmp x0, x2, #0, le; b.lt`: ga() iff flag || (lo <= x && x < hi).
public func touches(_ x: Int, _ lo: Int, _ hi: Int, _ flag: Bool) {
    if flag || (lo <= x && x < hi) { ga() }
    gc()
}

// `cmp x0, #5; fcsel …; fcmp d0, d2; b.pl`: the branch tests a Double.
public func selThenFloat(_ a: Int, _ x: Double, _ y: Double, _ z: Double) {
    let k = a > 5 ? x : y
    if k < z { ga() }
    gc()
}

// String `!=`: `cmp x0, x21; ccmp x22, x1, #0, eq; b.eq` compares both words.
public final class Model {
    public var status: String = ""
    public func setStatus(_ v: String) {
        if status != v { ga() }
        status = v
    }
}

// `ldr x8, [x0, #0x18]; sub x8, x8, #10; cmp x8, #10; b.hi`: ga() iff
// 10 <= p[3] <= 20, an UNSIGNED compare of p[3] - 10.
public func rng(_ p: UnsafePointer<Int>) {
    if (10...20).contains(p[3]) { ga() } else { gc() }
}
