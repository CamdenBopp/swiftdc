// Await-resume return probes. Each returns its argument x after awaiting.
@inline(never) public func sink() async {}
@inline(never) public func sinkT() async throws {}
// True: returns x.
public func r1(_ x: Int) async -> Int { await sink(); return x }
// True: returns x (throws only if sinkT throws).
public func r2(_ x: Int) async throws -> Int { try await sinkT(); return x }
// True: returns x after Task.yield.
public func r3(_ x: Int) async -> Int { await Task.yield(); return x }
// True: returns x after Task.sleep (throws).
public func r4(_ x: Int) async throws -> Int { try await Task.sleep(nanoseconds: 1); return x }
// True: returns x + y after await.
public func r5(_ x: Int, _ y: Int) async -> Int { await sink(); return x &+ y }
