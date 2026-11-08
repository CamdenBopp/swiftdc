// The two-function reduction of a class parameter's field access, small enough
// that -Osize's outliner shares no prologue fragment between functions.

public final class Holder { public var v = 5; public init() {} }
public func readHolder(_ h: Holder) -> Int { h.v + 1 }
public func writeHolder(_ h: Holder, _ x: Int) { h.v = x }
