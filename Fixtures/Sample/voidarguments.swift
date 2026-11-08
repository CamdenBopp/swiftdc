// An explicit Void is a source argument with no register: `tail` is x0 in
// afterVoid, and d1 in betweenFloats. Every body differs so -O does not merge
// them into one symbol. True behaviour: each returns the expression it spells.
@inline(never) public func afterVoid(_ empty: Void, _ tail: Int) -> Int { tail &+ 1 }
@inline(never) public func afterQualifiedVoid(_ empty: Swift.Void, _ tail: Int) -> Int { tail &+ 2 }
@inline(never) public func afterVoids(_ first: (), _ second: Swift.Void, _ tail: Int) -> Int { tail &+ 3 }
@inline(never) public func betweenIntegers(_ first: Int, _ empty: (), _ tail: Int) -> Int { first &- tail }
@inline(never) public func betweenFloats(_ first: Double, _ empty: Swift.Void, _ tail: Double) -> Double { first - tail }
