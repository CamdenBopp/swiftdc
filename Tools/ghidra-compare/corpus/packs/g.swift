// True behaviour noted per function.
public protocol Shape { func area() -> Int }
public struct Sq: Shape { public var s: Int; public init(s: Int) { self.s = s }; public func area() -> Int { s * s } }

// Parameter packs: returns the number of elements in the pack.
public func packCount<each T>(_ v: repeat each T) -> Int {
  var n = 0
  for _ in repeat each v { n += 1 }
  return n
}
// Returns a tuple of the pack wrapped in Optionals.
public func packWrap<each T>(_ v: repeat each T) -> (repeat Optional<each T>) {
  return (repeat Optional(each v))
}
// Variadic generic type
public struct Box<each T> {
  public var items: (repeat each T)
  public init(_ v: repeat each T) { items = (repeat each v) }
}

// Opaque result: returns Sq(s: n)
public func makeShape(_ n: Int) -> some Shape { Sq(s: n) }
// Opaque with primary associated type: returns [n, n+1]
public func makeColl(_ n: Int) -> some Collection<Int> { [n, n + 1] }
// Constrained existential parameter: sums the sequence
public func sumAny(_ s: any Sequence<Int>) -> Int { var t = 0; for x in s { t += x }; return t }
// Returns an existential with primary associated type
public func anySeq(_ n: Int) -> any Sequence<String> { [String(n)] }

// Same-type where clause: true iff first elements equal
public func firstEq<A: Sequence, B: Sequence>(_ a: A, _ b: B) -> Bool where A.Element == B.Element, A.Element: Equatable {
  var ia = a.makeIterator(); var ib = b.makeIterator()
  return ia.next() == ib.next()
}

// Conditional conformance
public struct Pair<T> { public var a: T; public var b: T; public init(a: T, b: T) { self.a = a; self.b = b } }
extension Pair: Equatable where T: Equatable {}
extension Pair: Shape where T == Int { public func area() -> Int { a * b } }

// Associated type with constraint
public protocol Container {
  associatedtype Item: Hashable
  associatedtype Idx = Int
  var first: Item { get }
}
public struct IntC: Container { public typealias Item = String; public var first: String { "x" }; public init() {} }
// Uses associated type witness: returns hash of first
public func hashFirst<C: Container>(_ c: C) -> Int { c.first.hashValue }

// Generic subscript
public struct Store {
  public var d: [String: Any] = [:]
  public init() {}
  public subscript<T>(key: String, as t: T.Type) -> T? { d[key] as? T }
}
// Generic typealias
public typealias StrDict<V> = [String: V]
public func countDict(_ d: StrDict<Int>) -> Int { d.count }

// @_specialize: identity
@_specialize(where T == Int)
public func ident<T>(_ x: T) -> T { x }

// Recursive generic constraint
public protocol Node { associatedtype Child: Node; var kids: [Child] { get } }
// Metatype param: returns MemoryLayout<T>.size
public func sizeOf<T>(_ t: T.Type) -> Int { MemoryLayout<T>.size }
// type(of:): returns the dynamic type
public func dynType<T>(_ x: T) -> Any.Type { type(of: x) }
// is cast: true iff x is an Int
public func isInt<T>(_ x: T) -> Bool { x is Int }
// as? cast to Shape existential
public func asShape<T>(_ x: T) -> (any Shape)? { x as? any Shape }
// Protocol composition parameter
public protocol Named { var name: String { get } }
public func describe(_ x: any Shape & Named) -> String { x.name + String(x.area()) }
public func compo<T: Shape & Named>(_ x: T) -> Int { x.area() }
// Class-bound composition
public class Base { public init() {} }
public func clsComp(_ x: Base & Shape) -> Int { x.area() }
