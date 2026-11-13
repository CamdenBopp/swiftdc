// Property wrappers, observers, lazy, coroutine accessors.
@propertyWrapper public struct Clamped {
  var value: Int
  public let lo: Int, hi: Int
  public init(wrappedValue: Int, lo: Int, hi: Int) { self.lo = lo; self.hi = hi; self.value = min(max(wrappedValue, lo), hi) }
  // true: getter returns value; setter clamps to [lo, hi]
  public var wrappedValue: Int { get { value } set { value = min(max(newValue, lo), hi) } }
  // true: projectedValue returns hi - lo
  public var projectedValue: Int { hi - lo }
}
public struct Box {
  @Clamped(lo: 0, hi: 10) public var level: Int = 5
  public init() {}
}
// true: returns b.level (the clamped _level.value)
public func readLevel(_ b: Box) -> Int { b.level }
// true: sets level clamped to [0,10]
public func writeLevel(_ b: inout Box, _ v: Int) { b.level = v }
// true: returns $level == hi - lo == 10
public func readProjected(_ b: Box) -> Int { b.$level }

public final class Observed {
  public var count: Int = 0 {
    willSet { log &+= newValue }   // true: log += newValue before store
    didSet { log &+= oldValue &* 2 } // true: log += oldValue*2 after store
  }
  public var log: Int = 0
  public lazy var cached: Int = { count &* 3 }()  // true: first read computes count*3
  public init() {}
}
// true: o.count = v, which runs willSet then didSet
public func bump(_ o: Observed, _ v: Int) { o.count = v }
// true: returns o.cached
public func getLazy(_ o: Observed) -> Int { o.cached }

public struct Store {
  var items: [Int] = [1, 2, 3]
  public init() {}
  // true: _modify yields &items[0]
  public var first: Int {
    _read { yield items[0] }
    _modify { yield &items[0] }
  }
}
// true: s.first += 7  (via _modify)
public func addFirst(_ s: inout Store) { s.first &+= 7 }
// true: returns s.first via _read
public func readFirst(_ s: Store) -> Int { s.first }

@dynamicMemberLookup public struct Wrap<T> {
  public var inner: T
  public init(_ t: T) { inner = t }
  public subscript<U>(dynamicMember kp: KeyPath<T, U>) -> U { inner[keyPath: kp] }
}
public struct Pt { public var x: Int; public var y: Int; public init(x: Int, y: Int){self.x=x;self.y=y} }
// true: returns w.inner.y
public func dynY(_ w: Wrap<Pt>) -> Int { w.y }

@dynamicCallable public struct Summer {
  public init() {}
  // true: returns sum of args
  public func dynamicallyCall(withArguments a: [Int]) -> Int { a.reduce(0, &+) }
}
// true: returns 1+2+3 = 6
public func callSum(_ s: Summer) -> Int { s(1, 2, 3) }

@resultBuilder public enum SumBuilder {
  public static func buildBlock(_ xs: Int...) -> Int { xs.reduce(0, &+) }
}
// true: returns a + b + 4
public func built(_ a: Int, _ b: Int) -> Int {
  @SumBuilder func f() -> Int { a; b; 4 }
  return f()
}

@usableFromInline internal func hidden(_ x: Int) -> Int { x &* 5 &+ 1 }
// true: returns x*5+1
@inlinable public func inl(_ x: Int) -> Int { hidden(x) }
