import ClassParamKit
import ClassParamTwin

// A class over a resilient base: its field offsets are `Wvd` globals.
public final class Over: KitBase { public final var x = 9; public final var y = 10; public override init() { super.init() } }
public func readOver(_ o: Over) -> Int { o.y + 1 }
public func writeOver(_ o: Over, _ v: Int) { o.x = v }

// Two classes named Twin. This module's map must not answer for the other's.
public final class Twin { public var other = 1; public init() {} }
public func readForeignTwin(_ t: ClassParamTwin.Twin) -> Int { t.second + 2 }
public func writeForeignTwin(_ t: ClassParamTwin.Twin, _ x: Int) { t.first = x }
public func readOwnTwin(_ t: Twin) -> Int { t.other + 3 }

// A class named like another module's struct, which a signature here mentions.
public final class Pair { public var mine = 1; public init() {} }
public func readOwnPair(_ p: Pair) -> Int { p.mine + 6 }
public func makeForeignPair() -> ClassParamTwin.Pair { ClassParamTwin.Pair() }
