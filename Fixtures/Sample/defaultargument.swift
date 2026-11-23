// A default argument's generator is its own function with no parameters:
// `default argument 1 of scale(_:by:)` is `mov w0, #7; ret`, lowered
// `define … i64 @"…fA0_"()`. Its name carries scale's parameter list,
// which is not its own. -Onone, where the generator is not inlined.
public func scale(_ x: Int, by k: Int = 7) -> Int { x &* k }
public func use(_ x: Int) -> Int { scale(x) }
