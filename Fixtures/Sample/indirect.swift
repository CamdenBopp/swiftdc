// Fixture for swiftdc's indirect-result (x8) reconstruction: functions whose
// result is too wide for the four result registers, so the caller passes a
// buffer address in x8 and the callee stores into it. Built by `build.sh` into
// `libIndirect.dylib` (-Onone -g) and `libIndirect.opt.dylib` (-O), both
// asserted on verbatim in `ReconstructionTests.swift`.
//
// A separate module on purpose: `reconstruction.swift`'s binaries are pinned by
// byte offset in the preflight fuzz-mutant tests, so growing them would move
// every mutant.
//
// The mutable global below is load-bearing: it gives the dylib a `__DATA`
// segment. Without one the image has three segments, and the pinned MachOKit
// reads the `seg_info_offset == 0` entry of `dyld_chained_starts_in_image`
// (dyld's "this segment has no fixups") as a `dyld_chained_starts_in_segment`
// struct; the bytes under it then decode to `page_count = 0x4000`, and the
// 32 KB over-read past the file mapping faults whenever the next page is
// unmapped (3 of 4 test runs). A fourth segment moves the aliased bytes so the
// garbage count is 0x18 and the over-read stays inside the file. The bug is
// MachOKit's, not this fixture's; see handoff.md.
public var indirectCallCount = 0

// MARK: - Indirect results (the x8 result buffer)

// A struct of five words is too large for the four result registers, so the
// caller passes a buffer address in x8 and the callee stores the fields into it.
// x0 at the `ret` is a STALE first argument, never the result: an x8-indirect
// function must not print `return arg0`. When every field's store through x8 is
// proven on every path, the return reconstructs field-wise.
public struct Wide5 {
    var a: Int
    var b: Int
    var c: Int
    var d: Int
    var e: Int
}

// -O inlines the memberwise init into direct stores; -Onone calls
// `Wide5.init(a:b:c:d:e:)` with the SAME x8 forwarded, so the result is the
// callee's result (`return Wide5.init(...)`), not a stale register.
@inline(never)
public func makeWide(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int) -> Wide5 {
    Wide5(a: a, b: b, c: c, d: d, e: e)
}
public func constantWide() -> Wide5 { Wide5(a: 1, b: 2, c: 3, d: 4, e: 5) }

// Caller side: the result of an x8-indirect call lives in the caller's frame
// slot that x8 pointed at, so a later load from that slot is a FIELD of the
// call's result (`makeWide(...).a`), not a raw stack load.
public func wideSum(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int) -> Int {
    let w = makeWide(a, b, c, d, e)
    return w.a + w.e
}

// Negative: a field stored on only ONE path (the other path keeps the zero)
// does not meet at the shared `ret`, so the field-wise return must DECLINE
// rather than print one arm's value as the result.
public func wideMaybeSet(_ flag: Bool, _ p: UnsafeMutablePointer<Int>) -> Wide5 {
    var w = Wide5(a: 0, b: 0, c: 0, d: 0, e: 0)
    if flag { w.a = p.pointee }
    return w
}

// Negative: a generic result is written by the value witness
// (`initializeWithCopy(dest: x8, src: x0)`), so the result pointer ESCAPES into
// a call argument and nothing about the buffer's contents is provable.
public func identity<T>(_ x: T) -> T { x }

// Negative: an existential result has no stored-property layout to cover, so
// even provable stores through x8 (the value, the metadata) decline.
public func asAny(_ x: Int) -> Any { x }

// Negative: the result is a callee's result PARTIALLY overwritten afterwards; the
// buffer holds neither the call's value nor a full set of field stores.
@inline(never)
public func otherWide() -> Wide5 { Wide5(a: 9, b: 9, c: 9, d: 9, e: 9) }
public func modifiedWide(_ a: Int) -> Wide5 {
    var w = otherWide()
    w.a = a
    return w
}

// Negative: the address of the local holding the result escapes into a callee
// that writes through it, so the local's zero-initialized slots are stale after
// the call. The copy into x8 must not print those zeros as the result.
@inline(never)
public func fillWide(_ p: UnsafeMutablePointer<Wide5>) { p.pointee.a = 7 }
public func escapedWide() -> Wide5 {
    var w = Wide5(a: 0, b: 0, c: 0, d: 0, e: 0)
    fillWide(&w)
    return w
}

// A payload enum of more than four scalars (four payload words plus the tag
// byte at offset 32) is returned through x8 as well. The tag store names the
// case exactly (the static enum-layout oracle), and the payload words follow.
// (A three-word payload would still travel in x0...x3, direct, not via x8.)
public enum Shape4 {
    case empty
    case box(Int, Int, Int, Int)
    case ball(Int)
    case tagged(String, Int, Int)
}
public func makeBox(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Shape4 { .box(a, b, c, d) }
public func emptyShape() -> Shape4 { .empty }
// Negative: a payload that is not a tuple of word scalars (a `String` spans two
// words) has no provable scalar arity, so the case is named but its payload
// is not spelled out: the return declines rather than guessing `tagged(a, b, c, d)`.
public func makeTagged(_ s: String, _ n: Int, _ m: Int) -> Shape4 { .tagged(s, n, m) }
