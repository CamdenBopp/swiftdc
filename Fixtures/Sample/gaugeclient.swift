// Calls GaugeKit's requirements through their dispatch thunks (-O).
// True behaviour: `readLevel` calls `level.getter` with no argument (x0 and
// x1 are A's metadata and witness table); `readScaled` calls
// `scaled(by: f)` with one argument, f, in x0; `label` passes the String
// `name.getter` returns, both words, to `count(of:)`.
import GaugeKit

@inline(never) public func readLevel<G: Gauge>(_ g: G) -> Int { g.level }
@inline(never) public func readScaled(_ g: any Gauge, _ f: Int) -> Int { g.scaled(by: f) }
@inline(never) public func count(of s: String) -> Int { s.utf8.count }
@inline(never) public func label(_ g: any Gauge) -> Int { count(of: g.name) }
