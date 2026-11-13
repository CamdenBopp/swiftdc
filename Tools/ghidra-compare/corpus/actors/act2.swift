// Actor/concurrency ABI probe fixture 2.
public actor Bank {
    public var balance: Int = 100
    public init() {}
    // True: deposits into other (cross-actor await), then returns own balance - amt.
    public func transfer(_ amt: Int, to other: Bank) async -> Int {
        balance -= amt
        await other.deposit(amt)
        return balance
    }
    public func deposit(_ amt: Int) { balance += amt }
    // True: nonisolated async: hops to generic, returns x + 1 (no actor state).
    public nonisolated func plain(_ x: Int) async -> Int { x + 1 }
}

// True: reads actor property from outside: await b.balance.
public func readBalance(_ b: Bank) async -> Int { await b.balance }

// True: runs closure on main actor returning x * 2.
public func onMain(_ x: Int) async -> Int { await MainActor.run { x * 2 } }

// True: assumeIsolated on MainActor, returns x + 5.
@MainActor public var mainCounter = 0
public func assume(_ x: Int) -> Int {
    MainActor.assumeIsolated { mainCounter += x; return mainCounter }
}

// True: cancellation handler wraps op returning x; onCancel does nothing observable.
public func withHandler(_ x: Int) async -> Int {
    await withTaskCancellationHandler { x &+ 11 } onCancel: { }
}

// True: yields once then returns x.
public func yielder(_ x: Int) async -> Int { await Task.yield(); return x }

public struct Boom: Error { public let code: Int }
// True: throwing group; child i throws Boom(code: i) when i == 3; sums otherwise.
public func throwingGroup(_ n: Int) async throws -> Int {
    try await withThrowingTaskGroup(of: Int.self) { g in
        for i in 0..<n { g.addTask { if i == 3 { throw Boom(code: i) }; return i } }
        var s = 0
        for try await v in g { s += v }
        g.cancelAll()
        return s
    }
}

// True: builds stream yielding 1,2,3 then finishing.
public func makeStream() -> AsyncThrowingStream<Int, Error> {
    AsyncThrowingStream { c in c.yield(1); c.yield(2); c.yield(3); c.finish() }
}

public enum Ctx { @TaskLocal public static var id: Int = 0 }
// True: binds Ctx.id = x for the op, returns Ctx.id read inside (== x).
public func withLocal(_ x: Int) async -> Int {
    await Ctx.$id.withValue(x) { Ctx.id }
}

// True: high-priority task returning 7; caller awaits its value.
public func highTask() async -> Int {
    let t = Task(priority: .high) { 7 }
    return await t.value
}

// True: cancels task t.
public func cancelIt(_ t: Task<Int, Never>) { t.cancel() }

// True: Task on MainActor, sets mainCounter = 1.
public func mainTask() -> Task<Void, Never> { Task { @MainActor in mainCounter = 1 } }

@MainActor public final class VM {
    public var items: [Int] = []
    public init() {}
    // True: awaits Task.sleep then appends x; back on MainActor after the await.
    public func load(_ x: Int) async throws { try await Task.sleep(nanoseconds: 10); items.append(x) }
    // True: nonisolated, returns 9.
    public nonisolated func nine() -> Int { 9 }
}
