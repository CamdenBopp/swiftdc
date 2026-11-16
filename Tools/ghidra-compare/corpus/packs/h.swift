public protocol Shape { func area() -> Int }
public struct Sq<T>: Shape { public var t: T; public init(_ t: T) { self.t = t }; public func area() -> Int { 4 } }
// opaque result depending on a generic parameter: Sq<T>(x)
public func mkg<T>(_ x: T) -> some Shape { Sq(x) }
