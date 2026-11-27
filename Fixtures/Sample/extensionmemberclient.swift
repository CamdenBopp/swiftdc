// The client opens the existential and calls the extension's method: one
// formal, k. The registers after it are Self's metadata and witness table,
// and one more still holds the address the value was projected to.
//
// viaExistential(a, b, k) = emMake(a, b).scaled(k) = (a &+ b &+ 3) &* k
import ExtensionMemberKit

@inline(never) public func viaExistential(_ a: Int, _ b: Int, _ k: Int) -> Int {
    emMake(a, b).scaled(k)
}

// viaDouble(a, b, f) = emMake(a, b).tilted(f) = a &+ b &+ 3 &+ Int(f)
@inline(never) public func viaDouble(_ a: Int, _ b: Int, _ f: Double) -> Int {
    emMake(a, b).tilted(f)
}

// viaInt(a, b, k) = a.emPlus(k) &+ b = a &+ k &* 3 &+ b
@inline(never) public func viaInt(_ a: Int, _ b: Int, _ k: Int) -> Int {
    a.emPlus(k) &+ b
}

// viaBuffer(p, k, j) = p.emCount(k) &+ j = p.count &+ k &+ j
@inline(never) public func viaBuffer(_ p: UnsafeRawBufferPointer, _ k: Int, _ j: Int) -> Int {
    p.emCount(k) &+ j
}

// viaStruct(a, b, k) = emMake(a, b).against(EMBig(a: k, b: 1, c: 2, d: 3))
//                    = a &+ b &+ 3 &- (k &+ 6)
@inline(never) public func viaStruct(_ a: Int, _ b: Int, _ k: Int) -> Int {
    emMake(a, b).against(EMBig(a: k, b: 1, c: 2, d: 3))
}
