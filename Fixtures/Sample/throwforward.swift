// A throwing function whose last act is a throwing call: `bl`, its
// epilogue, `ret` (-O). x21 at the `ret` is the callee's error and the
// result registers are its result, so the exit is the callee's outcome:
// `return try callee(…)`, neither a proven return nor a throw. Each read
// `machine_return() /* unresolved Swift success/error exit */`.
// - `Reader.count()`, `Reader.ratio()` and `Reader.title()` are witnesses
//   of `Source` forwarding to the type's own methods: an Int in x0, a
//   Double in d0, a String in x0 and x1.
// - `Reader.shifted()` adds 1 to the result, and checks nothing: on an
//   error the caller ignores x0, so it is `return try (count() + 1)`.
// - `Reader.combined()` adds `bump()`, called first. It hands count() a
//   copy of its entry x21 (`mov x19, x21` ... `mov x21, x19`), which the
//   zero proof does not follow, so it stays unresolved.
public struct Refused: Error {}

public protocol Source {
    func count() throws -> Int
    func ratio() throws -> Double
    func title() throws -> String
}

public struct Reader: Source {
    public var limit: Int
    public var name: String
    public init(limit: Int, name: String) { self.limit = limit; self.name = name }
    @inline(never) public func count() throws -> Int {
        if limit < 0 { throw Refused() }
        return limit &* 2
    }
    @inline(never) public func ratio() throws -> Double {
        if limit == 0 { throw Refused() }
        return 1 / Double(limit)
    }
    @inline(never) public func title() throws -> String {
        if name.isEmpty { throw Refused() }
        return name + "!"
    }
    @inline(never) public func shifted() throws -> Int { try count() &+ 1 }
    @inline(never) public func combined() throws -> Int {
        let before = bump()
        return try count() &+ before
    }
}

public final class Tally { public var hits = 0; public init() {} }
public let tally = Tally()
@inline(never) public func bump() -> Int {
    tally.hits &+= 1
    return tally.hits
}
