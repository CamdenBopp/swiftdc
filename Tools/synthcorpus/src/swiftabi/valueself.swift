// LEVELS: O Osize Onone
// Value-type self passed directly in registers (non-mutating methods on
// loadable structs and enums take self exploded into x0-x3 / d0-d3).
// TRUE behaviour, per call site:
//   callLength: Point.length with self = (3.5, 4.25) in d0, d1 (tail call at -O).
//   callScaled: Mixed.scaled with self.n = 7 in x0 and self.d = 2.5 in d0.
//   callSum:    Quad.sum with self = (11, 22, 33, 44) in x0-x3.
//   callArea:   Shape.area with payload (2.0, 8.0) as bit patterns in x0, x1
//               and the case tag 1 (.rect) in w2.
//   callWeight: Named.weight with the String in x0, x1 (the caller's own
//               argument, untouched) and count 3 in x2.
//   callTotal:  Bag.total with the array buffer, the caller's arg0, in x0.
//   callBoxGet: Box<Int>.get is specialized and folded: returns 42. At -Onone
//               the generic get takes self indirectly: x20 = address of a local.
// A correct render never drops the receiver: `length()` with no self reads
// as a static call. It shows the receiver or declines it as `self: ?`.
//
// Expected to pass only after the value-self fix (not in swiftdc-sa2):
// EXPECT structured O,Osize callLength :: length(self: (3.5, 4.25))
// FORBID structured * callLength :: re:Point\.length\(\)
// EXPECT structured * callScaled :: scaled(self:
// FORBID structured * callScaled :: re:Mixed\.scaled\(\)
// EXPECT structured * callArea :: area(self:
// FORBID structured * callArea :: re:Shape\.area\(\)
// FORBID structured Onone callBoxGet :: re:Box\.get\(\)
//
// Passing today:
// EXPECT structured O,Osize callSum :: sum(self: (11, 22, 33, 44))
// FORBID structured * callSum :: re:Quad\.sum\(\)
// EXPECT structured O,Osize callWeight :: re:weight\(self: \((\?|arg0), (\?|arg1), 3\)\)
// FORBID structured * callWeight :: weight(self: 3)
// EXPECT structured O,Osize callTotal :: total(self: arg0)
// EXPECT structured O,Osize callBoxGet :: return 42
// EXPECT structured * Point.length() :: sqrt(
// EXPECT structured O,Osize Quad.sum() :: ((self.b + self.a) + (self.c + self.d))
// EXPECT structured O,Osize Shape.area() :: re:\(\(w2 & 0xff\) == 0\)|\(\(arg2 & 0xff\) == 0\)
@inline(never) public func sinkD(_ x: Double) { print(x) }
@inline(never) public func sinkI(_ x: Int) { print(x) }

public struct Point { public var x: Double; public var y: Double
  public init(x: Double, y: Double) { self.x = x; self.y = y }
  @inline(never) public func length() -> Double { (x * x + y * y).squareRoot() } }
public func callLength() -> Double { Point(x: 3.5, y: 4.25).length() }

public struct Mixed { public var n: Int; public var d: Double
  public init(n: Int, d: Double) { self.n = n; self.d = d }
  @inline(never) public func scaled() -> Double { Double(n) * d } }
public func callScaled() -> Double { Mixed(n: 7, d: 2.5).scaled() }

public struct Quad { public var a, b, c, d: Int
  public init(a: Int, b: Int, c: Int, d: Int) { self.a = a; self.b = b; self.c = c; self.d = d }
  @inline(never) public func sum() -> Int { a &+ b &+ c &+ d } }
public func callSum() -> Int { Quad(a: 11, b: 22, c: 33, d: 44).sum() }

public enum Shape { case circle(Double), rect(Double, Double), empty
  @inline(never) public func area() -> Double {
    switch self { case .circle(let r): return r * r * 3.0
                  case .rect(let w, let h): return w * h
                  case .empty: return 0 } } }
public func callArea() -> Double { Shape.rect(2.0, 8.0).area() }

public struct Named { public var name: String; public var count: Int
  public init(name: String, count: Int) { self.name = name; self.count = count }
  @inline(never) public func weight() -> Int { name.utf8.count &* count } }
public func callWeight(_ s: String) -> Int { Named(name: s, count: 3).weight() }

public struct Bag { public var items: [Int]
  public init(items: [Int]) { self.items = items }
  @inline(never) public func total() -> Int { var t = 0; for i in items { t &+= i }; return t } }
public func callTotal(_ a: [Int]) -> Int { Bag(items: a).total() }

public struct Box<T> { public var value: T
  public init(value: T) { self.value = value }
  @inline(never) public func get() -> T { value } }
public func callBoxGet() -> Int { Box(value: 42).get() }
