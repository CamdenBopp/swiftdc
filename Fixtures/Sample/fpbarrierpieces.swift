// A float between two integers of one 8-byte chunk (-O and -Onone).
//
// A struct argument is its scalar fields in offset order, and the Swift
// calling convention merges two integer scalars into one register only
// when they are neighbours in that order and share an 8-byte chunk. A
// float never merges, so one that sits between two integers keeps them in
// separate registers. Measured with `swiftc -O -emit-ir` (Swift 6.4.2,
// arm64): `after(_: {Int16, Float16, Int16}, _: Int)` is
// `(i16, half, i16, i64)`. More than four scalars in all go by address.
// Each function's true behaviour is its source; the comment gives the
// registers at -O.

// i16, half, i16: w0, h0, w1.
public struct Split { public var a: Int16; public var h: Float16; public var b: Int16 }
// The same fields with the integers adjacent. i32, half: w0, h0.
public struct Joined { public var a: Int16; public var b: Int16; public var h: Float16 }
// i16, half, i16, double, double: five scalars, so by address in x0.
public struct SplitWide {
    public var a: Int16; public var h: Float16; public var b: Int16
    public var d: Double; public var e: Double
}
// i32, half, double, double: four scalars, so direct in w0, h0, d1, d2.
public struct JoinedWide {
    public var a: Int16; public var b: Int16; public var h: Float16
    public var d: Double; public var e: Double
}

// s takes x0 and x1, so k is x2 and m is x3. `sub x0, x2, x3`: k - m
@inline(never) public func afterSplit(_ s: Split, _ k: Int, _ m: Int) -> Int { k &- m }
// j takes x0 alone, so k is x1 and m is x2. `sub x0, x1, x2`: k - m
@inline(never) public func afterJoined(_ j: Joined, _ k: Int, _ m: Int) -> Int { k &- m }

// x1 is s.b, not k. `sxth x0, w1`: s.b sign-extended; k (x2) is not read
@inline(never) public func secondOfSplit(_ s: Split, _ k: Int) -> Int { Int(s.b) }
// x1 is k. `mov x0, x1`: k
@inline(never) public func secondOfJoined(_ j: Joined, _ k: Int) -> Int { k }

// w is an address and takes no v register, so x is d0 and y is d1.
// `fsub d0, d0, d1`: x - y
@inline(never) public func afterSplitWide(_ w: SplitWide, _ x: Double, _ y: Double) -> Double { x - y }
// w takes h0, d1 and d2, so x is d3 and y is d4. `fsub d0, d3, d4`: x - y
@inline(never) public func afterJoinedWide(_ w: JoinedWide, _ x: Double, _ y: Double) -> Double { x - y }

// The result has five scalars, so it is written through x8. a is w0, b is
// w1 and d is d0; h is the constant 1.5, the half 0x3e00, stored to +2.
@inline(never) public func withHalf(_ a: Int16, _ b: Int16, _ d: Double) -> SplitWide {
    SplitWide(a: a, h: 1.5, b: b, d: d, e: d)
}
