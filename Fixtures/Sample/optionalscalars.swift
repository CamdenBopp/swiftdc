// Fixture for the footprint of an Optional of a fixed-width scalar, which
// has no spare bits for nil: the payload's bytes, then a tag byte that is
// 1 for nil. Built by `build.sh` into `libOptionalScalars.dylib` (-O).
//
// - An eight-byte payload (`Int?`, `Double?`) takes two integer registers,
//   the payload in x0 (a Double's bits too, not d0) and the tag in w1, so
//   the next parameter is x2: `ldr x8, [x0]; ldrb w1, [x0, #8]; mov x0, x8;
//   mov w2, #7; b take…`.
// - A narrower payload (`Int32?`, `Int16?`) packs payload and tag into one
//   integer register: `ldr w8, [x0]; ldrb w9, [x0, #4]; orr x0, x8, x9,
//   lsl #32; mov w1, #7`.
//
// `@_optimize(none)` keeps each callee's signature from being specialized.
//
// True behaviour: every call passes the optional written in the source and
// then 7.

@_optimize(none) @inline(never) public func takeOptInt(_ a: Int?, _ b: Int) -> Int { (a ?? 0) &+ b }
@_optimize(none) @inline(never) public func takeOptDouble(_ a: Double?, _ b: Int) -> Int { Int(a ?? 0) &+ b }
@_optimize(none) @inline(never) public func takeOptInt32(_ a: Int32?, _ b: Int) -> Int { Int(a ?? 0) &+ b }

public func callOptInt(_ p: UnsafePointer<Int?>) -> Int { takeOptInt(p.pointee, 7) }
public func callOptIntSome() -> Int { takeOptInt(5, 7) }
public func callOptIntNil() -> Int { takeOptInt(nil, 7) }
public func callOptDouble(_ p: UnsafePointer<Double?>) -> Int { takeOptDouble(p.pointee, 7) }
public func callOptDoubleSome() -> Int { takeOptDouble(2.5, 7) }
public func callOptInt32(_ p: UnsafePointer<Int32?>) -> Int { takeOptInt32(p.pointee, 7) }
public func callOptInt32Some() -> Int { takeOptInt32(5, 7) }
public func callOptInt32Nil() -> Int { takeOptInt32(nil, 7) }
