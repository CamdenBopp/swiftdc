// Fixture for the arity of a Swift callee whose parameters are not all one
// scalar register each. Built by `build.sh` into `libStringArity.dylib` (-O).
//
// A String travels in two integer registers (count and flags, then the
// object), a `String?` in the same two (nil is an extra inhabitant), and an
// `inout` parameter is one address. `@_optimize(none)` keeps each callee's
// signature from being specialized at -O, so the call names the declared
// signature.

@_optimize(none) @inline(never) public func takeTwo(_ a: String, _ b: Int) -> Int { a.utf8.count &+ b }
@_optimize(none) @inline(never) public func takeInout(_ x: inout Int, _ b: Int) { x &+= b }
@_optimize(none) @inline(never) public func takeOptString(_ s: String?, _ b: Int) -> Int { (s?.utf8.count ?? 0) &+ b }
@_optimize(none) @inline(never) public func takeOptInt(_ a: Int?, _ b: Int) -> Int { (a ?? 0) &+ b }

// x0/x1 and x2 all loaded through unknown pointers: takeTwo takes two
// arguments, a String and an Int.
public func callTwo(_ p: UnsafePointer<String>, _ q: UnsafePointer<Int>) -> Int { takeTwo(p.pointee, q.pointee) }

// The String is unknown, the Int is 7 in x2: takeTwo(?, 7).
public func callTwoSeven(_ p: UnsafePointer<String>) -> Int { takeTwo(p.pointee, 7) }

// A small literal in x0/x1 (both words immediate): takeTwo("hi", 7).
public func callTwoSmall() -> Int { takeTwo("hi", 7) }

// A large literal: count and flags in x0, the object address in x1.
public func callTwoLarge() -> Int { takeTwo("a literal longer than fifteen bytes", 7) }

@inline(never) public func makeString(_ n: Int) -> String { String(repeating: "x", count: n) }

// x0 is makeString's first result word and x1 its second, which the call
// site does not track: the String is not proven, takeTwo(?, 7).
public func callTwoCallResult(_ n: Int) -> Int { takeTwo(makeString(n), 7) }

// Both the address and the Int loaded through unknown pointers:
// takeInout(?, ?), never takeInout().
public func callInoutLoaded(_ p: UnsafePointer<UnsafeMutablePointer<Int>>, _ q: UnsafePointer<Int>) {
    takeInout(&p.pointee.pointee, q.pointee)
}

// x0 is the address of the Int, x1 is 7: takeInout(&p.pointee, 7).
public func callInout(_ p: UnsafeMutablePointer<Int>) { takeInout(&p.pointee, 7) }

// String? in x0/x1, the Int in x2: takeOptString(p.pointee, 7).
public func callOptString(_ p: UnsafePointer<String?>) -> Int { takeOptString(p.pointee, 7) }

// nil is not a literal: takeOptString(nil, 7) must not render as a string.
public func callOptStringNil() -> Int { takeOptString(nil, 7) }

// Int? is a payload and a tag byte in two registers (optionalscalars.swift
// covers its layout): takeOptInt(?, 7).
public func callOptInt(_ p: UnsafePointer<Int?>) -> Int { takeOptInt(p.pointee, 7) }

public final class Box {
    public var total = 0
    // A class method: self in x20, the String in x0/x1, the Int in x2.
    @_optimize(none) @inline(never) public func put(_ s: String, _ n: Int) { total &+= s.utf8.count &+ n }
}

// b.put(p.pointee, 7): self is x20, so the formals start at x0.
public func callBox(_ b: Box, _ p: UnsafePointer<String>) { b.put(p.pointee, 7) }
