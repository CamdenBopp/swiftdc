// The client half of the throws(Never) fixture, built at -Onone against the
// -O library in typedthrowsnever_lib.swift. Each use emits the library's
// wrapper and the serialized specialization of `transform` it calls:
// `generic specialization <serialized, Swift.Never>` (cannot throw: returns
// `body(x) &+ 1`), `<serialized, TypedThrowsNeverLib.ProbeError>` and
// `<serialized, Swift.Error>` (both may throw what the closure throws).
import TypedThrowsNeverLib

public func useNever(_ x: Int) -> Int {
    neverThrows(x) { $0 &* 3 }
}

public func useTyped(_ x: Int) throws(ProbeError) -> Int {
    try typedThrows(x) { v throws(ProbeError) in
        if v < 0 { throw .bad }
        return v &* 3
    }
}

public struct Untyped: Error {}

public func useUntyped(_ x: Int) throws -> Int {
    try untypedThrows(x) { v in
        if v < 0 { throw Untyped() }
        return v &* 3
    }
}
