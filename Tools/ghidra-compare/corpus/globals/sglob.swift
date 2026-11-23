// Swift globals fixture. True behaviour per function.
import Foundation
public var gCount: Int = 0                 // statically initialised at -O (no once)
public let gTable: [Int] = [1, 2, 3, 4]    // lazy: swift_once + _WZ + unsafeMutableAddressor
public var gName = String(repeating: "a", count: 3) // lazy, dynamic init
public struct Config { public static let shared = Config(x: 7, y: 9); public var x: Int; public var y: Int
  public static var counter = 0 }
public enum Mode { public static let defaultName = "fast" }
public final class Box<T> { public static var label: String { "box" } }
@MainActor public var mainCounter = 3
public struct Pair { public var a: Int; public var b: Int }
public var gPair = Pair(a: 1, b: 2)

// increments gCount by 1 and returns the new value (dynamic exclusivity: modify access at -Onone/-O)
@inline(never) public func bumpCount() -> Int { gCount += 1; return gCount }
// returns gTable[i] (bounds checked)
@inline(never) public func tableAt(_ i: Int) -> Int { gTable[i] }
// returns gName.count
@inline(never) public func nameCount() -> Int { gName.count }
// returns Config.shared.y (9)
@inline(never) public func sharedY() -> Int { Config.shared.y }
// Config.counter += n
@inline(never) public func addCounter(_ n: Int) { Config.counter += n }
// returns Mode.defaultName
@inline(never) public func modeName() -> String { Mode.defaultName }
// gPair.b = v ; returns gPair.a
@inline(never) public func setPairB(_ v: Int) -> Int { gPair.b = v; return gPair.a }
@MainActor @inline(never) public func bumpMain() -> Int { mainCounter += 1; return mainCounter }
// reads gCount twice around an opaque call: values may differ
@inline(never) public func readTwice(_ f: () -> Void) -> Int { let a = gCount; f(); return a &+ gCount }
@_cdecl("c_entry") public func cEntry(_ x: Int32) -> Int32 { x &* 2 }
@_silgen_name("custom_silgen_fn") public func silgenFn(_ x: Int) -> Int { x &+ 5 }
