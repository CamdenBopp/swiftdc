// A class parameter's fields in a free function: what names, and what declines.
// Each function adds its own constant so -O cannot fold two of them into one.

public final class Holder {
    public var v = 5
    public init() {}
    public func take(_ other: Holder) -> Int { other.v + v }
}
public func readHolder(_ h: Holder) -> Int { h.v + 1 }
public func writeHolder(_ h: Holder, _ x: Int) { h.v = x }
public func afterString(_ s: String, _ h: Holder) -> Int { h.v + 2 }

// A load names a field only at the field's own width.
public final class Widths {
    public var flag = true
    public var small: Int32 = 1
    public var tiny: Int8 = -1
    public var half: UInt16 = 3
    public var big = 2
    public var d = 1.5
    public var f: Float = 2.5
    public var s = "x"
    public var o: Int? = 1
    public var next: Widths? = nil
    public var pair = (1, 2)
    public init() {}
}
public func readFlag(_ w: Widths) -> Bool { w.flag }
public func readSmall(_ w: Widths) -> Int32 { w.small }
public func readSmallWide(_ w: Widths) -> Int { Int(w.small) }
public func readTiny(_ w: Widths) -> Int8 { w.tiny }
public func readHalf(_ w: Widths) -> UInt16 { w.half }
public func readDouble(_ w: Widths) -> Double { w.d * 2 }
public func readFloat(_ w: Widths) -> Float { w.f }
public func readString(_ w: Widths) -> String { w.s }
public func readOptionalInt(_ w: Widths) -> Int? { w.o }
public func readNext(_ w: Widths) -> Widths? { w.next }
public func readPairFirst(_ w: Widths) -> Int { w.pair.0 }
public func lowByte(_ w: Widths) -> UInt8 { UInt8(truncatingIfNeeded: w.big) }
public func writeFlag(_ w: Widths, _ b: Bool) { w.flag = b }
public func writeSmall(_ w: Widths, _ x: Int32) { w.small = x }
public func writeDouble(_ w: Widths, _ x: Double) { w.d = x }
public func writeString(_ w: Widths, _ x: String) { w.s = x }
public func writePair(_ w: Widths, _ x: Int) { w.pair.1 = x }

// A value read from a field is a snapshot of it.
public func snapshotAcrossStore(_ h: Holder) -> Int { let t = h.v; h.v = 9; return t }
public func snapshotAcrossAliasStore(_ a: Holder, _ b: Holder) -> Int { let t = b.v; a.v = 9; return t }
@inline(never) public func bump(_ h: Holder) { h.v += 1 }
public func snapshotAcrossCall(_ h: Holder) -> Int { let t = h.v; bump(h); return t + 1 }
public func increment(_ h: Holder) -> Int { h.v += 1; return h.v }
public func twoReads(_ a: Holder, _ b: Holder) -> Int { a.v + b.v }
public func copyField(_ a: Holder, _ b: Holder) { a.v = b.v }
public func branchOnField(_ h: Holder) -> Int { if h.v > 3 { return 1 }; return 0 }
public func loopBump(_ h: Holder, _ n: Int) -> Int { let t = h.v; for _ in 0 ..< n { h.v &+= 1 }; return t }

// Not the object the parameter arrived as.
public func optionalParam(_ h: Holder?) -> Int { h?.v ?? 3 }
public func optionalWrite(_ h: Holder?, _ x: Int) { h?.v = x }
public func inoutRead(_ h: inout Holder) -> Int { h.v + 4 }
public func inoutWrite(_ h: inout Holder, _ x: Int) { h.v = x }
public func reassignedOnBranch(_ h: Holder, _ o: Holder, _ c: Bool) { var t = h; if c { t = o }; t.v = 1 }
public func reassignedFresh(_ h: Holder) -> Holder { var t = h; t = Holder(); t.v = 1; return t }
public final class Node {
    public var v = 1
    public var next: Node? = nil
    public init() {}
}
public func walk(_ n: Node) { var c = n; while let m = c.next { c.v = 1; c = m } }

// Generic classes.
public final class Box<T> {
    public var head = 1
    public var item: T
    public var tail = 2
    public init(_ item: T) { self.item = item }
}
public func readBoxHead(_ b: Box<Int>) -> Int { b.head + 5 }
public func readBoxTail(_ b: Box<Int>) -> Int { b.tail + 6 }
public func readBoxGeneric<T>(_ b: Box<T>) -> Int { b.head + 7 }
public func writeBoxHead(_ b: Box<Int>, _ x: Int) { b.head = x + 1 }
public func readWithGeneric<T>(_ h: Holder, _ t: T) -> Int { h.v + 8 }

// A name a class shares with a value type, and a collision between classes.
public enum A { public final class Shared { public var a = 1; public init() {} } }
public enum B { public struct Shared { public var b = 2; public var c = 3; public init() {} } }
public func readShared(_ s: A.Shared) -> Int { s.a + 9 }
public func writeShared(_ s: A.Shared, _ x: Int) { s.a = x + 2 }
public enum C1 { public final class Dup { public var a = 1; public var b = 2; public init() {} } }
public enum C2 { public final class Dup { public var z = 1; public init() {} } }
public func readDup(_ d: C1.Dup) -> Int { d.a + 10 }
public func writeDup(_ d: C1.Dup, _ x: Int) { d.a = x + 3 }

// An own field names at its real offset. An inherited one is not in the map.
public class Base { public final var a = 1; public init() {} }
public final class Derived: Base { public final var b = 2; public override init() { super.init() } }
public func readOwn(_ d: Derived) -> Int { d.b + 11 }
public func readInherited(_ d: Derived) -> Int { d.a + 12 }

// Not free functions.
public enum Namespace { public static func read(_ h: Holder) -> Int { h.v + 13 } }
public func makeClosure(_ h: Holder) -> () -> Int { { h.v + 14 } }
public func asyncRead(_ h: Holder) async -> Int { h.v + 15 }

// No exclusivity marker: a leaf, and an adjacent pair read at once.
final class Quiet { var v = 1; var w = 2; init() {} }
@inline(never) func quietRead(_ q: Quiet) -> Int { q.v &+ 16 }
@inline(never) func quietWrite(_ q: Quiet, _ x: Int) { q.w = x }
@inline(never) func quietCopy(_ q: Quiet) { q.v = q.w }
@inline(never) func quietPair(_ q: Quiet) -> Int { q.v &* q.w }
public func driveQuiet() -> Int { let q = Quiet(); quietWrite(q, 3); quietCopy(q); return quietRead(q) &+ quietPair(q) }
