// Fixed/resilient builds share source and manglings but lower small and tuple
// results differently. The native driver checks their actual returned words;
// the builder checks x8 sret versus ordinary leading result parameters in IR.
public struct Big5 {
    public var a,b,c,d,e: Int
    public init(_ k: Int) { a=k; b=k &+ 1; c=k &+ 2; d=k &+ 3; e=k &+ 4 }
}
public struct Small2 {
    public var a,b: Int
    public init(_ k: Int) { a=k; b=k &+ 1 }
}
@inline(never) public func wide(_ k: Int) -> Big5 { Big5(k) }
@inline(never) public func wideForward(_ k: Int) -> Big5 { wide(k) }
@inline(never) public func small(_ k: Int) -> Small2 { Small2(k) }
@inline(never) public func scalar(_ k: Int) -> Int { k &+ 7 }
@inline(never) public func generic<T>(_ x: T) -> T { x }
@inline(never) public func mixed<T>(_ x: T) -> (T, Int) { (x,37) }
@inline(never) public func wideAndInt(_ k: Int) -> (Big5,Int) { (wide(k),37) }
