// Structs passed by value, each before an Int (-O). Their registers,
// measured with `swiftc -O -emit-ir` (docs/ABI-INVARIANTS.md): integer
// fields merge per 8-byte chunk ({Int32, Int32} is one x register, {Int16,
// Int32, Int8} two), every float or double takes its own v register, an
// Optional's tag is its own register, an empty struct takes none, and more
// than four registers in all go by address ({Int x5}, {Float x4, Int}).
// Each pass_<S> passes a literal struct and 7, so the 7 lands in the
// register after the struct's: rendered `take_<S>(?, 7)` only when the
// struct's footprint is right.

public struct S1 { var a: Int }
public struct S2 { var a: Int; var b: Int }
public struct S32 { var a: Int32; var b: Int32 }
public struct SID { var a: Int; var d: Double }
public struct SD4 { var a: Double; var b: Double; var c: Double; var d: Double }
public struct SI4 { var a: Int; var b: Int; var c: Int; var d: Int }
public struct SI5 { var a: Int; var b: Int; var c: Int; var d: Int; var e: Int }
public struct SB { var b: Bool; var a: Int }
public struct S8 { var a: Int8; var b: Int8 }
public struct SNest { var p: S2; var c: Int }
public struct SOpt { var o: Int?; var k: Int }
public struct FF { var a: Float; var b: Float }
public struct FI32 { var a: Float; var b: Int32 }
public struct Mixed { var a: Int16; var b: Int32; var c: Int8 }
public struct I32I64I32 { var a: Int32; var b: Int64; var c: Int32 }
public struct F4I { var a: Float; var b: Float; var c: Float; var d: Float; var k: Int }
public struct Empty {  }
public struct WithEmpty { var e: Empty; var k: Int }
@_optimize(none) public func take_S1(_ x: S1, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_S1() -> Int { take_S1(S1(a: 1), 7) }
@_optimize(none) public func take_S2(_ x: S2, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_S2() -> Int { take_S2(S2(a: 1, b: 2), 7) }
@_optimize(none) public func take_S32(_ x: S32, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_S32() -> Int { take_S32(S32(a: 1, b: 2), 7) }
@_optimize(none) public func take_SID(_ x: SID, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_SID() -> Int { take_SID(SID(a: 1, d: 2.5), 7) }
@_optimize(none) public func take_SD4(_ x: SD4, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_SD4() -> Int { take_SD4(SD4(a: 1, b: 2, c: 3, d: 4), 7) }
@_optimize(none) public func take_SI4(_ x: SI4, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_SI4() -> Int { take_SI4(SI4(a: 1, b: 2, c: 3, d: 4), 7) }
@_optimize(none) public func take_SI5(_ x: SI5, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_SI5() -> Int { take_SI5(SI5(a: 1, b: 2, c: 3, d: 4, e: 5), 7) }
@_optimize(none) public func take_SB(_ x: SB, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_SB() -> Int { take_SB(SB(b: true, a: 1), 7) }
@_optimize(none) public func take_S8(_ x: S8, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_S8() -> Int { take_S8(S8(a: 1, b: 2), 7) }
@_optimize(none) public func take_SNest(_ x: SNest, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_SNest() -> Int { take_SNest(SNest(p: S2(a: 1, b: 2), c: 3), 7) }
@_optimize(none) public func take_SOpt(_ x: SOpt, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_SOpt() -> Int { take_SOpt(SOpt(o: 1, k: 2), 7) }
@_optimize(none) public func take_FF(_ x: FF, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_FF() -> Int { take_FF(FF(a: 1, b: 2), 7) }
@_optimize(none) public func take_FI32(_ x: FI32, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_FI32() -> Int { take_FI32(FI32(a: 1, b: 2), 7) }
@_optimize(none) public func take_Mixed(_ x: Mixed, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_Mixed() -> Int { take_Mixed(Mixed(a: 1, b: 2, c: 3), 7) }
@_optimize(none) public func take_I32I64I32(_ x: I32I64I32, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_I32I64I32() -> Int { take_I32I64I32(I32I64I32(a: 1, b: 2, c: 3), 7) }
@_optimize(none) public func take_F4I(_ x: F4I, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_F4I() -> Int { take_F4I(F4I(a: 1, b: 2, c: 3, d: 4, k: 5), 7) }
@_optimize(none) public func take_Empty(_ x: Empty, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_Empty() -> Int { take_Empty(Empty(), 7) }
@_optimize(none) public func take_WithEmpty(_ x: WithEmpty, _ k: Int) -> Int { withUnsafeBytes(of: x) { $0.count } &+ k }
public func pass_WithEmpty() -> Int { take_WithEmpty(WithEmpty(e: Empty(), k: 1), 7) }
