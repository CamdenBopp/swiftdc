// Conditions that compare against a literal holding a quote (-O). The
// rendered literal escapes it (`"a\""`), and a condition scanner that
// toggled at every `"` read everything after that literal as still inside
// it. `skipUnlessQuote`'s loop guard is `cmp x0, x8; ccmp x1, #1, #8, ne;
// b.lt` to the exit: the loop is skipped iff p is the literal's address or
// n < 1. Inverting `((arg0 == "a\"") || (arg1 < 1))` gave
// `!(arg0 == "a\"") || (arg1 < 1)`, entered when n < 1. `skipUnlessPlain`
// is the same loop over `"ab"`, which always rendered
// `!((arg0 == "ab") || (arg1 < 1))`.
//
// True behaviour: each emits "y" while p is not its literal and n counts
// down above 0.
public var sink = ""

@inline(never) public func emit(_ text: String) { sink = text }

public func skipUnlessQuote(_ p: UnsafeRawPointer, _ n: Int) {
    var i = n
    while p != UnsafeRawPointer(("a\"" as StaticString).utf8Start) && i > 0 { emit("y"); i -= 1 }
}

public func skipUnlessPlain(_ p: UnsafeRawPointer, _ n: Int) {
    var i = n
    while p != UnsafeRawPointer(("ab" as StaticString).utf8Start) && i > 0 { emit("y"); i -= 1 }
}
