// Compile as module LoadBits with load_bits.s. These mutating declarations
// select the native indirect receiver convention. The assembly supplies each body.
public struct FloatBox {
    public var f: Float

    @_silgen_name("$s8LoadBits8FloatBoxV9roundTripSfyF")
    public mutating func roundTrip() -> Float

    @_silgen_name("$s8LoadBits8FloatBoxV17roundTripUnscaledSfyF")
    public mutating func roundTripUnscaled() -> Float

    // Uses an explicit load and sign extension to exercise the narrow read.
    @_silgen_name("$s8LoadBits8FloatBoxV5plainSfyF")
    public mutating func plain() -> Float

    // Also keeps an outer mask whose low word is all ones.
    @_silgen_name("$s8LoadBits8FloatBoxV6maskedSfyF")
    public mutating func masked() -> Float
}

@_cdecl("loadbits_round_trip")
public func loadBitsRoundTrip(_ pattern: UInt32) -> UInt32 {
    var value = FloatBox(f: Float(bitPattern: pattern))
    return value.roundTrip().bitPattern
}

@_cdecl("loadbits_round_trip_unscaled")
public func loadBitsRoundTripUnscaled(_ pattern: UInt32) -> UInt32 {
    var value = FloatBox(f: Float(bitPattern: pattern))
    return value.roundTripUnscaled().bitPattern
}

@_cdecl("loadbits_plain")
public func loadBitsPlain(_ pattern: UInt32) -> UInt32 {
    var value = FloatBox(f: Float(bitPattern: pattern))
    return value.plain().bitPattern
}

@_cdecl("loadbits_masked")
public func loadBitsMasked(_ pattern: UInt32) -> UInt32 {
    var value = FloatBox(f: Float(bitPattern: pattern))
    return value.masked().bitPattern
}
