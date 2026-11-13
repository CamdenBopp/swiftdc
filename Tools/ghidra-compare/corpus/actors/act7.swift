// MainActor hop shapes.
@MainActor @inline(never) public func mainOnly(_ x: Int) -> Int { x &+ 7 }
// True: hops to the main actor, calls mainOnly(x), hops back to generic.
public func callMain(_ x: Int) async -> Int { await mainOnly(x) }
@MainActor public func mainAsync(_ x: Int) async -> Int { x &+ 1 }
// True: an @MainActor async function: hops to main on entry.
@MainActor public func mainAsync2(_ x: Int) async -> Int { await Task.yield(); return x &+ 1 }
