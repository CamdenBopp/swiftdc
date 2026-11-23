// A field read on both sides of a call to a name twin (-O and -Onone,
// -enforce-exclusivity=unchecked so the compiler emits no markers of its
// own).
//
// The runtime's swift_beginAccess and swift_endAccess write no field of
// any object. accesstwin.c defines functions of those names in this
// image that do. The name is the same; the contract is not. The compiler
// warns that the names are reserved, which is the point of the fixture,
// so build.sh suppresses warnings for it. Each function's true behaviour
// is its source.

public final class Meter { public var n: Int = 0; public init() {} }

@_silgen_name("swift_beginAccess")
func twinBegin(_ m: Meter, _ buffer: UnsafeMutableRawPointer?, _ flags: Int, _ pc: UnsafeMutableRawPointer?)
@_silgen_name("swift_endAccess")
func twinEnd(_ m: Meter)

@inline(never) public func consume(_ x: Int) { print(x) }

// Reads n, the twin sets n to 23, reads n again: 23 minus the old value.
@inline(never) public func acrossEnd(_ m: Meter) -> Int {
    let old = m.n
    twinEnd(m)
    return m.n &- old
}

// consume gets the value from before the twin set n to 19; returns 19.
@inline(never) public func acrossBegin(_ m: Meter) -> Int {
    let old = m.n
    twinBegin(m, nil, 0, nil)
    consume(old)
    return m.n
}

// The control: nothing between the reads, so they are one value.
@inline(never) public func noCall(_ m: Meter) -> Int {
    let old = m.n
    consume(old)
    return m.n &- old
}
