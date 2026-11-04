// Which register holds each parameter at entry. Truth is `-emit-ir`.
import EntrySeedKit
import Foundation

// `inout` of a struct this image lays out is one address, whatever the struct
// holds: `a3` is (ptr, i64, i64, i64), so `l` is x3 (`lsl x8, x3, #3`).
public struct P2 { public var a: Int; public var b: Int }
public struct P3 { public var a: Int; public var b: Int; public var c: Int }
public struct P4 { public var a: Int; public var b: Int; public var c: Int; public var d: Int }
public struct PD { public var a: Double; public var b: Double }
public struct Unit { public var nothing: Void = () }

@inline(never) public func a2(_ p: inout P2, _ k: Int, _ j: Int) -> Int { j &* 7 }
@inline(never) public func a3(_ p: inout P3, _ k: Int, _ j: Int, _ l: Int) -> Int { l &* 11 }
@inline(never) public func a4(_ p: inout P4, _ k: Int, _ j: Int) -> Int { j &* 13 }
@inline(never) public func aUnit(_ p: inout Unit, _ k: Int, _ j: Int) -> Int { j &* 19 }
// x0 is `p`, x1 is `k`: `p.a = 2.5` stores through x0.
@inline(never) public func aStore(_ p: inout PD, _ k: Int) { p.a = 2.5 }
// A value of the same struct does take its registers: `k` is x3.
@inline(never) public func byValue(_ p: P3, _ k: Int) -> Int { k &* 23 }

// A foreign type is not the local type of the same simple name. Each foreign
// one here is two words (i64, i64) and the local one is one, so `k` is x2.
public struct Data { public var a: Int = 0 }
public struct Duration { public var ms: Int = 0 }

@inline(never) public func foreignData(_ d: Foundation.Data, _ k: Int, _ j: Int) -> Int { k &* 9 }
@inline(never) public func foreignDuration(_ d: Swift.Duration, _ k: Int, _ j: Int) -> Int { k &* 5 }
// The local one's single word: `k` is x1.
@inline(never) public func localData(_ d: Data, _ k: Int, _ j: Int) -> Int { k &* 17 }
// A call site lays its arguments out by the same answer: 42 is x2.
@inline(never) public func callsForeign(_ d: Swift.Duration) -> Int { foreignDuration(d, 42, 1) }

// The result side. The foreign `Rec`'s words are not the local `Rec`'s fields.
public struct Rec {
    public var wrongFirst: Int, wrongSecond: Int, wrongThird: Int, wrongFourth: Int, wrongFifth: Int
}
@inline(never) public func makeForeign(_ k: Int) -> EntrySeedKit.Rec {
    EntrySeedKit.Rec(first: k, second: 2, third: 3, fourth: 4, fifth: 5)
}
@inline(never) public func makeLocal(_ k: Int) -> Rec {
    Rec(wrongFirst: k, wrongSecond: 6, wrongThird: 7, wrongFourth: 8, wrongFifth: 9)
}
@inline(never) public func readForeign(_ k: Int) -> Int { makeForeign(k).third }
