// A StaticString parameter is three words: the start pointer (or a scalar),
// the code-unit count and a flags byte (stdlib StaticString.swift:77-92).
// True behaviour: `report` calls `note("ready", 3)`, two arguments; laid
// out one register per argument it read `note("ready", 5, 2, 3)`.
@inline(never) public func note(_ text: StaticString, _ count: Int) -> Int {
    Int(bitPattern: text.utf8Start) &+ text.utf8CodeUnitCount &+ count
}
@inline(never) public func report() -> Int { note("ready", 3) }
