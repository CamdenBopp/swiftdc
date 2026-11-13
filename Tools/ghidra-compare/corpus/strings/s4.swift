// Return-path and field-write probes.
// returns (0x6968, Int(bitPattern: 0xE200000000000000)): two Ints, not "hi"
public func intPairRet() -> (Int, Int) { (0x6968, Int(bitPattern: 0xE200000000000000)) }
// returns UInt64 pair struct
public struct Two { public var a: UInt64; public var b: UInt64 }
public func twoRet() -> Two { Two(a: 0x6968, b: 0xE200000000000000) }
// typed Int-pair argument
@inline(never) public func takeInts(_ a: Int, _ b: Int) { print(a, b) }
public func intPairArg() { takeInts(0x6968, Int(bitPattern: 0xE200000000000000)) }
// ternary between two literals: b ? "yes" : "no"
public func pick(_ b: Bool) -> String { b ? "yes" : "no" }
// ternary small vs large
public func pickLarge(_ b: Bool) -> String { b ? "short" : "this one is long enough" }
// Optional<String>: b ? "some" : nil
public func optStr(_ b: Bool) -> String? { b ? "some" : nil }
// Character return "é"
public func retChar() -> Character { "é" }
// Unicode.Scalar return "€" = 0x20AC
public func retScalar() -> Unicode.Scalar { "€" }
// class field writes
public final class Box {
    public var label: String = "init-label"
    public var other: String = ""
    public init() {}
    // sets label = "set-small", other = "set-a-long-literal-value"
    public func set() { label = "set-small"; other = "set-a-long-literal-value" }
    // sets label = "" (empty)
    public func clear() { label = "" }
    // sets label = "tab\there"
    public func setTab() { label = "tab\there" }
}
// String count of a literal: 5
public func countLit() -> Int { "hello".count }
// utf8 count of argument
public func utf8Count(_ s: String) -> Int { s.utf8.count }
// returns "a" + "b" folded? concat literals
public func concatLits() -> String { "abc" + "def" }
// string from repeating
public func rep() -> String { String(repeating: "ab", count: 3) }
// Array of strings literal
public func arr() -> [String] { ["one", "two-is-a-longer-literal"] }
// Dictionary key lookup
public func dict(_ d: [String: Int]) -> Int? { d["lookup-key"] }
