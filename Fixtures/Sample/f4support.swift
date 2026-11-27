// F4 support: the types, the opaque invokers and the opaque factories the
// closure family in f4closures.swift is called through. The two files are
// compiled together WITHOUT whole-module optimization, so at -O and -Osize
// nothing here is inlined into, or specialized for, a caller in the other
// file: every call through a function value below is a real `blr` on a
// context the invoker knows nothing about.
//
// A thick function value is two words: the entry point and the context.
// A call through one puts the context in x20 and the arguments in x0…,
// exactly as if the context were `self`.

// Two words: travels in two registers, as an argument and as a result.
public struct Pair { var lo: Int; var hi: Int }
extension Pair {
    // lo = y + 53, hi = x - 53
    @inline(never) init(swapped x: Int, and y: Int) { self.init(lo: y &+ 53, hi: x &- 53) }
}
// Five words: passed by address, returned through x8.
public struct Five { var a: Int; var b: Int; var c: Int; var d: Int; var e: Int }
// One word of error payload.
struct Fault: Error { var code: Int }

protocol Weighted { func weight(_ x: Int) -> Int }

// A final class: methods are direct symbols. Fields v at +16, w at +24.
final class Cell: Weighted {
    var v: Int
    var w: Int
    @inline(never) init(_ v: Int, _ w: Int) { self.v = v; self.w = w }
    // v*3 + w*5 + x*7
    @inline(never) func scale(_ x: Int) -> Int { v &* 3 &+ w &* 5 &+ x &* 7 }
    // v*2 + w*3 + x*5 + y*7
    @inline(never) func combine(_ x: Int, _ y: Int) -> Int { v &* 2 &+ w &* 3 &+ x &* 5 &+ y &* 7 }
    // v*43 + w*47 + x
    @inline(never) func weight(_ x: Int) -> Int { v &* 43 &+ w &* 47 &+ x }
    // A closure whose only capture is self: the context IS the object.
    // Calls return v*11 + w*13 + x.
    @inline(never) func makeAdder() -> (Int) -> Int {
        return { x in self.v &* 11 &+ self.w &* 13 &+ x }
    }
}

// A non-final class: `weigh` goes through the vtable.
class Node {
    var k: Int
    @inline(never) init(k: Int) { self.k = k }
    // k*17 + x*19
    @inline(never) func weigh(_ x: Int) -> Int { k &* 17 &+ x &* 19 }
}
final class SubNode: Node {
    // k*23 - x*29
    @inline(never) override func weigh(_ x: Int) -> Int { k &* 23 &- x &* 29 }
}

struct Scale: Weighted {
    var m: Int
    var n: Int
    // m*2 + n*7 + x*13
    @inline(never) func weight(_ x: Int) -> Int { m &* 2 &+ n &* 7 &+ x &* 13 }
    // m*3 - n*5 + x*11
    @inline(never) func mix(_ x: Int) -> Int { m &* 3 &- n &* 5 &+ x &* 11 }
    // A closure capturing a copy of a struct self (two words in a box).
    // Calls return m*17 + n*19 + x*23.
    @inline(never) func makeMixer() -> (Int) -> Int {
        return { x in self.m &* 17 &+ self.n &* 19 &+ x &* 23 }
    }
}

struct Holder { var f: (Int) -> Int; var k: Int }
enum Op {
    case const(Int)
    case unary((Int) -> Int)
    case binary((Int, Int) -> Int)
}

// ---- invokers: each is one call through the function value ----

// Invokers whose machine code would otherwise be identical (and be merged
// at -O) first leave their own number here.
nonisolated(unsafe) var lastInvoker = 0

// f(x), context from the caller's stack or null
@inline(never) func invoke1(_ f: (Int) -> Int, _ x: Int) -> Int { f(x) }
// f(x), escaping type (heap context or the captured object itself)
@inline(never) func invokeEsc(_ f: @escaping (Int) -> Int, _ x: Int) -> Int { lastInvoker = 100; return f(x) }
// f(x, y)
@inline(never) func invokeEsc2(_ f: @escaping (Int, Int) -> Int, _ x: Int, _ y: Int) -> Int { f(x, y) }
// f(x) returning two registers
@inline(never) func invokePair(_ f: (Int) -> Pair, _ x: Int) -> Pair { lastInvoker = 101; return f(x) }
// f(p), p in x0/x1
@inline(never) func invokeWithPair(_ f: (Pair) -> Int, _ p: Pair) -> Int { lastInvoker = 108; return f(p) }
// f(x) returning through x8
@inline(never) func invokeFive(_ f: (Int) -> Five, _ x: Int) -> Five { f(x) }
// f(v), v by address in x0
@inline(never) func invokeWithFive(_ f: (Five) -> Int, _ v: Five) -> Int { lastInvoker = 102; return f(v) }
// f(x) returning Int? in x0 and the tag in w1
@inline(never) func invokeOpt(_ f: (Int) -> Int?, _ x: Int) -> Int? { lastInvoker = 103; return f(x) }
// f(o), o in x0 and the tag in w1
@inline(never) func invokeWithOpt(_ f: (Int?) -> Int, _ o: Int?) -> Int { lastInvoker = 104; return f(o) }
// u(o)(x): the unapplied method reference returns the bound closure
@inline(never) func invokeUnapplied(_ u: (Cell) -> (Int) -> Int, _ o: Cell, _ x: Int) -> Int { u(o)(x) }
// f(x): a closure that returns a closure
@inline(never) func invokeMake(_ f: (Int) -> (Int) -> Int, _ x: Int) -> (Int) -> Int { lastInvoker = 105; return f(x) }
// A C function pointer: a plain blr, no context.
@inline(never) func invokeC(_ f: @convention(c) (Int, Int) -> Int, _ x: Int, _ y: Int) -> Int { f(x, y) }
// A block: the invoke pointer is loaded from block+16, the block is x0.
@inline(never) func invokeBlock(_ f: @convention(block) (Int) -> Int, _ x: Int) -> Int { f(x) }
// h.f(x)*5 + h.k*7
@inline(never) func runHolder(_ h: Holder, _ x: Int) -> Int { h.f(x) &* 5 &+ h.k &* 7 }
// const k: k*2 + x.  unary f: f(x)*3.  binary f: f(x, y)*5.
@inline(never) func runOp(_ op: Op, _ x: Int, _ y: Int) -> Int {
    switch op {
    case .const(let k): return k &* 2 &+ x
    case .unary(let f): return f(x) &* 3
    case .binary(let f): return f(x, y) &* 5
    }
}
// Folds left to right: acc = f(acc).
@inline(never) func runAll(_ fs: [(Int) -> Int], _ seed: Int) -> Int {
    var acc = seed
    for f in fs { acc = f(acc) }
    return acc
}
// try f(x) + 1; the error stays in x21.
@inline(never) func invokeThrowing(_ f: (Int) throws -> Int, _ x: Int) throws -> Int { try f(x) &+ 1 }
// try f(x) + 2; a Fault comes back in x0 with x21 set.
@inline(never) func invokeTyped(_ f: (Int) throws(Fault) -> Int, _ x: Int) throws(Fault) -> Int { try f(x) &+ 2 }
// cond ? v()*7 + 1 : -43. v is not called when cond is false.
@inline(never) func pick(_ cond: Bool, _ v: @autoclosure () -> Int) -> Int { cond ? v() &* 7 &+ 1 : -43 }
// f(p, q, r, s, t)
@inline(never) func invoke5(_ f: (Int, Int, Int, Int, Int) -> Int, _ p: Int, _ q: Int, _ r: Int, _ s: Int, _ t: Int) -> Int { f(p, q, r, s, t) }
// f(x1 … x9): the ninth argument is on the stack
@inline(never) func invoke9(_ f: (Int, Int, Int, Int, Int, Int, Int, Int, Int) -> Int,
                            _ x1: Int, _ x2: Int, _ x3: Int, _ x4: Int, _ x5: Int,
                            _ x6: Int, _ x7: Int, _ x8: Int, _ x9: Int) -> Int {
    f(x1, x2, x3, x4, x5, x6, x7, x8, x9)
}
// f(&v)
@inline(never) func invokeInout(_ f: (inout Int) -> Void, _ v: inout Int) { lastInvoker = 106; f(&v) }
// f(x) at the most general abstraction: argument and result by address.
@inline(never) func invokeGeneric<T>(_ f: (T) -> T, _ x: T) -> T { f(x) }
// mk(x, y)
@inline(never) func invokeMakePair(_ mk: (Int, Int) -> Pair, _ x: Int, _ y: Int) -> Pair { lastInvoker = 107; return mk(x, y) }

// A stored escaping closure, called later.
nonisolated(unsafe) var stashed: ((Int) -> Int)? = nil
@inline(never) func stash(_ f: @escaping (Int) -> Int) { stashed = f }
// stashed(x), or -54 when nothing is stashed
@inline(never) func runStash(_ x: Int) -> Int { stashed.map { $0(x) } ?? -54 }

// Returns f unchanged: the caller gets a function value it knows nothing about.
@inline(never) func launder(_ f: @escaping (Int) -> Int) -> (Int) -> Int { lastInvoker = 109; return f }
// p.lo*3 + p.hi*5 + k*11
@inline(never) func sumPair(_ p: Pair, _ k: Int) -> Int { p.lo &* 3 &+ p.hi &* 5 &+ k &* 11 }

// ---- factories ----

// A closure in a generic context: the box holds T's metadata, the witness
// table and the value. Calls return t.weight(x)*3 + 29.
@inline(never) func makeWeigher<T: Weighted>(_ t: T) -> (Int) -> Int {
    return { x in t.weight(x) &* 3 &+ 29 }
}
// A witness method bound to a generic value. Calls return t.weight(x).
@inline(never) func bindWitness<T: Weighted>(_ t: T) -> (Int) -> Int {
    let f = t.weight
    return f
}
// A boxed counter: each call does n = n*3 + x and returns n.
@inline(never) func makeCounter(_ start: Int) -> (Int) -> Int {
    var n = start
    return { x in n = n &* 3 &+ x; return n }
}
// A closure that captures two closures: f(g(x)) + 46.
@inline(never) func compose(_ f: @escaping (Int) -> Int, _ g: @escaping (Int) -> Int) -> (Int) -> Int {
    return { x in f(g(x)) &+ 46 }
}

// ---- direct callees for the controls ----

// lo = x*3, hi = y*5
@inline(never) func makePairDirect(_ x: Int, _ y: Int) -> Pair { Pair(lo: x &* 3, hi: y &* 5) }
// (x, y, z, x^y, y^z)
@inline(never) func makeFiveDirect(_ x: Int, _ y: Int, _ z: Int) -> Five { Five(a: x, b: y, c: z, d: x ^ y, e: y ^ z) }
// odd x: x*3. even x: nil.
@inline(never) func optDirect(_ x: Int) -> Int? { x & 1 == 1 ? x &* 3 : nil }
// odd x: throws Fault(code: x*5). even x: x*7.
@inline(never) func failIfOdd(_ x: Int) throws -> Int {
    if x & 1 == 1 { throw Fault(code: x &* 5) }
    return x &* 7
}
