// Authored research corpus. Every exported Swift function has exactly the
// trusted UInt64 -> UInt64 ABI; loops mask their bound before iterating.
// Build independently at -Onone, -O and -Osize, with distinct module names.
@inline(never) public func increment(_ x: UInt64) -> UInt64 { x &+ 1 }
@inline(never) public func mixedBits(_ x: UInt64) -> UInt64 { (x &* 0x9e3779b97f4a7c15) ^ (x >> 13) }
@inline(never) public func lowWord(_ x: UInt64) -> UInt64 { UInt64(UInt32(truncatingIfNeeded: x)) }
@inline(never) public func signedShift(_ x: UInt64) -> UInt64 { UInt64(bitPattern: Int64(bitPattern: x) >> 7) }
@inline(never) public func unsignedRange(_ x: UInt64) -> UInt64 { (x &- 7) < 20 ? 43 : 59 }
@inline(never) public func signedRange(_ x: UInt64) -> UInt64 {
    let n = Int64(bitPattern: x)
    return n >= -11 && n < 23 ? 61 : 71
}
@inline(never) public func choose(_ x: UInt64) -> UInt64 { x < 100 ? x &+ 3 : x &- 5 }
@inline(never) public func quotient(_ x: UInt64) -> UInt64 { x / 7 }
@inline(never) public func residue(_ x: UInt64) -> UInt64 { x % 7 }
@inline(never) public func boundedLoop(_ x: UInt64) -> UInt64 {
    var sum: UInt64 = 0
    var i: UInt64 = 0
    while i < (x & 15) { sum &+= i; i &+= 1 }
    return sum
}
@inline(never) public func wordAdd(_ x: UInt64) -> UInt64 { UInt64(UInt32(truncatingIfNeeded: x) &+ 1) }
@inline(never) public func wordArithmeticShift(_ x: UInt64) -> UInt64 {
    UInt64(UInt32(bitPattern: Int32(truncatingIfNeeded: x) >> 7))
}
@inline(never) public func signExtendWord(_ x: UInt64) -> UInt64 { UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: x))) }
@inline(never) public func signExtendByte(_ x: UInt64) -> UInt64 { UInt64(bitPattern: Int64(Int8(truncatingIfNeeded: x))) }
@inline(never) public func signExtendHalf(_ x: UInt64) -> UInt64 { UInt64(bitPattern: Int64(Int16(truncatingIfNeeded: x))) }
@inline(never) public func unsignedByte(_ x: UInt64) -> UInt64 { UInt64(UInt8(truncatingIfNeeded: x)) }
@inline(never) public func wordNot(_ x: UInt64) -> UInt64 { UInt64(~UInt32(truncatingIfNeeded: x)) }
@inline(never) public func shiftedNot(_ x: UInt64) -> UInt64 { ~(x >> 7) }
@inline(never) public func orNot(_ x: UInt64) -> UInt64 { 33 | ~x }
@inline(never) public func byteSwap(_ x: UInt64) -> UInt64 { x.byteSwapped }
@inline(never) public func unsignedHigh(_ x: UInt64) -> UInt64 { x.multipliedFullWidth(by: x).high }
@inline(never) public func signedHigh(_ x: UInt64) -> UInt64 {
    UInt64(bitPattern: Int64(bitPattern: x).multipliedFullWidth(by: -0x123456789abcdef).high)
}
@inline(never) public func signedWordProduct(_ x: UInt64) -> UInt64 {
    UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: x)) * Int64(Int32(truncatingIfNeeded: x >> 32)))
}
@inline(never) public func unsignedWordProduct(_ x: UInt64) -> UInt64 {
    UInt64(UInt32(truncatingIfNeeded: x)) * UInt64(UInt32(truncatingIfNeeded: x >> 32))
}
@inline(never) public func signedWordAccumulate(_ x: UInt64) -> UInt64 {
    x &+ UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: x)) * Int64(Int32(truncatingIfNeeded: x >> 32)))
}
@inline(never) public func unsignedWordSubtract(_ x: UInt64) -> UInt64 {
    x &- UInt64(UInt32(truncatingIfNeeded: x)) * UInt64(UInt32(truncatingIfNeeded: x >> 32))
}
@inline(never) public func wordSelect(_ x: UInt64) -> UInt64 {
    let n = UInt32(truncatingIfNeeded: x)
    return UInt64((n & 1) != 0 ? n &+ 1 : ~n)
}
