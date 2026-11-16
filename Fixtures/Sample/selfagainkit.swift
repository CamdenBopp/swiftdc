// The types selfagain.swift calls from another module, so each call is an
// import with no body to summarize: only the callee's name says whether it
// takes self in x20.
public final class Box {
    public var a = 1
    public var b = 2
    public init() {}
    @inline(never) public func m1() -> Int { a &* 3 }
    @inline(never) public func m2() -> Int { b &* 5 }
    @inline(never) public static func make() -> Int { 7 }
}


public struct Pair {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    @inline(never) public func sum(_ z: Int) -> Int { x &+ y &+ z }
}


public enum Mode {
    case slow, fast, off
    @inline(never) public func code() -> Int {
        switch self { case .slow: 10; case .fast: 20; case .off: 30 }
    }
}
