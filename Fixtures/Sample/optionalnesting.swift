// Nested Optionals as direct results, and the Optional that is not one
// (-O and -Onone).
//
// A result of at most four registers is returned in them; a fifth piece
// sends the whole value through the caller's buffer in x8. An Optional adds
// a tag byte when its payload has no spare bit pattern for nil, and each
// further level of nesting adds another: `MemoryLayout` gives 9, 10 and 11
// bytes for `Int?`, `Int??` and `UInt64???`. The tag bytes share one
// register, so the register count grows once. A payload with a spare
// pattern (a reference, a String's bridge object, a closure's function
// pointer, a Bool) never grows at all.
//
// So `Int??` is the same two registers as `Int?` with two tag bytes in the
// second, `Substring??` is still Substring's four words, and
// `UnsafeBufferPointer<UInt8>??` is its two words and a register of tags
// (18 bytes). The value that does cross the boundary is an Optional of
// four words with no spare pattern: `Four?` is 33 bytes, five pieces.
//
// Each maker returns its last argument wrapped as non-nil. The constants
// and the leading `k` only keep two makers from compiling to one body.

public struct Four { public var a: UInt64; public var b: UInt64; public var c: UInt64; public var d: UInt64 }

// Direct: payload in x0, tag byte 0 in w1.
@inline(never) public func makeInt(_ x: Int) -> Int?? { x &+ 1 }
// Direct: three levels, still payload in x0 and one tag byte in w1.
@inline(never) public func makeUInt64(_ x: UInt64) -> UInt64??? { x &+ 2 }
// Direct: one byte in w0; nil and the outer nil are spare values of it.
@inline(never) public func makeBool(_ k: Int, _ x: Bool) -> Bool?? { x }
// Direct: the Double's bits in x0 (not d0), tag byte in w1.
@inline(never) public func makeDouble(_ x: Double) -> Double?? { x }
// Direct: the Float's bits and the tag byte share x0.
@inline(never) public func makeFloat(_ x: Float) -> Float?? { x }
// Direct: a raw pointer's only spare pattern is null, which the inner
// Optional takes, so the outer one adds a tag byte in w1.
@inline(never) public func makeRawPointer(_ p: UnsafeRawPointer) -> UnsafeRawPointer?? { p }
// Direct: one register; both nils are spare patterns of the reference.
@inline(never) public func makeObject(_ o: AnyObject) -> AnyObject?? { o }
// Direct: one register, the array's storage reference.
@inline(never) public func makeArray(_ a: [Int]) -> [Int]?? { a }
// Direct: one register, the metadata pointer.
@inline(never) public func makeMetatype(_ k: Int, _ t: Any.Type) -> Any.Type?? { t }
// Direct: one register, the key path's reference.
@inline(never) public func makeKeyPath(_ p: AnyKeyPath) -> AnyKeyPath?? { p }
// Direct: one register, the unmanaged reference, or that and a tag byte.
@inline(never) public func makeUnmanaged(_ k: Int, _ u: Unmanaged<AnyObject>) -> Unmanaged<AnyObject>?? { u }
// Direct: String's two words in x0 and x1.
@inline(never) public func makeString(_ s: String) -> String?? { s }
// Direct: Character's two words in x0 and x1.
@inline(never) public func makeCharacter(_ k: Int, _ c: Character) -> Character?? { c }
// Direct: the scalar's four bytes and the tag byte share x0.
@inline(never) public func makeScalar(_ u: Unicode.Scalar) -> Unicode.Scalar?? { u }
// Direct: two words in x0 and x1; the flags byte and the tag byte share w2.
@inline(never) public func makeStaticString(_ s: StaticString) -> StaticString?? { s }
// Direct: pointer in x0, count in x1, tag byte in w2. Neither word has a
// spare pattern left, so this is the widest growth an Optional causes.
@inline(never) public func makeBuffer(_ b: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8>?? { b }
// Direct: Substring's four words in x0 to x3, with no tag: the widest
// payload that stays in registers.
@inline(never) public func makeSubstring(_ s: Substring) -> Substring?? { s }
// Direct: function in x0, context in x1.
@inline(never) public func makeClosure(_ f: @escaping () -> Int) -> (() -> Int)?? { f }

// Direct: four words in x0 to x3. No Optional, no tag.
@inline(never) public func makeFour(_ x: UInt64) -> Four { Four(a: x, b: x &+ 1, c: x &+ 2, d: x &+ 3) }
// Indirect: the same four words and a tag byte are five pieces, written
// through x8.
@inline(never) public func makeFourOptional(_ x: UInt64) -> Four? { Four(a: x, b: x &+ 5, c: x &+ 6, d: x &+ 7) }
// Indirect: two buffer pointers are four words with no spare pattern, and
// the tag byte is the fifth piece, written through x8.
@inline(never) public func makeBufferPairOptional(
    _ b: UnsafeBufferPointer<UInt8>
) -> (UnsafeBufferPointer<UInt8>, UnsafeBufferPointer<UInt8>)? { (b, b) }
