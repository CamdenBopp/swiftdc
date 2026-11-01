// A class subscript's getter takes its index as a method takes its own
// parameters: `g[i]` calls `Grid.subscript.getter : (Swift.Int) -> Swift.Int`
// with `self` in x20 and `i` in x0. Built -Onone so the call stays.
// True behaviour: `read(g, i)` returns `g[i]`, one index argument.
public final class Grid {
    var cells = [1, 2, 3]
    public init() {}
    public subscript(i: Int) -> Int { cells[i] }
}

@inline(never) public func read(_ g: Grid, _ i: Int) -> Int { g[i] }
