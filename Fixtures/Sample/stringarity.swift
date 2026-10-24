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

// Small literals the printable-ASCII decoder refused: the empty string is
// (0, 0xe000000000000000), "\n" is (0x0a, 0xe100000000000000), and "é" is
// (0xa9c3, 0xa200000000000000), its ASCII bit (62) clear. In a String slot
// each is that literal: takeTwo("", 7), takeTwo("\n", 7), takeTwo("é", 7).
public func callTwoEmpty() -> Int { takeTwo("", 7) }
public func callTwoNewline() -> Int { takeTwo("\n", 7) }
public func callTwoAccent() -> Int { takeTwo("é", 7) }

@inline(never) public func makeString(_ n: Int) -> String { String(repeating: "x", count: n) }

// x0 is makeString's first result word and x1 its second: the String is
// that call's, takeTwo(makeString(n), 7).
public func callTwoCallResult(_ n: Int) -> Int { takeTwo(makeString(n), 7) }

// The call's first word with the empty string's second word, and the two
// words of a call that returns no String: neither is a String a call
// returned, takeTwo(?, 7) both.
public func callTwoMixedResult(_ n: Int) -> Int {
    let words = unsafeBitCast(makeString(n), to: (UInt, UInt).self)
    return takeTwo(unsafeBitCast((words.0, 0xe000_0000_0000_0000 as UInt), to: String.self), 7)
}
public struct TwoWords { public var a: UInt; public var b: UInt }
@inline(never) public func makeTwoWords(_ n: Int) -> TwoWords { TwoWords(a: UInt(bitPattern: n), b: UInt(bitPattern: n) &* 3) }
public func callTwoWordsResult(_ n: Int) -> Int { takeTwo(unsafeBitCast(makeTwoWords(n), to: String.self), 7) }

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
    public var label = ""
    public var span: (Int, Int) = (0, 0)
    public var both: (String, String) = ("", "")
    // A class method: self in x20, the String in x0/x1, the Int in x2.
    @_optimize(none) @inline(never) public func put(_ s: String, _ n: Int) { total &+= s.utf8.count &+ n }
}

// b.put(p.pointee, 7): self is x20, so the formals start at x0.
public func callBox(_ b: Box, _ p: UnsafePointer<String>) { b.put(p.pointee, 7) }

// The two words of a String field, loaded with one ldp (`ldp x19, x20,
// [x20, #0x18]`), are that field: takeTwo(self.label, 7). passMixedLabel
// pairs the field's first word with the empty string's second, which is no
// String the program holds: takeTwo(?, 7). passSpan passes the two words of
// a field that is no String, and passFirstOfBoth the first String of a
// two-String field, whose two words are not the whole field: both take
// takeTwo(?, 7) until a part of a field can be named in a String slot.
extension Box {
    @inline(never) public func passLabel() -> Int { takeTwo(label, 7) }
    @inline(never) public func passMixedLabel() -> Int {
        let words = unsafeBitCast(label, to: (UInt, UInt).self)
        return takeTwo(unsafeBitCast((words.0, 0xe000_0000_0000_0000 as UInt), to: String.self), 7)
    }
    @inline(never) public func passSpan() -> Int { takeTwo(unsafeBitCast(span, to: String.self), 7) }
    @inline(never) public func passFirstOfBoth() -> Int { takeTwo(both.0, 7) }
}
