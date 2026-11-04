// Built with library evolution: a resilient class and a base for one.

open class KitBase { public final var r = 1; public init() {} }
public final class KitHolder { public final var v = 5; public final var w = 6; public init() {} }
public func readKit(_ h: KitHolder) -> Int { h.v + 1 }
public func writeKit(_ h: KitHolder, _ x: Int) { h.w = x }
