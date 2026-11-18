// Own-source reduction. Same-width signedness wrappers are B-only at -O/-Osize; smaller-result wrappers keep ordinary call/RET controls. Distinct increments prevent folding.
// Own source: distinct producer increments keep exported entries separate.
@inline(never) public func unsigned8TailProducer(_ x: Int8) -> Int8 { x &+ 1 }
@inline(never) public func unsigned8Tail(_ x: Int8) -> UInt8 { UInt8(bitPattern: unsigned8TailProducer(x)) }
@inline(never) public func signed8TailProducer(_ x: UInt8) -> UInt8 { x &+ 2 }
@inline(never) public func signed8Tail(_ x: UInt8) -> Int8 { Int8(bitPattern: signed8TailProducer(x)) }
@inline(never) public func unsigned16TailProducer(_ x: Int16) -> Int16 { x &+ 3 }
@inline(never) public func unsigned16Tail(_ x: Int16) -> UInt16 { UInt16(bitPattern: unsigned16TailProducer(x)) }
@inline(never) public func signed16TailProducer(_ x: UInt16) -> UInt16 { x &+ 4 }
@inline(never) public func signed16Tail(_ x: UInt16) -> Int16 { Int16(bitPattern: signed16TailProducer(x)) }
@inline(never) public func unsigned32TailProducer(_ x: Int32) -> Int32 { x &+ 5 }
@inline(never) public func unsigned32Tail(_ x: Int32) -> UInt32 { UInt32(bitPattern: unsigned32TailProducer(x)) }
@inline(never) public func signed32TailProducer(_ x: UInt32) -> UInt32 { x &+ 6 }
@inline(never) public func signed32Tail(_ x: UInt32) -> Int32 { Int32(bitPattern: signed32TailProducer(x)) }
@inline(never) public func unsigned8From16TailProducer(_ x: Int16) -> Int16 { x &+ 7 }
@inline(never) public func unsigned8From16Tail(_ x: Int16) -> UInt8 { UInt8(truncatingIfNeeded: unsigned8From16TailProducer(x)) }
@inline(never) public func signed8From16TailProducer(_ x: UInt16) -> UInt16 { x &+ 8 }
@inline(never) public func signed8From16Tail(_ x: UInt16) -> Int8 { Int8(truncatingIfNeeded: signed8From16TailProducer(x)) }
@inline(never) public func unsigned16From32TailProducer(_ x: Int32) -> Int32 { x &+ 9 }
@inline(never) public func unsigned16From32Tail(_ x: Int32) -> UInt16 { UInt16(truncatingIfNeeded: unsigned16From32TailProducer(x)) }
@inline(never) public func signed16From32TailProducer(_ x: UInt32) -> UInt32 { x &+ 10 }
@inline(never) public func signed16From32Tail(_ x: UInt32) -> Int16 { Int16(truncatingIfNeeded: signed16From32TailProducer(x)) }
@inline(never) public func unsigned32From64TailProducer(_ x: Int64) -> Int64 { x &+ 11 }
@inline(never) public func unsigned32From64Tail(_ x: Int64) -> UInt32 { UInt32(truncatingIfNeeded: unsigned32From64TailProducer(x)) }
@inline(never) public func signed32From64TailProducer(_ x: UInt64) -> UInt64 { x &+ 12 }
@inline(never) public func signed32From64Tail(_ x: UInt64) -> Int32 { Int32(truncatingIfNeeded: signed32From64TailProducer(x)) }
@inline(never) public func unsigned8From64TailProducer(_ x: Int64) -> Int64 { x &+ 13 }
@inline(never) public func unsigned8From64Tail(_ x: Int64) -> UInt8 { UInt8(truncatingIfNeeded: unsigned8From64TailProducer(x)) }
@inline(never) public func signed8From64TailProducer(_ x: UInt64) -> UInt64 { x &+ 14 }
@inline(never) public func signed8From64Tail(_ x: UInt64) -> Int8 { Int8(truncatingIfNeeded: signed8From64TailProducer(x)) }
