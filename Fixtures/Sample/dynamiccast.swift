// swift_dynamicCast returns whether the cast succeeded; the value goes to
// its dest buffer (-O). True behaviour: isInt and isStr return a Bool, true
// iff the value is an Int / a String.
@inline(never) public func isInt<T>(_ a: T) -> Bool { a is Int }
@inline(never) public func isStr(_ a: Any) -> Bool { if let _ = a as? String { return true }; return false }

// The metatype helpers take a type and return it, not an object: `x as?
// C.Type` asks whether x is C or a subclass. metaOptional, metaForced and
// metaIs cast types; instanceOptional is the object cast beside them.
public class MetaBase { public init() {} }
@inline(never) public func metaOptional(_ x: Any.Type) -> MetaBase.Type? { x as? MetaBase.Type }
@inline(never) public func metaForced(_ x: AnyClass) -> MetaBase.Type { x as! MetaBase.Type }
@inline(never) public func metaIs(_ a: AnyObject.Type) -> Bool { a is MetaBase.Type }
@inline(never) public func instanceOptional(_ x: AnyObject) -> MetaBase? { x as? MetaBase }
