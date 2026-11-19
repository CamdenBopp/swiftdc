// Own source: no result-width declaration is present in the analyzed image for the C provider.
@_silgen_name("argument_opaque_word") private func opaqueWord(_ x: UInt64) -> UInt64
@inline(never) public func signed8OpaqueConsumer(_ value: Int8) -> Int64 { Int64(value) &* 3 &+ 8 }
@inline(never) public func signed8OpaqueCaller(_ seed: UInt64) -> Int64 { signed8OpaqueConsumer(Int8(truncatingIfNeeded: opaqueWord(seed))) }
@inline(never) public func unsigned8OpaqueConsumer(_ value: UInt8) -> Int64 { Int64(value) &* 3 &+ 8 }
@inline(never) public func unsigned8OpaqueCaller(_ seed: UInt64) -> Int64 { unsigned8OpaqueConsumer(UInt8(truncatingIfNeeded: opaqueWord(seed))) }
@inline(never) public func signed16OpaqueConsumer(_ value: Int16) -> Int64 { Int64(value) &* 3 &+ 16 }
@inline(never) public func signed16OpaqueCaller(_ seed: UInt64) -> Int64 { signed16OpaqueConsumer(Int16(truncatingIfNeeded: opaqueWord(seed))) }
@inline(never) public func unsigned16OpaqueConsumer(_ value: UInt16) -> Int64 { Int64(value) &* 3 &+ 16 }
@inline(never) public func unsigned16OpaqueCaller(_ seed: UInt64) -> Int64 { unsigned16OpaqueConsumer(UInt16(truncatingIfNeeded: opaqueWord(seed))) }
@inline(never) public func signed32OpaqueConsumer(_ value: Int32) -> Int64 { Int64(value) &* 3 &+ 32 }
@inline(never) public func signed32OpaqueCaller(_ seed: UInt64) -> Int64 { signed32OpaqueConsumer(Int32(truncatingIfNeeded: opaqueWord(seed))) }
@inline(never) public func unsigned32OpaqueConsumer(_ value: UInt32) -> Int64 { Int64(value) &* 3 &+ 32 }
@inline(never) public func unsigned32OpaqueCaller(_ seed: UInt64) -> Int64 { unsigned32OpaqueConsumer(UInt32(truncatingIfNeeded: opaqueWord(seed))) }
