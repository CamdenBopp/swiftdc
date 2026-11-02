// swift_dynamicCast returns whether the cast succeeded; the value goes to
// its dest buffer (-O). True behaviour: isInt and isStr return a Bool, true
// iff the value is an Int / a String.
@inline(never) public func isInt<T>(_ a: T) -> Bool { a is Int }
@inline(never) public func isStr(_ a: Any) -> Bool { if let _ = a as? String { return true }; return false }
