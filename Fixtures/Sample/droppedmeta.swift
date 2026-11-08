// A generic specialization that drops its metatype parameter (`Tt`), whose
// demangled name prints like one that keeps it (-O). True behaviour:
// useTT(k, d) calls the Double specialization of tt with d in d0 and k in
// x0; tt returns k * 5 + Int(a).
@inline(never) public func tt<A: BinaryFloatingPoint>(_ t: A.Type, _ a: A, _ k: Int) -> Int { k &* 5 &+ Int(a) }
public func useTT(_ k: Int, _ d: Double) -> Int { tt(Double.self, d, k) }
