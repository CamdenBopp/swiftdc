// A witness for an async requirement of another image's protocol
// (`AsyncIteratorProtocol.next()`, libswiftCore). The conformance's resilient
// witness for `next` does not point at code: it points at the witness's async
// function pointer record (`…TWTu`, `{ i32 relative, i32 context size }`),
// whose first word leads to the witness's code. The symbol at the record is
// what `interface --member-addresses` saw, so it printed the record's address.
// True behaviour: the member's code is the function the record leads to.
public struct Countdown: AsyncIteratorProtocol {
    public var remaining: Int

    public init(from start: Int) { remaining = start }

    public mutating func next() async -> Int? {
        guard remaining > 0 else { return nil }
        remaining -= 1
        return remaining
    }
}
