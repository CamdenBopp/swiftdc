// Compile as module SignedSelfLoad with signed_self_load.s. Mutating declarations select
// the actual native address-valued Swift self ABI independently of the stub.
public struct FloatBox {
    public var f: Float

    @_silgen_name("$s14SignedSelfLoad8FloatBoxV9roundTripSfyF")
    public mutating func roundTrip() -> Float

    @_silgen_name("$s14SignedSelfLoad8FloatBoxV17roundTripUnscaledSfyF")
    public mutating func roundTripUnscaled() -> Float

    @_silgen_name("$s14SignedSelfLoad8FloatBoxV5plainSfyF")
    public mutating func plain() -> Float
}

public struct SignedBox {
    public var i: Int32

    @_silgen_name("$s14SignedSelfLoad9SignedBoxV6signeds5Int64VyF")
    public mutating func signed() -> Int64
}

public struct ByteBox {
    public var i: Int8

    @_silgen_name("$s14SignedSelfLoad7ByteBoxV4wideSfyF")
    public mutating func wide() -> Float
}

public struct ShortBox {
    public var i: Int16

    @_silgen_name("$s14SignedSelfLoad8ShortBoxV4wideSfyF")
    public mutating func wide() -> Float
}

@_cdecl("signedselfload_round_trip")
public func loadBitsRoundTrip(_ pattern: UInt32) -> UInt32 {
    var value = FloatBox(f: Float(bitPattern: pattern))
    return value.roundTrip().bitPattern
}

@_cdecl("signedselfload_round_trip_unscaled")
public func loadBitsRoundTripUnscaled(_ pattern: UInt32) -> UInt32 {
    var value = FloatBox(f: Float(bitPattern: pattern))
    return value.roundTripUnscaled().bitPattern
}

@_cdecl("signedselfload_plain")
public func loadBitsPlain(_ pattern: UInt32) -> UInt32 {
    var value = FloatBox(f: Float(bitPattern: pattern))
    return value.plain().bitPattern
}

@_cdecl("signedselfload_signed")
public func loadBitsSigned(_ input: Int32) -> Int64 {
    var value = SignedBox(i: input)
    return value.signed()
}

@_cdecl("signedselfload_wide_byte")
public func loadBitsWideByte(_ input: Int8) -> UInt32 {
    var value = ByteBox(i: input)
    return value.wide().bitPattern
}

@_cdecl("signedselfload_wide_short")
public func loadBitsWideShort(_ input: Int16) -> UInt32 {
    var value = ShortBox(i: input)
    return value.wide().bitPattern
}


// Exact whole-field raw and signed reads.
extension FloatBox {
    @_silgen_name("$s14SignedSelfLoad8FloatBoxV7rawWords6UInt64VyF")
    public mutating func rawWord() -> UInt64

    @_silgen_name("$s14SignedSelfLoad8FloatBoxV10signedWords5Int64VyF")
    public mutating func signedWord() -> Int64
}

@_cdecl("signedselfload_raw_word")
public func loadBitsRawWord(_ pattern: UInt32) -> UInt64 {
    var box = FloatBox(f: Float(bitPattern: pattern))
    return box.rawWord()
}

@_cdecl("signedselfload_signed_word")
public func loadBitsSignedWord(_ pattern: UInt32) -> Int64 {
    var box = FloatBox(f: Float(bitPattern: pattern))
    return box.signedWord()
}

// These type-check the source expressions asserted by the renderer tests.
// The native C wrappers above call the assembly bodies; their expected bits
// are computed independently in the tests.
extension FloatBox {
    func expectedFloat() -> Float { return self.f }
    func expectedRawWord() -> UInt64 { return UInt64(self.f.bitPattern) }
    func expectedSignedWord() -> Int64 { return Int64(Int32(bitPattern: self.f.bitPattern)) }
}

extension SignedBox {
    func expectedSigned() -> Int64 { return Int64(self.i) }
}

extension ByteBox {
    func expectedWide() -> Float { return Float(bitPattern: UInt32(bitPattern: Int32(self.i))) }
}

extension ShortBox {
    func expectedWide() -> Float { return Float(bitPattern: UInt32(bitPattern: Int32(self.i))) }
}

public struct OffsetByte {
    public var marker: UInt64
    public var value: Int8

    @_silgen_name("$s14SignedSelfLoad10OffsetByteV13sampleStorages5Int64VyF")
    public mutating func sampleStorage() -> Int64
}

@_cdecl("storage_OffsetByte")
public func cOffsetByte(_ input: Int8) -> Int64 {
    var receiver = OffsetByte(marker: 0x0123456789abcdef, value: input)
    return receiver.sampleStorage()
}

public struct OffsetHalf {
    public var marker: UInt64
    public var value: Int16

    @_silgen_name("$s14SignedSelfLoad10OffsetHalfV13sampleStorages5Int64VyF")
    public mutating func sampleStorage() -> Int64
}

@_cdecl("storage_OffsetHalf")
public func cOffsetHalf(_ input: Int16) -> Int64 {
    var receiver = OffsetHalf(marker: 0x0123456789abcdef, value: input)
    return receiver.sampleStorage()
}

public struct OffsetWord {
    public var marker: UInt64
    public var value: Int32

    @_silgen_name("$s14SignedSelfLoad10OffsetWordV13sampleStorages5Int64VyF")
    public mutating func sampleStorage() -> Int64
}

@_cdecl("storage_OffsetWord")
public func cOffsetWord(_ input: Int32) -> Int64 {
    var receiver = OffsetWord(marker: 0x0123456789abcdef, value: input)
    return receiver.sampleStorage()
}

public struct UnsignedByte {
    public var value: UInt8

    @_silgen_name("$s14SignedSelfLoad12UnsignedByteV13sampleStorages5Int64VyF")
    public mutating func sampleStorage() -> Int64
}

@_cdecl("storage_UnsignedByte")
public func cUnsignedByte(_ input: UInt8) -> Int64 {
    var receiver = UnsignedByte(value: input)
    return receiver.sampleStorage()
}

public struct UnsignedHalf {
    public var value: UInt16

    @_silgen_name("$s14SignedSelfLoad12UnsignedHalfV13sampleStorages5Int64VyF")
    public mutating func sampleStorage() -> Int64
}

@_cdecl("storage_UnsignedHalf")
public func cUnsignedHalf(_ input: UInt16) -> Int64 {
    var receiver = UnsignedHalf(value: input)
    return receiver.sampleStorage()
}

public struct UnsignedWord {
    public var value: UInt32

    @_silgen_name("$s14SignedSelfLoad12UnsignedWordV13sampleStorages5Int64VyF")
    public mutating func sampleStorage() -> Int64
}

@_cdecl("storage_UnsignedWord")
public func cUnsignedWord(_ input: UInt32) -> Int64 {
    var receiver = UnsignedWord(value: input)
    return receiver.sampleStorage()
}

public struct ZeroByte {
    public var value: UInt8

    @_silgen_name("$s14SignedSelfLoad8ZeroByteV13sampleStorages6UInt64VyF")
    public mutating func sampleStorage() -> UInt64
}

@_cdecl("storage_ZeroByte")
public func cZeroByte(_ input: UInt8) -> UInt64 {
    var receiver = ZeroByte(value: input)
    return receiver.sampleStorage()
}

public struct ZeroHalf {
    public var value: UInt16

    @_silgen_name("$s14SignedSelfLoad8ZeroHalfV13sampleStorages6UInt64VyF")
    public mutating func sampleStorage() -> UInt64
}

@_cdecl("storage_ZeroHalf")
public func cZeroHalf(_ input: UInt16) -> UInt64 {
    var receiver = ZeroHalf(value: input)
    return receiver.sampleStorage()
}

public struct SignedWByte {
    public var value: Int8

    @_silgen_name("$s14SignedSelfLoad11SignedWByteV13sampleStorages6UInt64VyF")
    public mutating func sampleStorage() -> UInt64
}

@_cdecl("storage_SignedWByte")
public func cSignedWByte(_ input: Int8) -> UInt64 {
    var receiver = SignedWByte(value: input)
    return receiver.sampleStorage()
}

public struct SignedUWByte {
    public var value: Int8

    @_silgen_name("$s14SignedSelfLoad12SignedUWByteV13sampleStorages6UInt64VyF")
    public mutating func sampleStorage() -> UInt64
}

@_cdecl("storage_SignedUWByte")
public func cSignedUWByte(_ input: Int8) -> UInt64 {
    var receiver = SignedUWByte(value: input)
    return receiver.sampleStorage()
}

public struct SignedWHalf {
    public var value: Int16

    @_silgen_name("$s14SignedSelfLoad11SignedWHalfV13sampleStorages6UInt64VyF")
    public mutating func sampleStorage() -> UInt64
}

@_cdecl("storage_SignedWHalf")
public func cSignedWHalf(_ input: Int16) -> UInt64 {
    var receiver = SignedWHalf(value: input)
    return receiver.sampleStorage()
}

public struct SignedUWHalf {
    public var value: Int16

    @_silgen_name("$s14SignedSelfLoad12SignedUWHalfV13sampleStorages6UInt64VyF")
    public mutating func sampleStorage() -> UInt64
}

@_cdecl("storage_SignedUWHalf")
public func cSignedUWHalf(_ input: Int16) -> UInt64 {
    var receiver = SignedUWHalf(value: input)
    return receiver.sampleStorage()
}

public struct FloatWByte {
    public var value: Int8

    @_silgen_name("$s14SignedSelfLoad10FloatWByteV13sampleStorageSfyF")
    public mutating func sampleStorage() -> Float
}

@_cdecl("storage_FloatWByte")
public func cFloatWByte(_ input: Int8) -> UInt32 {
    var receiver = FloatWByte(value: input)
    return receiver.sampleStorage().bitPattern
}

public struct FloatWHalf {
    public var value: Int16

    @_silgen_name("$s14SignedSelfLoad10FloatWHalfV13sampleStorageSfyF")
    public mutating func sampleStorage() -> Float
}

@_cdecl("storage_FloatWHalf")
public func cFloatWHalf(_ input: Int16) -> UInt32 {
    var receiver = FloatWHalf(value: input)
    return receiver.sampleStorage().bitPattern
}

public struct MixedWord {
    public var value: UInt32

    @_silgen_name("$s14SignedSelfLoad9MixedWordV13sampleStorages6UInt64VyF")
    public mutating func sampleStorage() -> UInt64
}

@_cdecl("storage_MixedWord")
public func cMixedWord(_ input: UInt32) -> UInt64 {
    var receiver = MixedWord(value: input)
    return receiver.sampleStorage()
}

// Type-check the exact Swift expressions expected from the source renderer.
extension OffsetByte {
    func expectedStorage() -> Int64 { return Int64(self.value) }
}

extension OffsetHalf {
    func expectedStorage() -> Int64 { return Int64(self.value) }
}

extension OffsetWord {
    func expectedStorage() -> Int64 { return Int64(self.value) }
}

extension UnsignedByte {
    func expectedStorage() -> Int64 { return Int64(Int8(bitPattern: self.value)) }
}

extension UnsignedHalf {
    func expectedStorage() -> Int64 { return Int64(Int16(bitPattern: self.value)) }
}

extension UnsignedWord {
    func expectedStorage() -> Int64 { return Int64(Int32(bitPattern: self.value)) }
}

extension ZeroByte {
    func expectedStorage() -> UInt64 { return UInt64(self.value) }
}

extension ZeroHalf {
    func expectedStorage() -> UInt64 { return UInt64(self.value) }
}

extension SignedWByte {
    func expectedStorage() -> UInt64 { return UInt64(UInt32(bitPattern: Int32(self.value))) }
}

extension SignedUWByte {
    func expectedStorage() -> UInt64 { return UInt64(UInt32(bitPattern: Int32(self.value))) }
}

extension SignedWHalf {
    func expectedStorage() -> UInt64 { return UInt64(UInt32(bitPattern: Int32(self.value))) }
}

extension SignedUWHalf {
    func expectedStorage() -> UInt64 { return UInt64(UInt32(bitPattern: Int32(self.value))) }
}

extension FloatWByte {
    func expectedStorage() -> Float { return Float(bitPattern: UInt32(bitPattern: Int32(self.value))) }
}

extension FloatWHalf {
    func expectedStorage() -> Float { return Float(bitPattern: UInt32(bitPattern: Int32(self.value))) }
}

extension MixedWord {
    func expectedStorage() -> UInt64 { return ((UInt64(UInt8(truncatingIfNeeded: self.value)) << 32) | UInt64(self.value)) }
    func expectedStorageReordered() -> UInt64 { return (UInt64(self.value) | (UInt64(UInt8(truncatingIfNeeded: self.value)) << 32)) }
}
