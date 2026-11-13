// computed getter: returns 5
public struct K { public init() {}; public var five: Int { 5 }
  // subscript: returns i + 1
  public subscript(i: Int) -> Int { i &+ 1 }
  // generic subscript: returns 7
  public subscript<T>(t: T) -> Int { 7 }
}
public final class KC { public init() {}
  // class subscript: returns i + 2
  @inline(never) public subscript(i: Int) -> Int { i &+ 2 }
  // generic class subscript: returns 8
  public subscript<T>(g t: T) -> Int { 8 }
}
// caller: returns kc[i] * 3 (non-inlined class subscript)
@inline(never) public func useKC(_ k: KC, _ i: Int) -> Int { k[i] &* 3 }
