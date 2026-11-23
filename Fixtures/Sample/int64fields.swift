// A value struct's Int64 and UInt64 fields in registers (-O).
//
// A small struct of scalars is passed exploded, one register per field.
// `Int64` and `UInt64` lower to one i64 each, exactly as `Int` and `UInt`
// do, so `{ a: UInt64, b: UInt64 }` arrives in x0 and x1 and the formal
// after it in x2. Each function's true behaviour is its source.

public struct Wide { public var a: UInt64; public var b: UInt64 }
public struct Signed { public var a: Int64; public var b: Int64 }
public struct Mixed { public var n: Int; public var raw: UInt64; public var d: Double }
public struct Flags: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}
// The control: the same shape with `Int`, which was always read.
public struct Words { public var a: Int; public var b: Int }

// `msub x0, x2, x1, x0`: a - k * b
@inline(never) public func wideCombine(_ w: Wide, _ k: UInt64) -> UInt64 { w.a &- k &* w.b }
// `cmp x0, x1; cset lt`: signed, a < b
@inline(never) public func signedLess(_ s: Signed) -> Bool { s.a < s.b }
// `madd x0, x1, x0, x2`-shaped: n * k + raw; d rides in d0 and is not read
@inline(never) public func mixedSum(_ m: Mixed, _ k: Int) -> UInt64 { UInt64(truncatingIfNeeded: m.n &* k) &+ m.raw }
// `orr x0, x1, x0`: the union's raw value
@inline(never) public func flagsUnion(_ f: Flags, _ g: Flags) -> UInt64 { f.rawValue | g.rawValue }
// `madd x0, x2, x1, x0`: a + k * b
@inline(never) public func wordsCombine(_ w: Words, _ k: Int) -> Int { w.a &+ k &* w.b }

extension Wide {
    // self exploded in x0, x1; the formal in x2: (a ^ b) + k
    @inline(never) public func mix(_ k: UInt64) -> UInt64 { (a ^ b) &+ k }
}
