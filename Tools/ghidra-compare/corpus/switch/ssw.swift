// Swift switch lowerings. Truth stated per function.
@inline(never) public func sink(_ x: Int) { print(x) }

// dense Int, cases return constants: 0->10, 1->31, 2->52, 3->73, 4->94, 5->15, 6->36; else -1
public func constReturn(_ x: Int) -> Int {
  switch x {
  case 0: return 10
  case 1: return 31
  case 2: return 52
  case 3: return 73
  case 4: return 94
  case 5: return 15
  case 6: return 36
  default: return -1
  }
}
// dense biased Int with distinct side effects: x in 20...27 -> sink(x*7 + 1 distinct constants) else sink(0)
public func biasCalls(_ x: Int) {
  switch x {
  case 20: sink(201)
  case 21: sink(212)
  case 22: sink(223)
  case 23: sink(234)
  case 24: print("twenty-four")
  case 25: sink(256)
  case 26: print("twenty-six")
  case 27: sink(278)
  default: sink(0)
  }
}
// ranges: 1...5 -> "low", 6..<10 -> "mid", 10...100 -> "high", else "other"; returns 1,2,3,0
public func ranges(_ x: Int) -> Int {
  switch x {
  case 1...5: return 1
  case 6..<10: return 2
  case 10...100: return 3
  default: return 0
  }
}
// tuple: (0,0)->1, (0,_)->2, (_,0)->3, (1,1)->4, else 5
public func tuple(_ a: Int, _ b: Int) -> Int {
  switch (a, b) {
  case (0, 0): return 1
  case (0, _): return 2
  case (_, 0): return 3
  case (1, 1): return 4
  default: return 5
  }
}
// where guards: x<0 -> -1 ; even x where x>100 -> 2 ; x>100 -> 3 ; else 0
public func guards(_ x: Int) -> Int {
  switch x {
  case let v where v < 0: return -1
  case let v where v > 100 && v % 2 == 0: return 2
  case let v where v > 100: return 3
  default: return 0
  }
}
// fallthrough: 0 -> sink(1),sink(2) ; 1 -> sink(2) ; 2 -> sink(3) ; else nothing
public func fall(_ x: Int) {
  switch x {
  case 0: sink(1); fallthrough
  case 1: sink(2)
  case 2: sink(3)
  default: break
  }
}
public enum Shape {
  case circle(Double)
  case rect(Int, Int)
  case tri(Int)
  case empty
  case dot
}
// payload enum: circle -> 1, rect(w,h) -> w*h, tri(n) -> n+3, empty -> 0, dot -> 9
public func area(_ s: Shape) -> Int {
  switch s {
  case .circle: return 1
  case let .rect(w, h): return w &* h
  case let .tri(n): return n &+ 3
  case .empty: return 0
  case .dot: return 9
  }
}
// if case let: rect -> w, else -7
public func rectWidth(_ s: Shape) -> Int {
  if case let .rect(w, _) = s { return w }
  return -7
}
// guard case: tri(n) -> n, else -8
public func triOr(_ s: Shape) -> Int {
  guard case let .tri(n) = s else { return -8 }
  return n
}
public enum Op: UInt8 { case add, sub, mul, div, neg, nop, halt, push, pop, dup }
// C-like enum: add->1 sub->2 mul->3 div->4 neg->5 nop->6 halt->7 push->8 pop->9 dup->10
public func opCode(_ o: Op) -> Int {
  switch o {
  case .add: return 1
  case .sub: return 2
  case .mul: return 3
  case .div: return 4
  case .neg: return 5
  case .nop: return 6
  case .halt: return 7
  case .push: return 8
  case .pop: return 9
  case .dup: return 10
  }
}
// sparse Int: 3->1, 300->2, 3000->3, 30000->4, 300000->5 else 0
public func sparse(_ x: Int) -> Int {
  switch x {
  case 3: return 1
  case 300: return 2
  case 3000: return 3
  case 30000: return 4
  case 300000: return 5
  default: return 0
  }
}
// Character: "a" -> 1, "b" -> 2, "é" -> 3 else 0
public func charSwitch(_ c: Character) -> Int {
  switch c {
  case "a": return 1
  case "b": return 2
  case "é": return 3
  default: return 0
  }
}
// String: "red"->1 "green"->2 "blue"->3 else 0
public func strSwitch(_ s: String) -> Int {
  switch s {
  case "red": return 1
  case "green": return 2
  case "blue": return 3
  default: return 0
  }
}
// bit-test-ish: x in [1,3,5,8,13,21] -> sink(1), x in [2,4] -> sink(2) else sink(3)
public func bitset(_ x: Int) {
  switch x {
  case 1, 3, 5, 8, 13, 21: sink(1)
  case 2, 4: print("two-four")
  default: print("other")
  }
}
// in loop: op 0 -> acc+=1 ; 1 -> continue (skip acc*=3) ; 2 -> break out ; 3 -> acc -= 5 ; 4 -> sink(acc); default acc = 0 ; then acc*=3
public func loopSwitch(_ ops: [Int]) -> Int {
  var acc = 0
  outer: for op in ops {
    switch op {
    case 0: acc &+= 1
    case 1: continue
    case 2: break outer
    case 3: acc &-= 5
    case 4: sink(acc)
    default: acc = 0
    }
    acc &*= 3
  }
  return acc
}
