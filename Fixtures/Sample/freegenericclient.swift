// Each caller keeps one of its own values in a callee-saved register across
// a call to a generic free function of another image. That function has no
// `self`, whatever x20 holds at the call.
//
// sizeInt(a, b, c) = b &* 1009 &+ c &* 1013 &+ gSize(a, b)
// weighPair(a, b, c) = gWeigh(FGPair(x: a, y: b), c) &+ b &* 7 &+ a
// viaMethod(box, k) = box.pick(k, k), the control: a generic method, whose
// receiver is in x20.
import FreeGenericKit

public struct FGPair: FGWeighted {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public var weight: Int { x &+ y }
    @inline(never) public func sum(_ k: Int) -> Int { x &+ y &+ k }
}

@inline(never) public func sizeInt(_ a: Int, _ b: Int, _ c: Int) -> Int {
    b &* 1009 &+ c &* 1013 &+ gSize(a, b)
}

@inline(never) public func weighPair(_ a: Int, _ b: Int, _ c: Int) -> Int {
    gWeigh(FGPair(x: a, y: b), c) &+ b &* 7 &+ a
}

@inline(never) public func viaMethod(_ box: FGBox, _ k: Int) -> Int {
    box.pick(k, k)
}
