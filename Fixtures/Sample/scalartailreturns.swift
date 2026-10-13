// At -O/-Osize these forwarding wrappers end in B, not BL; RET.
// The callee's scalar result is the caller's result. Void stays a statement.
@inline(never) public func integerLeaf(_ x: Int) -> Int { x &+ 3 }
@inline(never) public func integerTail(_ x: Int) -> Int { integerLeaf(x) }
@inline(never) public func booleanLeaf(_ x: UInt64) -> Bool { x != 0 }
@inline(never) public func booleanTail(_ x: UInt64) -> Bool { booleanLeaf(x) }
@inline(never) public func floatingLeaf(_ x: Double) -> Double { x + 1 }
@inline(never) public func floatingTail(_ x: Double) -> Double { floatingLeaf(x) }
public var observed: Int = 0
@inline(never) public func voidLeaf(_ x: Int) { observed = x }
@inline(never) public func voidTail(_ x: Int) { voidLeaf(x) }
