@inline(never) public func g(_ x: Int) -> Int { x &+ 7 }
// tail-calls g: returns x+8
public func f(_ x: Int) -> Int { g(x &+ 1) }
// returns the dynamic type of an existential: tail call into swift_getDynamicType
public func dynAny(_ x: Any) -> Any.Type { type(of: x) }
// returns the metatype of an Int: AnyObject.Type cast
public func metaOf<T: AnyObject>(_ x: T) -> AnyObject.Type { type(of: x) }
