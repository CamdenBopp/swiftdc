// Accessors of function-typed storage (-O and -Onone).
//
// The demangler prints an accessor as `name.getter : Type`. When the
// type is a function type its arrow belongs to the storage, not to the
// accessor: the getter takes only self and returns a closure (two
// words, code and context), and the setter takes that closure as its
// one new value. A subscript's accessor is different: its printed type
// is its signature. Each accessor's true behaviour is its declaration.

public final class Panel {
    // getter: () -> closure. setter: (closure) -> ().
    public var combine: (Int, Int) -> Int = { $0 &+ $1 }
    // A throwing function type: the accessors themselves do not throw.
    public var attempt: (Int) throws -> Int = { $0 }
    // The setter has work after the store: tally += 1.
    public var watched: (Int) -> Int = { $0 } { didSet { tally &+= 1 } }
    public var tally: Int = 0
    public init() {}
}

public struct Grid {
    public var cells: [Int]
    public var width: Int
    // The control: the accessor's printed type is (Int, Int) -> Int, and
    // it does take two Ints, after self.
    public subscript(_ row: Int, _ column: Int) -> Int { cells[row &* width &+ column] }
}

@inline(never) public func install(_ panel: Panel, _ f: @escaping (Int, Int) -> Int) { panel.combine = f }
@inline(never) public func observe(_ panel: Panel, _ f: @escaping (Int) -> Int) { panel.watched = f }
@inline(never) public func cell(_ grid: Grid, _ row: Int) -> Int { grid[row, 2] }
