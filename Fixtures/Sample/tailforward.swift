// Functions that end in a tail branch to a callee whose result they
// return (-O). The branch forwards the callee's x0 as the caller's result:
//   countLit: `b String.count.getter` (a property getter: no argument list)
//   dynType:  `b swift_getDynamicType` (a runtime entry, C prototype)
//   metaOf:   `b swift_getObjectType`, whose `AnyObject.Type` result is
//             not yet read as one register, so it still has no `return`
// Each read as a call statement with no `return`.
public func countLit() -> Int { "hello".count }
public func dynType<T>(_ x: T) -> Any.Type { type(of: x) }
public func metaOf<T: AnyObject>(_ x: T) -> AnyObject.Type { type(of: x) }
