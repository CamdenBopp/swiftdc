// A value struct of scalars from both register banks passes each field in
// the next register of its own bank, after the formal parameters
// (measured at -O):
//   Gauge.scaled():        level in x0, scale in d0, limit in w1;
//                          returns Double(level) * scale + Double(limit).
//   Gauge.scaledBy(k, x):  k in x0, x in d0, then level x1, scale d1,
//                          limit w2; returns Double(level - k) * (scale - x)
//                          + Double(limit).
//   Narrow.sum():          tag (Int8) in w0, count in x1: Int(tag) - count.
// Two fields sharing one 8-byte unit are merged into one register, and a
// fifth field passes the struct by address, so those decline:
//   Packed.diff():         a and b (Int32) both in x0: `lsr x8, x0, #32`.
//   Wide.sum():            five fields through x20.
public struct Gauge {
    public var level: Int
    public var scale: Double
    public var limit: Int32
}
public struct Narrow { public var tag: Int8; public var count: Int }
public struct Packed { public var a: Int32; public var b: Int32 }
public struct Wide { public var a: Int; public var b: Int; public var c: Int; public var d: Int; public var e: Int }

extension Gauge {
    @inline(never) public func scaled() -> Double { Double(level) * scale + Double(limit) }
    @inline(never) public func scaledBy(_ k: Int, _ x: Double) -> Double { Double(level &- k) * (scale - x) + Double(limit) }
}
extension Narrow { @inline(never) public func sum() -> Int { Int(tag) &- count } }
extension Packed { @inline(never) public func diff() -> Int32 { a &- b } }
extension Wide { @inline(never) public func sum() -> Int { a &- b &- c &- d &- e } }

// A struct parameter is passed the same way, before the parameters after
// it: `withGauge(_ g: Gauge, _ k: Int)` takes level in x0, scale in d0,
// limit in w1 and k in x2; returns Double(level + k) * scale.
@inline(never) public func withGauge(_ g: Gauge, _ k: Int) -> Double { Double(g.level &+ k) * g.scale }
