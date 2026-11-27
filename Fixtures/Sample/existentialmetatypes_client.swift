// Callers of the existential-metatype makers from another image, where a
// maker is a stub with no body and only its name says how it returns
// (-O and -Onone).
//
// `makeFour` returns five words through x8: its caller passes a buffer of
// its own in x8 and reads the result back from that buffer. `makeThree`
// returns four words in x0 to x3 and its caller passes nothing in x8.
//
// Each caller returns the result's first word, the metadata pointer, as an
// Int, plus a constant of its own so no two bodies are the same code.

import ExistentialMetatypes

// The metadata pointer is x0 after the call.
@inline(never) public func firstWordOfThree(_ k: Int) -> Int {
    unsafeBitCast(makeThree(k) as Any.Type, to: Int.self) &+ 3
}

// The metadata pointer is the first word of the buffer the caller passed
// in x8. x0 after the call is not a result.
@inline(never) public func firstWordOfFour(_ k: Int) -> Int {
    unsafeBitCast(makeFour(k) as Any.Type, to: Int.self) &+ 4
}

// The same through the six-word result.
@inline(never) public func firstWordOfFive(_ k: Int) -> Int {
    unsafeBitCast(makeFive(k) as Any.Type, to: Int.self) &+ 5
}

// The caller's own x8 buffer goes to the maker untouched.
@inline(never) public func forwardFour(_ k: Int) -> any (P1 & P2 & P3 & P4).Type {
    makeFour(k &+ 40)
}
