// Own source: a Swift formal consumes its declared physical low bits.
@inline(never) public func signed8BitPatternConsumer(_ x: Int8) -> Int64 { Int64(x) &* 3 &+ 1 }
@inline(never) public func signed8BitPatternCaller(_ x: UInt8) -> Int64 { signed8BitPatternConsumer(Int8(bitPattern: x)) }
@inline(never) public func unsigned8BitPatternConsumer(_ x: UInt8) -> Int64 { Int64(x) &* 5 &+ 2 }
@inline(never) public func unsigned8BitPatternCaller(_ x: Int8) -> Int64 { unsigned8BitPatternConsumer(UInt8(bitPattern: x)) }
@inline(never) public func signed8TruncationConsumer(_ x: Int8) -> Int64 { Int64(x) &* 7 &+ 3 }
@inline(never) public func signed8TruncationCaller(_ x: Int64) -> Int64 { signed8TruncationConsumer(Int8(truncatingIfNeeded: x)) }
@inline(never) public func unsigned8TruncationConsumer(_ x: UInt8) -> Int64 { Int64(x) &* 9 &+ 4 }
@inline(never) public func unsigned8TruncationCaller(_ x: UInt64) -> Int64 { unsigned8TruncationConsumer(UInt8(truncatingIfNeeded: x)) }
@inline(never) public func signed8SameConsumer(_ x: Int8) -> Int64 { Int64(x) &* 11 &+ 5 }
@inline(never) public func signed8SameCaller(_ x: Int8) -> Int64 { signed8SameConsumer(x) }
@inline(never) public func unsigned8SameConsumer(_ x: UInt8) -> Int64 { Int64(x) &* 13 &+ 6 }
@inline(never) public func unsigned8SameCaller(_ x: UInt8) -> Int64 { unsigned8SameConsumer(x) }
@inline(never) public func signed8NonTailConsumer(_ x: Int8) -> Int64 { Int64(x) &* 15 &+ 7 }
@inline(never) public func signed8NonTailCaller(_ x: UInt8) -> Int64 { signed8NonTailConsumer(Int8(bitPattern: x)) &+ 1007 }
@inline(never) public func unsigned8NonTailConsumer(_ x: UInt8) -> Int64 { Int64(x) &* 17 &+ 8 }
@inline(never) public func unsigned8NonTailCaller(_ x: Int8) -> Int64 { unsigned8NonTailConsumer(UInt8(bitPattern: x)) &+ 1008 }
@inline(never) public func signed8CallResultConsumer(_ x: Int8) -> Int64 { Int64(x) &* 19 &+ 9 }
@inline(never) public func signed8CallResultMaker(_ x: Int8) -> UInt8 { UInt8(bitPattern: x &+ 26) }
@inline(never) public func signed8CallResultCaller(_ x: Int8) -> Int64 { signed8CallResultConsumer(Int8(bitPattern: signed8CallResultMaker(x))) }
@inline(never) public func unsigned8CallResultConsumer(_ x: UInt8) -> Int64 { Int64(x) &* 21 &+ 10 }
@inline(never) public func unsigned8CallResultMaker(_ x: UInt8) -> Int8 { Int8(bitPattern: x &+ 27) }
@inline(never) public func unsigned8CallResultCaller(_ x: UInt8) -> Int64 { unsigned8CallResultConsumer(UInt8(bitPattern: unsigned8CallResultMaker(x))) }
@inline(never) public func signed16BitPatternConsumer(_ x: Int16) -> Int64 { Int64(x) &* 23 &+ 11 }
@inline(never) public func signed16BitPatternCaller(_ x: UInt16) -> Int64 { signed16BitPatternConsumer(Int16(bitPattern: x)) }
@inline(never) public func unsigned16BitPatternConsumer(_ x: UInt16) -> Int64 { Int64(x) &* 25 &+ 12 }
@inline(never) public func unsigned16BitPatternCaller(_ x: Int16) -> Int64 { unsigned16BitPatternConsumer(UInt16(bitPattern: x)) }
@inline(never) public func signed16TruncationConsumer(_ x: Int16) -> Int64 { Int64(x) &* 27 &+ 13 }
@inline(never) public func signed16TruncationCaller(_ x: Int64) -> Int64 { signed16TruncationConsumer(Int16(truncatingIfNeeded: x)) }
@inline(never) public func unsigned16TruncationConsumer(_ x: UInt16) -> Int64 { Int64(x) &* 29 &+ 14 }
@inline(never) public func unsigned16TruncationCaller(_ x: UInt64) -> Int64 { unsigned16TruncationConsumer(UInt16(truncatingIfNeeded: x)) }
@inline(never) public func signed16SameConsumer(_ x: Int16) -> Int64 { Int64(x) &* 31 &+ 15 }
@inline(never) public func signed16SameCaller(_ x: Int16) -> Int64 { signed16SameConsumer(x) }
@inline(never) public func unsigned16SameConsumer(_ x: UInt16) -> Int64 { Int64(x) &* 33 &+ 16 }
@inline(never) public func unsigned16SameCaller(_ x: UInt16) -> Int64 { unsigned16SameConsumer(x) }
@inline(never) public func signed16NonTailConsumer(_ x: Int16) -> Int64 { Int64(x) &* 35 &+ 17 }
@inline(never) public func signed16NonTailCaller(_ x: UInt16) -> Int64 { signed16NonTailConsumer(Int16(bitPattern: x)) &+ 1017 }
@inline(never) public func unsigned16NonTailConsumer(_ x: UInt16) -> Int64 { Int64(x) &* 37 &+ 18 }
@inline(never) public func unsigned16NonTailCaller(_ x: Int16) -> Int64 { unsigned16NonTailConsumer(UInt16(bitPattern: x)) &+ 1018 }
@inline(never) public func signed16CallResultConsumer(_ x: Int16) -> Int64 { Int64(x) &* 39 &+ 19 }
@inline(never) public func signed16CallResultMaker(_ x: Int16) -> UInt16 { UInt16(bitPattern: x &+ 36) }
@inline(never) public func signed16CallResultCaller(_ x: Int16) -> Int64 { signed16CallResultConsumer(Int16(bitPattern: signed16CallResultMaker(x))) }
@inline(never) public func unsigned16CallResultConsumer(_ x: UInt16) -> Int64 { Int64(x) &* 41 &+ 20 }
@inline(never) public func unsigned16CallResultMaker(_ x: UInt16) -> Int16 { Int16(bitPattern: x &+ 37) }
@inline(never) public func unsigned16CallResultCaller(_ x: UInt16) -> Int64 { unsigned16CallResultConsumer(UInt16(bitPattern: unsigned16CallResultMaker(x))) }
@inline(never) public func signed32BitPatternConsumer(_ x: Int32) -> Int64 { Int64(x) &* 43 &+ 21 }
@inline(never) public func signed32BitPatternCaller(_ x: UInt32) -> Int64 { signed32BitPatternConsumer(Int32(bitPattern: x)) }
@inline(never) public func unsigned32BitPatternConsumer(_ x: UInt32) -> Int64 { Int64(x) &* 45 &+ 22 }
@inline(never) public func unsigned32BitPatternCaller(_ x: Int32) -> Int64 { unsigned32BitPatternConsumer(UInt32(bitPattern: x)) }
@inline(never) public func signed32TruncationConsumer(_ x: Int32) -> Int64 { Int64(x) &* 47 &+ 23 }
@inline(never) public func signed32TruncationCaller(_ x: Int64) -> Int64 { signed32TruncationConsumer(Int32(truncatingIfNeeded: x)) }
@inline(never) public func unsigned32TruncationConsumer(_ x: UInt32) -> Int64 { Int64(x) &* 49 &+ 24 }
@inline(never) public func unsigned32TruncationCaller(_ x: UInt64) -> Int64 { unsigned32TruncationConsumer(UInt32(truncatingIfNeeded: x)) }
@inline(never) public func signed32SameConsumer(_ x: Int32) -> Int64 { Int64(x) &* 51 &+ 25 }
@inline(never) public func signed32SameCaller(_ x: Int32) -> Int64 { signed32SameConsumer(x) }
@inline(never) public func unsigned32SameConsumer(_ x: UInt32) -> Int64 { Int64(x) &* 53 &+ 26 }
@inline(never) public func unsigned32SameCaller(_ x: UInt32) -> Int64 { unsigned32SameConsumer(x) }
@inline(never) public func signed32NonTailConsumer(_ x: Int32) -> Int64 { Int64(x) &* 55 &+ 27 }
@inline(never) public func signed32NonTailCaller(_ x: UInt32) -> Int64 { signed32NonTailConsumer(Int32(bitPattern: x)) &+ 1027 }
@inline(never) public func unsigned32NonTailConsumer(_ x: UInt32) -> Int64 { Int64(x) &* 57 &+ 28 }
@inline(never) public func unsigned32NonTailCaller(_ x: Int32) -> Int64 { unsigned32NonTailConsumer(UInt32(bitPattern: x)) &+ 1028 }
@inline(never) public func signed32CallResultConsumer(_ x: Int32) -> Int64 { Int64(x) &* 59 &+ 29 }
@inline(never) public func signed32CallResultMaker(_ x: Int32) -> UInt32 { UInt32(bitPattern: x &+ 46) }
@inline(never) public func signed32CallResultCaller(_ x: Int32) -> Int64 { signed32CallResultConsumer(Int32(bitPattern: signed32CallResultMaker(x))) }
@inline(never) public func unsigned32CallResultConsumer(_ x: UInt32) -> Int64 { Int64(x) &* 61 &+ 30 }
@inline(never) public func unsigned32CallResultMaker(_ x: UInt32) -> Int32 { Int32(bitPattern: x &+ 47) }
@inline(never) public func unsigned32CallResultCaller(_ x: UInt32) -> Int64 { unsigned32CallResultConsumer(UInt32(bitPattern: unsigned32CallResultMaker(x))) }
