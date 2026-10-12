// Nested range loops with a filter, trigonometry and an array append (-O).
// The value tracer stores an unknown register sometimes as `.unknown` and
// sometimes as absent; comparing block states literally saw x9 flip between
// the two and never reached a fixpoint. Shape reduced from an app audit.
import Foundation
public struct Point: Sendable { public var a: Double; public var b: Double
    public init(a: Double, b: Double) { self.a = a; self.b = b } }
public enum Sampler {
    public static func disk(around c: Point, radius: Double) -> [Point] {
        guard radius > 0 else { return [c] }
        let r = radius / 6371.0
        var out = [Point]()
        for i in -10...10 { for j in -10...10 where i * i + j * j <= 100 {
            let d = hypot(Double(i), Double(j)) / 10 * r, t = atan2(Double(i), Double(j))
            let la = c.a * .pi / 180, lo = c.b * .pi / 180
            let p = asin(sin(la) * cos(d) + cos(la) * sin(d) * cos(t))
            let q = lo + atan2(sin(t) * sin(d) * cos(la), cos(d) - sin(la) * sin(p))
            out.append(.init(a: p * 180 / .pi, b: (q * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180))
        }}
        return out
    }
}
