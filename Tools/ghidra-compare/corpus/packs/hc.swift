import H
// returns mkg(x).area() == 4, generic so the opaque type needs swift_getOpaqueTypeMetadata2
public func cl<T>(_ x: T) -> Int { mkg(x).area() }
