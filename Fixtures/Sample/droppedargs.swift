// Specializations whose registers are not the printed signature's: a generic
// specialization that drops arguments (`Tt`) and a closure-propagated one.
// Built at -O and -Osize; at -Onone nothing here is specialized.
//
// Register truth is from `swiftc -O -emit-ir`, and every shape below was read
// there. The mangled index of a `Tt` clause counts SIL arguments, so it is not
// the formal's position: an indirect result comes first, and a tuple formal
// counts once per element.

// `Ttg5`: `(i64 a)`. Returns a + 1.
@inline(never) func meta<T>(_ t: T.Type, _ a: Int) -> Int { a &+ MemoryLayout<T>.stride }
public func useMeta(_ z: Int) -> Int { meta(Int8.self, z) &+ 1 }
// A tail call for the same result is a return.
public func useMetaTail(_ z: Int) -> Int { meta(Int16.self, z) }

// `Tt1g5`, the metatype last: `(i64 a, i64 b)`. Returns a * 3 + b + 2.
@inline(never) func last<T>(_ a: Int, _ b: Int, _ t: T.Type) -> Int { a &* 3 &+ b &+ MemoryLayout<T>.size }
public func useLast(_ a: Int, _ b: Int) -> Int { last(a, b, Int16.self) }

// The only parameter dropped: `()`. Returns 9.
@inline(never) func only<T>(_ t: T.Type) -> Int { MemoryLayout<T>.size &+ 5 }
public func useOnly() -> Int { only(Int32.self) }

// `Ttt1g5`, two dropped: `(i64 a, i64 b)`. Returns a - b + 3.
@inline(never) func two<T, U>(_ t: T.Type, _ a: Int, _ u: U.Type, _ b: Int) -> Int {
    a &- b &+ MemoryLayout<T>.size &+ MemoryLayout<U>.size
}
public func useTwo(_ a: Int, _ b: Int) -> Int { two(Int8.self, a, Int16.self, b) }

// A float survivor: `(double d, i64 a)`. arg0 is the Double, arg1 the Int.
@inline(never) func float<T>(_ t: T.Type, _ d: Double, _ a: Int) -> Double {
    d * 2 + Double(a) + Double(MemoryLayout<T>.size)
}
public func useFloat(_ d: Double, _ a: Int) -> Double { float(Int8.self, d, a) }

// `Tt0g5`: the `@out T` is SIL argument 0, the metatype 1, so index 1 is not
// the Int. `(i64 a, double v)` returning double.
@inline(never) func genericResult<T>(_ t: T.Type, _ a: Int, _ v: T) -> T { print(a); return v }
public func useGenericResult(_ k: Int, _ d: Double) -> Double { genericResult(Double.self, k, d) + 1 }

// `Tt1g5`: the tuple formal takes SIL arguments 0 and 1. `(i64, i64, i64 a)`.
@inline(never) func tupled<T>(_ p: (Int, Int), _ t: T.Type, _ a: Int) -> Int {
    p.0 &+ p.1 &* a &+ MemoryLayout<T>.size
}
public func useTupled(_ x: Int, _ a: Int) -> Int { tupled((x, x), Int8.self, a) }

// Only one of two indirect results converts, and a buffer stays in x0:
// `(ptr, i64 a, i64 v)` returning i64.
@inline(never) func pair<T>(_ t: T.Type, _ a: Int, _ v: T) -> (T, T) { print(a); return (v, v) }
public func usePair(_ k: Int) -> Int { let (x, y) = pair(Int.self, k, k); return x &+ y }

// An argument label names the printed formal: `(i64 count)`.
@inline(never) func labeled<T>(of t: T.Type, count: Int) -> Int { count &* 4 &+ MemoryLayout<T>.size }
public func useLabeled(_ n: Int) -> Int { labeled(of: Int8.self, count: n) }

// A method: `self` follows the formals, `(i64 a, i64 self.v)`.
public struct Holder {
    var v: Int
    @inline(never) public func method<T>(_ t: T.Type, _ a: Int) -> Int { a &+ v &+ MemoryLayout<T>.size }
}
public func useHolder(_ s: Holder, _ a: Int) -> Int { s.method(Int8.self, a) }

// A struct result may be `@out`, so the index cannot be mapped to a formal and
// the printed `(A.Type, Swift.Int, Swift.Int)` stands for nothing: `(i64 a, i64 b)`
// where the printed list has b at x2 and calls x1 its second parameter.
@inline(never) func keyed<T>(_ t: T.Type, _ a: Int, _ b: Int) -> Holder { Holder(v: a &* 5 &- b &+ MemoryLayout<T>.size) }
public func useKeyed(_ a: Int, _ b: Int) -> Int { keyed(Int8.self, a, b).v }
// c stays in x2 across the call, where the printed list has a third parameter.
public func useKeyedThenAdd(_ a: Int, _ b: Int, _ c: Int) -> Int { keyed(Int8.self, a, b).v &+ c }

// Each parameter query indexes the real list, not the printed one.
// `(i1 flag, i64 a)`.
@inline(never) func chosen<T>(_ t: T.Type, _ flag: Bool, _ a: Int) -> Int { flag ? a : MemoryLayout<T>.size }
public func useChosen(_ flag: Bool, _ a: Int) -> Int { chosen(Int8.self, flag, a) }
// `(i64 a, i64 b)`: an unsigned compare.
@inline(never) func below<T>(_ t: T.Type, _ a: UInt, _ b: UInt) -> Int { a < b ? MemoryLayout<T>.size : 0 }
public func useBelow(_ a: UInt, _ b: UInt) -> Int { below(Int8.self, a, b) }
public enum Mode { case first, second, third }
// `(i8 m)`.
@inline(never) func moded<T>(_ t: T.Type, _ m: Mode) -> Int { m == .second ? MemoryLayout<T>.size : 7 }
public func useModed(_ m: Mode) -> Int { moded(Int8.self, m) }

// A specialization's own tail call is a return: `(i64 a)`.
@inline(never) public func helper(_ a: Int) -> Int { a &* 11 }
@inline(never) func tails<T>(_ t: T.Type, _ a: Int) -> Int { helper(a) }
public func useTails(_ a: Int) -> Int { tails(Double.self, a) &+ 1 }

// A static's and an allocator's own thin metatype go too, past the formals:
// `Tt1g5` is index 2, and each formal stays where the name prints it.
// `(i64 a, i64 b)`.
public struct Pack<T> {
    var n: Int
    @inline(never) static func combine(_ a: Int, _ b: Int) -> Int { a &* 2 &- b &+ MemoryLayout<T>.size }
    @inline(never) init(count a: Int, scale b: Int) { n = a &* b &+ MemoryLayout<T>.size }
}
public func useCombine(_ a: Int, _ b: Int) -> Int { Pack<Int8>.combine(a, b) }
public func usePack(_ a: Int, _ b: Int) -> Int { Pack<Int8>(count: a, scale: b).n }
// A generic static: `Tt2g5` is its metatype alone, `(i64 a, i64 b, i8 v)`, and
// `Ttt2g5` the metatype formal as well, `(i64 a, i64 b)`.
enum Scale {
    @inline(never) static func by<T: FixedWidthInteger>(_ a: Int, _ b: Int, _ v: T) -> Int {
        a &* 9 &- b &+ Int(truncatingIfNeeded: v)
    }
    @inline(never) static func of<T>(_ t: T.Type, _ a: Int, _ b: Int) -> Int { a &* 9 &- b &+ MemoryLayout<T>.size }
}
public func useScaleBy(_ a: Int, _ b: Int) -> Int { Scale.by(a, b, Int8(3)) }
public func useScaleOf(_ a: Int, _ b: Int) -> Int { Scale.of(Int8.self, a, b) }

// `Tf1nc_n` over `Ttg5`: `(i64 x, i64 y)`. Returns y * x + 8.
@inline(never) func apply<T>(_ t: T.Type, _ x: Int, _ f: (Int) -> Int) -> Int { f(x) &+ MemoryLayout<T>.size }
public func useApply(_ y: Int) -> Int { apply(Int.self, y) { $0 &* y } }
// No capture: `(i64 x)`. Returns x + 18.
public func useApplyNoCapture(_ y: Int) -> Int { apply(String.self, y) { $0 &+ 2 } }

// `Tf1nc_n` of a plain function.
@inline(never) func run(_ x: Int, _ f: (Int) -> Int) -> Int { f(x) &+ 1 }
// `(i64 x, double d)`.
public func captureDouble(_ y: Int, _ d: Double) -> Int { run(y) { $0 &+ Int(d) } }
// The same clause, the same printed `Swift.Double`: `(i64 x, ptr d)`.
public func captureDoubleVar(_ y: Int) -> Int {
    var d = 1.5
    let r = run(y) { d += 1; return $0 &+ Int(d) }
    return r &+ Int(d)
}
// k stays in x1 across the call. The body reads x0 and d0, and the printed
// list's closure has a place for it.
public func captureDoubleThenAdd(_ y: Int, _ k: Int, _ d: Double) -> Int { run(y) { $0 &* Int(d) } &+ k }
// A String's two words, then an Int: `(i64 x, i64, ptr, i64 k)`.
public func captureString(_ y: Int, _ s: String, _ k: Int) -> Int { run(y) { $0 &+ s.utf8.count &* k } }
public final class Counter { var v = 3 }
// A class reference: `(i64 x, ptr c)`.
public func captureClass(_ y: Int, _ c: Counter) -> Int { run(y) { $0 &+ c.v } }

// Survivors before all captures, in clause order: `Tf1cncn_n` is
// `(double x, i64 z, i64 a, i64 b)`. Returns x + Double(z * a + z + b).
@inline(never) func twoClosures(_ f: (Int) -> Int, _ x: Double, _ g: (Int) -> Int, _ z: Int) -> Double {
    x + Double(f(z) &+ g(z))
}
public func useTwoClosures(_ a: Int, _ b: Int, _ x: Double, _ z: Int) -> Double {
    twoClosures({ $0 &* a }, x, { $0 &+ b }, z)
}

// A closure that survives keeps its two words: `Tf1cnn_n` is
// `(ptr, ptr, i64 z, i64 a)`.
@inline(never) func oneOfTwo(_ f: (Int) -> Int, _ g: (Int) -> Int, _ z: Int) -> Int { f(z) &+ g(z) }
public func useOneOfTwo(_ a: Int, _ z: Int, _ h: (Int) -> Int) -> Int { oneOfTwo({ $0 &* a }, h, z) }

// A generic survivor, its metatype dropped: `(double v, i64 k)`.
@inline(never) func genericValue<T>(_ t: T.Type, _ v: T, _ f: (T) -> Int) -> Int { f(v) &+ 1 }
public func useGenericValue(_ d: Double, _ k: Int) -> Int { genericValue(Double.self, d) { Int($0) &+ k } }

// Three entries, the `@out T` converted to a direct result:
// `(double v, i64 n, i64 k)` returning double.
@inline(never) func folded<T>(_ v: T, _ n: Int, _ f: (T, Int) -> T) -> T { f(v, n) }
public func useFolded(_ d: Double, _ k: Int) -> Double { folded(d, 3) { $0 + Double($1 &+ k) } }

// The same closure twice, the second entry `C0`: `Tf1EC0n_n` is
// `(i64 z, i64 a)`. Returns (z + a) * 2.
@inline(never) func sameTwice(_ f: (Int) -> Int, _ g: (Int) -> Int, _ z: Int) -> Int { f(z) &+ g(z) }
public func useSameTwice(_ a: Int, _ z: Int) -> Int {
    let h: (Int) -> Int = { $0 &+ a }
    return sameTwice(h, h, z)
}

// A method: three entries, `self` third. `(i64 x, i64 self.v, i64 q)`.
public struct Runner {
    var v: Int
    @inline(never) public func run(_ x: Int, _ f: (Int) -> Int) -> Int { f(x) &+ v }
}
public func useRunner(_ s: Runner, _ q: Int) -> Int { s.run(q) { $0 &* q } }
