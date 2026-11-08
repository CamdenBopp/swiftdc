// Narrow integer constants passed to a Swift function. The caller materialises
// each in a register (Int8 -1 as 0xff or 0xffffffff, depending on the width
// it chose); the parameter's declared type says how to read it. True call:
// takeNarrow(-1, -2, -3, 250, 65000, 4000000000, true).
@inline(never) public func takeNarrow(_ a: Int8, _ b: Int16, _ c: Int32, _ d: UInt8,
                                      _ e: UInt16, _ f: UInt32, _ g: Bool) -> Int {
    Int(a) &+ Int(b) &+ Int(c) &+ Int(d) &+ Int(e) &+ Int(f) &+ (g ? 1 : 0)
}
public func callNarrow() -> Int { takeNarrow(-1, -2, -3, 250, 65000, 4000000000, true) }
// A narrow result is its type's low bits too. True result: -1.
@inline(never) public func minusOne32() -> Int32 { -1 }
