// Own source: -Osize outlines the context-header stores and x22 handoff
// into a leaf helper: stp x22,x8,[x0]; mov x22,x0; ret. The async index
// must prove those physical effects before attaching either resume.
// The sum also records the separate, still-open carried-result problem.
nonisolated(unsafe) private var leftValue: Int64 = 0
nonisolated(unsafe) private var rightValue: Int64 = 0
public func configure(_ left: Int64, _ right: Int64) { leftValue = left; rightValue = right }
@inline(never) public func first() async -> Int64 { await Task.yield(); return leftValue }
@inline(never) public func second() async -> Int64 { await Task.yield(); return rightValue }
@inline(never) public func sequence() async -> Int64 { await first() &+ (await second()) }
