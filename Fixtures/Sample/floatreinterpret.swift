// An integer's bits read as a float, and a float's bits read as an integer,
// with and without an `fmov`. Built at -O and -Onone; the lowering and the
// true behaviour are written per function.

@inline(never) func sd(_ x: Double) { print(x) }
@inline(never) func sf(_ x: Float) { print(x) }
@inline(never) func sink(_ x: Int) { print(x) }

// -O: `fmov d0, x0; fadd d0, d0, d0`. Passes the Double whose bits are i,
// doubled: a float add, not the integer `i + i`.
@inline(never) public func doubleFromBits(_ i: UInt64) { sd(Double(bitPattern: i) * 2.0) }

// -O: `fmov s0, w0; fadd s0, s0, s0`. The Float form.
@inline(never) public func floatFromBits(_ i: UInt32) { sf(Float(bitPattern: i) * 2.0) }

// -O: `fmov d0, x0; fmov d1, #1.0; fadd d0, d0, d1`. -Onone spills the Int and
// reloads it into a float register, with no `fmov`: `str x0, [sp]; ldr d0,
// [sp]`. Either way the add is a float add of the reinterpreted bits.
@inline(never) public func castFromInt(_ i: Int) { sd(unsafeBitCast(i, to: Double.self) + 1.0) }

// -Onone spills the Double and reloads it into a general register:
// `str d0, [sp]; ldr x9, [sp]; mov x8, #0; subs x8, x8, x9; subs x8, x8,
// #1; subs x8, x8, #7; b.ne`. `~bits` lowered to `0 - bits - 1`, an integer
// subtraction; taken iff the complemented bits are not 7.
@inline(never) public func complement(_ a: Double) {
    if ~unsafeBitCast(a, to: Int.self) == 7 { sink(3) } else { sink(4) }
}

// -Onone copies a Float field through a general register, twice: `ldr w8,
// [x20]; str w8, [sp, #0xc]; ldr s0, [sp, #0xc]`. It is the declared Float, so
// the product is `scale * scale`, with no reinterpretation.
public struct Labelled {
    public var scale: Float
    public var name: String
    public var other: String
    public var third: String
    public var squared: Float { scale * scale }
}
