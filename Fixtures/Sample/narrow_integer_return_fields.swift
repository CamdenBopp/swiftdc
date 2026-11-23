// Exact metadata/read widths preserve same-type getters. A wider stored word
// still needs the narrow result view, including when self arrives by value.
public final class FieldBox {
    public let byte: UInt8
    public let signed: Int16
    public let middle: UInt32
    private let wide: Int64
    public init(_ word: UInt64) {
        byte = UInt8(truncatingIfNeeded: word)
        signed = Int16(truncatingIfNeeded: word)
        middle = UInt32(truncatingIfNeeded: word)
        wide = Int64(bitPattern: word)
    }
    @inline(never) public func narrowedWide() -> Int8 {
        Int8(truncatingIfNeeded: wide)
    }
}

public struct WordBox {
    private let wide: Int
    // Distinct initializer code prevents folding with the bare-RET method.
    public init(_ word: Int) { wide = word &+ 17 }
    @inline(never) public func narrowed() -> Int8 {
        Int8(truncatingIfNeeded: wide)
    }
}
