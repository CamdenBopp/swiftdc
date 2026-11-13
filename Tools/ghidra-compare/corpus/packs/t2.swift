import Darwin
// tail-calls labs: returns |x|
public func h(_ x: Int) -> Int { labs(x) }
// returns metatype via generic: type(of:) on a class-constrained value
public func metaInt(_ x: AnyObject) -> AnyObject.Type { type(of: x) }
