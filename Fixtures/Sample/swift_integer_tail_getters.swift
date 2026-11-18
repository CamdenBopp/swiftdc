// Own-source reduction. Computed integer getters become B-only opposite-signedness returns at -O/-Osize. -Onone retains call/RET controls.
// Own source: a computed integer getter and opposite-signedness tail view.
public struct Signed8Box {
 public let value: Int8
 public init(_ value: Int8) { self.value = value }
 public var produced: Int8 { @inline(never) get { value &+ 21 } }
 @inline(never) public func view() -> UInt8 { UInt8(bitPattern: produced) }
}
public struct Unsigned8Box {
 public let value: UInt8
 public init(_ value: UInt8) { self.value = value }
 public var produced: UInt8 { @inline(never) get { value &+ 22 } }
 @inline(never) public func view() -> Int8 { Int8(bitPattern: produced) }
}
public struct Signed16Box {
 public let value: Int16
 public init(_ value: Int16) { self.value = value }
 public var produced: Int16 { @inline(never) get { value &+ 23 } }
 @inline(never) public func view() -> UInt16 { UInt16(bitPattern: produced) }
}
public struct Unsigned16Box {
 public let value: UInt16
 public init(_ value: UInt16) { self.value = value }
 public var produced: UInt16 { @inline(never) get { value &+ 24 } }
 @inline(never) public func view() -> Int16 { Int16(bitPattern: produced) }
}
public struct Signed32Box {
 public let value: Int32
 public init(_ value: Int32) { self.value = value }
 public var produced: Int32 { @inline(never) get { value &+ 25 } }
 @inline(never) public func view() -> UInt32 { UInt32(bitPattern: produced) }
}
public struct Unsigned32Box {
 public let value: UInt32
 public init(_ value: UInt32) { self.value = value }
 public var produced: UInt32 { @inline(never) get { value &+ 26 } }
 @inline(never) public func view() -> Int32 { Int32(bitPattern: produced) }
}
