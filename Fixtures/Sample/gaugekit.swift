// A resilient protocol: a client in another module calls its requirements
// through dispatch thunks (`dispatch thunk of GaugeKit.Gauge.scaled(by:)`),
// which take `self` in x20, the formal parameters from x0, and the Self
// metadata and witness table after them.
public protocol Gauge {
    var level: Int { get }
    func scaled(by factor: Int) -> Int
    var name: String { get }
}

public struct Tank: Gauge {
    public var level: Int
    public init(level: Int) { self.level = level }
    public func scaled(by factor: Int) -> Int { level * factor }
    public var name: String { "tank" }
}
