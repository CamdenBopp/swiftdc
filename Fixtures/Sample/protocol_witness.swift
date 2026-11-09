// A protocol witness through a table swift_conformsToProtocol returned.
// `(object as? Named)?.label` on an AnyObject takes the object's class
// metadata (swift_getObjectType), asks swift_conformsToProtocol for its
// Named table, and calls requirement 0 (the `label` getter) at word 1,
// passing the metadata and the table last. With symbols the requirement is
// named `ProtocolWitness.Named.label.getter`; stripped, the descriptor
// still names the protocol and the requirement's index and kind.

public protocol Named: AnyObject {
    var label: String { get }
    func rank() -> Int
}

final class Thing: Named {
    var label: String { "thing" }
    func rank() -> Int { 3 }
}

@inline(never) public func labelOf(_ object: AnyObject) -> String? { (object as? Named)?.label }
@inline(never) public func rankOf(_ object: AnyObject) -> Int? { (object as? Named)?.rank() }
public func makeThing() -> AnyObject { Thing() }
