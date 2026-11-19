// Own-source scalar-argument role controls: stack, address, setter, FP banks.
@inline(never) public func signed8StackConsumer(_ a0: Int64, _ a1: Int64, _ a2: Int64, _ a3: Int64, _ a4: Int64, _ a5: Int64, _ a6: Int64, _ a7: Int64, _ x: Int8) -> Int64 { (a0 &+ a1 &+ a2 &+ a3 &+ a4 &+ a5 &+ a6 &+ a7) &+ (Int64(x) &* 5) &+ 1 }
@inline(never) public func signed8StackCaller(_ x: UInt8, _ g: Int64) -> Int64 { signed8StackConsumer(g, g &+ 1, g &+ 2, g &+ 3, g &+ 4, g &+ 5, g &+ 6, g &+ 7, Int8(bitPattern: x)) }
@inline(never) public func signed8InoutBump(_ x: inout Int8) { x &+= 1 }
@inline(never) public func signed8InoutCaller(_ x: Int8) -> Int64 { var value = x; signed8InoutBump(&value); return Int64(value) }
public final class Signed8Box {
 private var bits: Int8
 private var writes: Int64 = 0
 public init(_ bits: Int8) { self.bits = bits }
 public var value: Int8 {
  @inline(never) get { bits }
  @inline(never) set { bits = newValue; writes &+= 1 }
 }
 public var writeCount: Int64 { @inline(never) get { writes } }
}
@inline(never) public func signed8SetterCaller(_ box: Signed8Box, _ x: UInt8) { box.value = Int8(bitPattern: x) }
@inline(never) public func signed8MixedConsumer(_ f: Float, _ x: Int8) -> Int64 { (Int64(x) &* 5) &+ Int64(f) &+ 1 }
@inline(never) public func signed8MixedCaller(_ x: UInt8, _ f: Float) -> Int64 { signed8MixedConsumer(f, Int8(bitPattern: x)) }
@inline(never) public func unsigned8StackConsumer(_ a0: Int64, _ a1: Int64, _ a2: Int64, _ a3: Int64, _ a4: Int64, _ a5: Int64, _ a6: Int64, _ a7: Int64, _ x: UInt8) -> Int64 { (a0 &+ a1 &+ a2 &+ a3 &+ a4 &+ a5 &+ a6 &+ a7) &+ (Int64(x) &* 7) &+ 2 }
@inline(never) public func unsigned8StackCaller(_ x: Int8, _ g: Int64) -> Int64 { unsigned8StackConsumer(g, g &+ 1, g &+ 2, g &+ 3, g &+ 4, g &+ 5, g &+ 6, g &+ 7, UInt8(bitPattern: x)) }
@inline(never) public func unsigned8InoutBump(_ x: inout UInt8) { x &+= 2 }
@inline(never) public func unsigned8InoutCaller(_ x: UInt8) -> Int64 { var value = x; unsigned8InoutBump(&value); return Int64(value) }
public final class Unsigned8Box {
 private var bits: UInt8
 private var writes: Int64 = 0
 public init(_ bits: UInt8) { self.bits = bits }
 public var value: UInt8 {
  @inline(never) get { bits }
  @inline(never) set { bits = newValue; writes &+= 2 }
 }
 public var writeCount: Int64 { @inline(never) get { writes } }
}
@inline(never) public func unsigned8SetterCaller(_ box: Unsigned8Box, _ x: Int8) { box.value = UInt8(bitPattern: x) }
@inline(never) public func unsigned8MixedConsumer(_ f: Float, _ x: UInt8) -> Int64 { (Int64(x) &* 7) &+ Int64(f) &+ 2 }
@inline(never) public func unsigned8MixedCaller(_ x: Int8, _ f: Float) -> Int64 { unsigned8MixedConsumer(f, UInt8(bitPattern: x)) }
@inline(never) public func signed16StackConsumer(_ a0: Int64, _ a1: Int64, _ a2: Int64, _ a3: Int64, _ a4: Int64, _ a5: Int64, _ a6: Int64, _ a7: Int64, _ x: Int16) -> Int64 { (a0 &+ a1 &+ a2 &+ a3 &+ a4 &+ a5 &+ a6 &+ a7) &+ (Int64(x) &* 9) &+ 3 }
@inline(never) public func signed16StackCaller(_ x: UInt16, _ g: Int64) -> Int64 { signed16StackConsumer(g, g &+ 1, g &+ 2, g &+ 3, g &+ 4, g &+ 5, g &+ 6, g &+ 7, Int16(bitPattern: x)) }
@inline(never) public func signed16InoutBump(_ x: inout Int16) { x &+= 3 }
@inline(never) public func signed16InoutCaller(_ x: Int16) -> Int64 { var value = x; signed16InoutBump(&value); return Int64(value) }
public final class Signed16Box {
 private var bits: Int16
 private var writes: Int64 = 0
 public init(_ bits: Int16) { self.bits = bits }
 public var value: Int16 {
  @inline(never) get { bits }
  @inline(never) set { bits = newValue; writes &+= 3 }
 }
 public var writeCount: Int64 { @inline(never) get { writes } }
}
@inline(never) public func signed16SetterCaller(_ box: Signed16Box, _ x: UInt16) { box.value = Int16(bitPattern: x) }
@inline(never) public func signed16MixedConsumer(_ f: Float, _ x: Int16) -> Int64 { (Int64(x) &* 9) &+ Int64(f) &+ 3 }
@inline(never) public func signed16MixedCaller(_ x: UInt16, _ f: Float) -> Int64 { signed16MixedConsumer(f, Int16(bitPattern: x)) }
@inline(never) public func unsigned16StackConsumer(_ a0: Int64, _ a1: Int64, _ a2: Int64, _ a3: Int64, _ a4: Int64, _ a5: Int64, _ a6: Int64, _ a7: Int64, _ x: UInt16) -> Int64 { (a0 &+ a1 &+ a2 &+ a3 &+ a4 &+ a5 &+ a6 &+ a7) &+ (Int64(x) &* 11) &+ 4 }
@inline(never) public func unsigned16StackCaller(_ x: Int16, _ g: Int64) -> Int64 { unsigned16StackConsumer(g, g &+ 1, g &+ 2, g &+ 3, g &+ 4, g &+ 5, g &+ 6, g &+ 7, UInt16(bitPattern: x)) }
@inline(never) public func unsigned16InoutBump(_ x: inout UInt16) { x &+= 4 }
@inline(never) public func unsigned16InoutCaller(_ x: UInt16) -> Int64 { var value = x; unsigned16InoutBump(&value); return Int64(value) }
public final class Unsigned16Box {
 private var bits: UInt16
 private var writes: Int64 = 0
 public init(_ bits: UInt16) { self.bits = bits }
 public var value: UInt16 {
  @inline(never) get { bits }
  @inline(never) set { bits = newValue; writes &+= 4 }
 }
 public var writeCount: Int64 { @inline(never) get { writes } }
}
@inline(never) public func unsigned16SetterCaller(_ box: Unsigned16Box, _ x: Int16) { box.value = UInt16(bitPattern: x) }
@inline(never) public func unsigned16MixedConsumer(_ f: Float, _ x: UInt16) -> Int64 { (Int64(x) &* 11) &+ Int64(f) &+ 4 }
@inline(never) public func unsigned16MixedCaller(_ x: Int16, _ f: Float) -> Int64 { unsigned16MixedConsumer(f, UInt16(bitPattern: x)) }
@inline(never) public func signed32StackConsumer(_ a0: Int64, _ a1: Int64, _ a2: Int64, _ a3: Int64, _ a4: Int64, _ a5: Int64, _ a6: Int64, _ a7: Int64, _ x: Int32) -> Int64 { (a0 &+ a1 &+ a2 &+ a3 &+ a4 &+ a5 &+ a6 &+ a7) &+ (Int64(x) &* 13) &+ 5 }
@inline(never) public func signed32StackCaller(_ x: UInt32, _ g: Int64) -> Int64 { signed32StackConsumer(g, g &+ 1, g &+ 2, g &+ 3, g &+ 4, g &+ 5, g &+ 6, g &+ 7, Int32(bitPattern: x)) }
@inline(never) public func signed32InoutBump(_ x: inout Int32) { x &+= 5 }
@inline(never) public func signed32InoutCaller(_ x: Int32) -> Int64 { var value = x; signed32InoutBump(&value); return Int64(value) }
public final class Signed32Box {
 private var bits: Int32
 private var writes: Int64 = 0
 public init(_ bits: Int32) { self.bits = bits }
 public var value: Int32 {
  @inline(never) get { bits }
  @inline(never) set { bits = newValue; writes &+= 5 }
 }
 public var writeCount: Int64 { @inline(never) get { writes } }
}
@inline(never) public func signed32SetterCaller(_ box: Signed32Box, _ x: UInt32) { box.value = Int32(bitPattern: x) }
@inline(never) public func signed32MixedConsumer(_ f: Float, _ x: Int32) -> Int64 { (Int64(x) &* 13) &+ Int64(f) &+ 5 }
@inline(never) public func signed32MixedCaller(_ x: UInt32, _ f: Float) -> Int64 { signed32MixedConsumer(f, Int32(bitPattern: x)) }
@inline(never) public func unsigned32StackConsumer(_ a0: Int64, _ a1: Int64, _ a2: Int64, _ a3: Int64, _ a4: Int64, _ a5: Int64, _ a6: Int64, _ a7: Int64, _ x: UInt32) -> Int64 { (a0 &+ a1 &+ a2 &+ a3 &+ a4 &+ a5 &+ a6 &+ a7) &+ (Int64(x) &* 15) &+ 6 }
@inline(never) public func unsigned32StackCaller(_ x: Int32, _ g: Int64) -> Int64 { unsigned32StackConsumer(g, g &+ 1, g &+ 2, g &+ 3, g &+ 4, g &+ 5, g &+ 6, g &+ 7, UInt32(bitPattern: x)) }
@inline(never) public func unsigned32InoutBump(_ x: inout UInt32) { x &+= 6 }
@inline(never) public func unsigned32InoutCaller(_ x: UInt32) -> Int64 { var value = x; unsigned32InoutBump(&value); return Int64(value) }
public final class Unsigned32Box {
 private var bits: UInt32
 private var writes: Int64 = 0
 public init(_ bits: UInt32) { self.bits = bits }
 public var value: UInt32 {
  @inline(never) get { bits }
  @inline(never) set { bits = newValue; writes &+= 6 }
 }
 public var writeCount: Int64 { @inline(never) get { writes } }
}
@inline(never) public func unsigned32SetterCaller(_ box: Unsigned32Box, _ x: Int32) { box.value = UInt32(bitPattern: x) }
@inline(never) public func unsigned32MixedConsumer(_ f: Float, _ x: UInt32) -> Int64 { (Int64(x) &* 15) &+ Int64(f) &+ 6 }
@inline(never) public func unsigned32MixedCaller(_ x: Int32, _ f: Float) -> Int64 { unsigned32MixedConsumer(f, UInt32(bitPattern: x)) }
@inline(never) public func floatBitsInt32Consumer(_ x: Int32) -> Int64 { Int64(x) &* 19 &+ 7 }
@inline(never) public func floatBitsInt32Caller(_ x: Float) -> Int64 { floatBitsInt32Consumer(Int32(bitPattern: x.bitPattern)) }
@inline(never) public func floatBitsUInt8Consumer(_ x: UInt8) -> Int64 { Int64(x) &* 19 &+ 7 }
@inline(never) public func floatBitsUInt8Caller(_ x: Float) -> Int64 { floatBitsUInt8Consumer(UInt8(truncatingIfNeeded: x.bitPattern)) }
