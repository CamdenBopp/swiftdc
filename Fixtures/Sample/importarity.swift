// importarity.c's shapes through `@_silgen_name` imports (-O). The caller's
// Swift signature says nothing about the import's parameters.
// t1: nothing sets x0 for ext_h0. d4: x1 is the entry value of b, not an
// argument of ext_one; ext_one's result plus b is the function's result.
@_silgen_name("ext_g0") func g0() -> Int
@_silgen_name("ext_h0") func h0()
@_silgen_name("ext_one") func ext(_ a: Int) -> Int

public func t1() { _ = g0(); h0() }
public func d4(_ a: Int, _ b: Int) -> Int { ext(1) &+ b }
