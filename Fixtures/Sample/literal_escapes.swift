// String literals holding a quote or a backslash. A rendered literal must
// spell its bytes: `smallBackslash` passes the four characters c, backslash,
// n, d (at -O a small string's bytes in x0 and x1; at -Onone a C string
// handed to `String.init(_builtinStringLiteral:…)`), which read as a newline
// when printed `"c\nd"`, and `smallQuote`'s `a"b` printed `"a"b"`, which does
// not parse. The true literals are `"a\"b"` and `"c\\nd"`.
nonisolated(unsafe) public var sink = ""

@inline(never) public func take(_ s: String) { sink = s }

public func smallQuote() { take("a\"b") }
public func smallBackslash() { take("c\\nd") }
public func largeQuote() { take("a long literal with \"quotes\" in it") }
public func largeBackslash() { take("a long literal with a \\n backslash") }
// -Onone builds this from `appendLiteral` and `appendInterpolation` calls,
// whose literal pieces were escaped twice: `"say \\\"hi\\\" \(x) …"`.
public func interpolated(_ x: Int) -> String { "say \"hi\" \(x) and a \\n slash" }
// -Onone folds the `String.init` of a stored literal into the literal alone.
public func storeBackslash() { sink = "c\\nd" }
