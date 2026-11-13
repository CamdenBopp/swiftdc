// String operations probes.
@inline(never) public func sink(_ s: String) { print(s) }
@inline(never) public func sinkC(_ c: Character) { print(c) }
@inline(never) public func sinkU(_ u: Unicode.Scalar) { print(u) }
@inline(never) public func sinkS(_ s: StaticString) { print(s) }
@inline(never) public func sinkSub(_ s: Substring) { print(s) }

// returns 1 for "apple", 2 for "banana-split-large-name", 3 for "", 0 otherwise
public func switchOn(_ s: String) -> Int {
    switch s {
    case "apple": return 1
    case "banana-split-large-name": return 2
    case "": return 3
    default: return 0
    }
}
// true iff s == "yes"
public func eqYes(_ s: String) -> Bool { s == "yes" }
// true iff s != "a-much-longer-literal-here"
public func neLong(_ s: String) -> Bool { s != "a-much-longer-literal-here" }
// interpolation: "n=\(n)!"
public func interp(_ n: Int) -> String { "n=\(n)!" }
// interpolation of string: "Hello, \(name). Welcome back to the app"
public func interpName(_ name: String) { sink("Hello, \(name). Welcome back to the app") }
// Character literal "x" and "é" and "👍🏽"
public func charX() { sinkC("x") }
public func charE() { sinkC("é") }
public func charThumb() { sinkC("👍🏽") }
// Unicode.Scalar "A" (0x41) and "€" (0x20ac)
public func scalarA() { sinkU("A") }
public func scalarEuro() { sinkU("€") }
// StaticString "static text here"
public func staticStr() { sinkS("static text here") }
// String(cString:) of a C literal
public func fromCString() -> String { String(cString: "cstr-literal") }
// returns a literal
public func retSmall() -> String { "ret" }
public func retLarge() -> String { "returned large literal value" }
// Substring: dropFirst(2) of the arg
public func sub(_ s: String) { sinkSub(s.dropFirst(2)) }
// #function / #file
public func funcName() { sink(#function) }
public func fileName() { sink(#fileID) }
// hasPrefix with literal
public func prefixed(_ s: String) -> Bool { s.hasPrefix("pre") }
// global string
public var globalName = "global-default-value-long"
public let shortGlobal = "sg"
public func readGlobal() { sink(globalName) }
// struct with string fields
public struct Person { public var name: String; public var tag: String }
public func makePerson() -> Person { Person(name: "Alice", tag: "a-tag-that-is-quite-long") }
// string concatenation of literals with arg
public func concat(_ s: String) -> String { s + "-suffix" }
// string in optional
public func optStr(_ b: Bool) -> String? { b ? "some" : nil }
