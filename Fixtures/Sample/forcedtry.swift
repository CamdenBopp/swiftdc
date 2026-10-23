// A failed `try!` calls `swift_unexpectedError(error, filenameStart,
// filenameLength, isAscii, line)`, five integer arguments in x0-x4
// (swift/include/swift/Runtime/Error.h:128). The table gave it none, so the
// call rendered `swift_unexpectedError()`.
//
// True behaviour: forced returns risky(x), and traps through
// swift_unexpectedError with the thrown error and the try!'s location when
// risky throws.
struct Refused: Error {}

@inline(never)
func risky(_ x: Int) throws -> Int {
    if x < 0 { throw Refused() }
    return x
}

public func forced(_ x: Int) -> Int { try! risky(x) }
