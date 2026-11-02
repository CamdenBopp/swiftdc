// A protocol requirement whose right-hand side is a generic type, not an
// associated type: `Readiness.Element == Event<Payload>`. MachOSwiftSection
// 0.22 printed only the associated types it found in the right-hand side,
// `Self.Readiness.Element == Self.Payload`, a requirement the protocol does
// not have; 0.24 prints the type itself.
public struct Event<T> {
    public var value: T
}

public protocol Check: AnyObject {
    associatedtype Payload
    associatedtype Readiness: AsyncSequence where Readiness.Element == Event<Payload>, Readiness.Failure == Never
    associatedtype Pending where Pending == [Payload]
}
