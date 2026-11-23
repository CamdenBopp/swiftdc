// Each build emits one conversion so LLVM cannot fold incompatible signatures.
// Optimized bodies may be a bare RET; the declared result still reads only its
// low 8/16/32 bits, with signed interpretation for Int8/Int16/Int32.
#if NARROW_RETURN_INT8
public typealias NarrowInput = Int64
public typealias NarrowOutput = Int8
#elseif NARROW_RETURN_INT16
public typealias NarrowInput = Int64
public typealias NarrowOutput = Int16
#elseif NARROW_RETURN_INT32
public typealias NarrowInput = Int64
public typealias NarrowOutput = Int32
#elseif NARROW_RETURN_UINT8
public typealias NarrowInput = UInt64
public typealias NarrowOutput = UInt8
#elseif NARROW_RETURN_UINT16
public typealias NarrowInput = UInt64
public typealias NarrowOutput = UInt16
#elseif NARROW_RETURN_UINT32
public typealias NarrowInput = UInt64
public typealias NarrowOutput = UInt32
#else
#error("Select a NARROW_RETURN integer type")
#endif

@inline(never) public func narrow(_ x: NarrowInput) -> NarrowOutput {
    NarrowOutput(truncatingIfNeeded: x)
}
