import Foundation

// An @objc thunk bridges each String, Array, Set and Dictionary parameter with
// `static (extension in Foundation):…_unconditionallyBridgeFromObjectiveC`,
// which takes one word in x0 (and, for a generic collection, its element
// metadata after it). The thunk leaves its other parameters in x1 and up.
@objc public class Bridged: NSObject {
    @objc public var name: String = ""
    @objc public var tags: [String] = []
    @objc public func middle(_ x: Int, s: String, _ y: Int) -> Int { x &+ s.utf8.count &+ y }
    @objc public func first(_ a: [Int], _ b: Set<String>, _ c: Data) -> Int { a.count &+ b.count &+ c.count }
    @objc public func optional(_ o: String?, _ a: [Int]?) -> Int { (o?.utf8.count ?? 0) &+ (a?.count ?? 0) }
}
