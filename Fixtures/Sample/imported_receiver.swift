import Foundation

// Independent compiler references for the real external calls used by ASM.
@inline(never) public func referenceURLBridge(_ url: URL) -> NSURL {
    url._bridgeToObjectiveC()
}
@inline(never) public func referenceStringPrefix(_ value: String, _ prefix: String) -> Bool {
    value.hasPrefix(prefix)
}
@_silgen_name("imported_url_bridge_shape")
public func importedURLBridgeShape(_ url: URL) -> NSURL
@_silgen_name("imported_string_prefix_address")
public func importedStringPrefixAddress() -> Bool
@_silgen_name("imported_string_prefix_scalar")
public func importedStringPrefixScalar() -> Bool

@_cdecl("imported_url_bridge_oracle")
public func importedURLBridgeOracle() -> Int64 {
    let value=importedURLBridgeShape(URL(fileURLWithPath: "/example/leaf"))
    return value.lastPathComponent == "leaf" ? 1 : 0
}
@_cdecl("imported_string_prefix_address_oracle")
public func importedStringPrefixAddressOracle() -> Int64 {
    importedStringPrefixAddress() ? 1 : 0
}
@_cdecl("imported_string_prefix_scalar_oracle")
public func importedStringPrefixScalarOracle() -> Int64 {
    importedStringPrefixScalar() ? 1 : 0
}
@_cdecl("imported_string_reference_oracle")
public func importedStringReferenceOracle() -> Int64 {
    referenceStringPrefix("abc", "ab") && !referenceStringPrefix("abc", "zz") ? 1 : 0
}

@_silgen_name("imported_pointer_words")
public func importedPointerWords(_ pointer: UnsafePointer<URL>) -> (UInt, UnsafePointer<URL>)
@inline(never) public func referencePointerWords(_ pointer: UnsafePointer<URL>) -> (UInt, UnsafePointer<URL>) {
    importedPointerWords(pointer)
}
@_silgen_name("imported_url_bridge_opaque")
public func importedURLBridgeOpaque(_ url: URL) -> NSURL
@_cdecl("imported_url_bridge_opaque_oracle")
public func importedURLBridgeOpaqueOracle() -> Int64 {
    importedURLBridgeOpaque(URL(fileURLWithPath: "/example/leaf")).lastPathComponent == "leaf" ? 1 : 0
}

// An unchanged entry x1 is still the real ordinary receiver after formal x0.
public struct Meter {
    public var word: Int
    public init(_ word: Int) { self.word=word }
    @inline(never) public func scaled(_ k: Int) -> Int { word &* k }
    @inline(never) public func ignore(_ k: Int) -> Int { k &+ 5 }
}
@inline(never) public func passThrough(_ k: Int, _ word: Int) -> Int { Meter(word).scaled(k) }
@_cdecl("imported_passthrough_oracle")
public func passThroughOracle() -> Int64 { passThrough(7,9)==63 ? 1 : 0 }
public struct Wide {
    public var a,b,c,d,e: Int
    public init() { a=1;b=2;c=3;d=4;e=5 }
    @inline(never) public func sum(_ k: Int) -> Int { a &+ b &+ c &+ d &+ e &+ k }
}
@inline(never) public func callWide(_ value: Wide, _ k: Int) -> Int { value.sum(k) }
@_cdecl("imported_wide_oracle")
public func wideOracle() -> Int64 { callWide(Wide(),7)==22 ? 1 : 0 }

@inline(never) public func makeReceiverString() -> String { "abc" }
@inline(never) public func makeReceiverScalar() -> Int { 0x636261 }
@_silgen_name("imported_string_prefix_paired")
public func importedStringPrefixPaired() -> Bool
@_silgen_name("imported_string_prefix_mismatched")
public func importedStringPrefixMismatched() -> Bool
@_silgen_name("imported_scalar_receiver_word")
public func importedScalarReceiverWord() -> Int
@_silgen_name("imported_scalar_receiver_whole")
public func importedScalarReceiverWhole() -> Int
@_cdecl("imported_string_paired_oracle")
public func importedStringPairedOracle() -> Int64 { importedStringPrefixPaired() ? 1 : 0 }
@_cdecl("imported_string_mismatched_oracle")
public func importedStringMismatchedOracle() -> Int64 { !importedStringPrefixMismatched() ? 1 : 0 }
@_cdecl("imported_scalar_word_oracle")
public func importedScalarWordOracle() -> Int64 { importedScalarReceiverWord()==0x636261*7 ? 1 : 0 }
@_cdecl("imported_scalar_whole_oracle")
public func importedScalarWholeOracle() -> Int64 { importedScalarReceiverWhole()==0x636261*7 ? 1 : 0 }

public final class DoubleBox {
    public var value: Double = 1
    public var integer: Int = 3
    public init() {}
    @_silgen_name("$s12ImportedSelf9DoubleBoxC12selfWordBitsSiyF")
    public func selfWordBits() -> Int
    @_silgen_name("$s12ImportedSelf9DoubleBoxC15selfIntegerWordSiyF")
    public func selfIntegerWord() -> Int
}
@_silgen_name("$s12ImportedSelf11boxWordBitsySiAA9DoubleBoxCF")
public func boxWordBits(_ box: DoubleBox) -> Int
@_silgen_name("$s12ImportedSelf14boxIntegerWordySiAA9DoubleBoxCF")
public func boxIntegerWord(_ box: DoubleBox) -> Int
@inline(never) public func referenceBoxBits(_ box: DoubleBox) -> Int {
    Int(truncatingIfNeeded: box.value.bitPattern) &* 3
}
@_cdecl("imported_double_word_oracle")
public func importedDoubleWordOracle() -> Int64 {
    let box=DoubleBox()
    let base=UInt(bitPattern: Unmanaged.passUnretained(box).toOpaque())
    let offset=withUnsafePointer(to: &box.value) { UInt(bitPattern: $0)-base }
    guard offset==16 else { return -2 }
    let expected=Int(truncatingIfNeeded: Double(1).bitPattern) &* 3
    return boxWordBits(box)==expected && box.selfWordBits()==expected && referenceBoxBits(box)==expected ? 1 : 0
}
@_cdecl("imported_integer_word_oracle")
public func importedIntegerWordOracle() -> Int64 {
    let box=DoubleBox()
    let base=UInt(bitPattern: Unmanaged.passUnretained(box).toOpaque())
    let offset=withUnsafePointer(to: &box.integer) { UInt(bitPattern: $0)-base }
    return offset==24 && boxIntegerWord(box)==9 && box.selfIntegerWord()==9 ? 1 : 0
}

public struct Four {
    public var a,b,c,d: Int
    public init() { a=1;b=2;c=3;d=4 }
    @inline(never) public func sum(_ k: Int) -> Int { a &+ b &+ c &+ d &+ k }
}
@inline(never) public func callFour(_ value: Four, _ k: Int) -> Int { value.sum(k) }
@_cdecl("imported_four_oracle")
public func fourOracle() -> Int64 { callFour(Four(),7)==17 ? 1 : 0 }

@_silgen_name("imported_unused_receiver")
public func importedUnusedReceiver() -> Int
@_cdecl("imported_unused_receiver_oracle")
public func unusedReceiverOracle() -> Int64 { importedUnusedReceiver()==12 ? 1 : 0 }

public final class PackedBox {
    public var a: UInt8=1, b: UInt8=2, c: UInt8=3, d: UInt8=4
    public var e: UInt8=5, f: UInt8=6, g: UInt8=7, h: UInt8=8
    public init() {}
    @_silgen_name("$s12ImportedSelf9PackedBoxC10packedWordSiyF")
    public func packedWord() -> Int
}
@_cdecl("imported_spanning_field_oracle")
public func spanningFieldOracle() -> Int64 {
    let box=PackedBox()
    let base=UInt(bitPattern: Unmanaged.passUnretained(box).toOpaque())
    func offset(_ field: inout UInt8) -> UInt {
        withUnsafePointer(to: &field) { UInt(bitPattern: $0)-base }
    }
    let offsets=[offset(&box.a),offset(&box.b),offset(&box.c),offset(&box.d),
                 offset(&box.e),offset(&box.f),offset(&box.g),offset(&box.h)]
    guard offsets==Array(16...23).map(UInt.init) else { return -2 }
    let bytes=[box.a,box.b,box.c,box.d,box.e,box.f,box.g,box.h]
    let packed=bytes.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8*$1.offset) }
    return UInt64(bitPattern: Int64(box.packedWord())) == packed &* 3 ? 1 : 0
}
