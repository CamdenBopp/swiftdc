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
// A literal with one escaped quote. The folds found a call's arguments by
// toggling at every `"`, so `"q\""` never closed and they declined:
// -Onone kept `String.init("q\"", 2, 1)` and the appends it lowers to.
public func storeQuote() { sink = "q\"" }
public func interpolatedQuote(_ x: Int) -> String { "q\"\(x)" }
// -Onone builds each literal with String(_builtinStringLiteral:
// utf8CodeUnitCount:isASCII:), passing its bytes' address and count. Named
// as a C string, the address showed only printable ASCII cut after 48
// characters: `"\u{7}ring "` and `"café "` printed an address, and the
// interpolation fold then retried from the next append and printed the
// tail alone, `"\(local_40) done"`; `longStore`'s literal printed cut,
// `"…charac…"`, which the folds took for the string. True behaviour: bell
// returns "\u{7}ring " + x + " done", middleBell "x=" + x + " \u{7} y=" + y,
// accented "café " + x, and longStore and longInterp hold every byte.
public func bell(_ x: Int) -> String { "\u{7}ring \(x) done" }
public func middleBell(_ x: Int, _ y: Int) -> String { "x=\(x) \u{7} y=\(y)" }
public func accented(_ x: Int) -> String { "café \(x)" }
public func longStore() { sink = "a literal that is longer than forty-eight characters, by a few" }
public func longInterp(_ x: Int) -> String { "a literal that is longer than forty-eight characters: \(x)" }
