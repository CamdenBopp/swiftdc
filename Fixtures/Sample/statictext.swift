// A StaticString parameter is three words: the start pointer (or a scalar),
// the code-unit count and a flags byte (stdlib StaticString.swift:77-92).
// True behaviour: `report` calls `note("ready", 3)`, two arguments; laid
// out one register per argument it read `note("ready", 5, 2, 3)`.
@inline(never) public func note(_ text: StaticString, _ count: Int) -> Int {
    Int(bitPattern: text.utf8Start) &+ text.utf8CodeUnitCount &+ count
}
@inline(never) public func report() -> Int { note("ready", 3) }

// `fatalError(m)` calls `_assertionFailure(_:_:file:line:flags:)`: three,
// two and three words in x0-x7, then `line` and `flags` on the stack.
// True behaviour: five arguments, the prefix "Fatal error", m, the file
// name, the line and the flags.
@inline(never) public func die(_ m: String) -> Never { fatalError(m) }
