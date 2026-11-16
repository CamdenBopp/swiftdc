// Interpolation probes.
@inline(never) public func sink(_ s: String) { print(s) }
// "a=\(a), b=\(b)"
public func two(_ a: Int, _ b: Int) { sink("a=\(a), b=\(b)") }
// "\(a)" only
public func only(_ a: Int) { sink("\(a)") }
// segment with quote, newline and backslash: "q\"\(a)\n\\end"
public func escaped(_ a: Int) { sink("q\"\(a)\n\\end") }
// non-ASCII segment: "größe: \(a) €"
public func nonASCII(_ a: Int) { sink("größe: \(a) €") }
// a long leading segment: "this is a long leading segment \(a)"
public func longLead(_ a: Int) { sink("this is a long leading segment \(a)") }
// interpolating a String: "[\(s)]"
public func bracket(_ s: String) { sink("[\(s)]") }
