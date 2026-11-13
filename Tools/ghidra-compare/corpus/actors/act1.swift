// Actor/concurrency ABI probe fixture.
public actor Counter {
    public var value: Int = 0
    public init() {}
    // True: value += by; returns new value.
    public func bump(_ by: Int) -> Int { value += by; return value }
    // True: returns 42 constant, no isolation hop needed.
    public nonisolated func fixed() -> Int { 42 }
    // True: returns by * 3, nonisolated.
    public nonisolated func triple(_ by: Int) -> Int { by * 3 }
}

// True: awaits c.bump(5) (hop to actor), returns result + 1.
public func callBump(_ c: Counter) async -> Int {
    let r = await c.bump(5)
    return r + 1
}

@MainActor public final class Model {
    public var count = 0
    public init() {}
    // True: count += 1 on main actor.
    public func inc() { count += 1 }
}

// True: hops to main actor, calls m.inc().
public func touchModel(_ m: Model) async {
    await m.inc()
}

@MainActor public func mainOnly(_ x: Int) -> Int { x + 7 }

// True: sums 0..<n children, each child returns i*2.
public func groupSum(_ n: Int) async -> Int {
    await withTaskGroup(of: Int.self) { g in
        for i in 0..<n { g.addTask { i * 2 } }
        var s = 0
        for await v in g { s += v }
        return s
    }
}

// True: async let a = x+1, b = x+2; returns a*b.
public func asyncLetMul(_ x: Int) async -> Int {
    async let a = x + 1
    async let b = x + 2
    return await a * b
}

// True: resumes continuation with x*10.
public func cont(_ x: Int) async -> Int {
    await withCheckedContinuation { c in c.resume(returning: x * 10) }
}

// True: unsafe continuation resumed with x + 100.
public func ucont(_ x: Int) async -> Int {
    await withUnsafeContinuation { c in c.resume(returning: x + 100) }
}

// True: throwing continuation: throws if x < 0 else returns x.
public struct E: Error {}
public func tcont(_ x: Int) async throws -> Int {
    try await withCheckedThrowingContinuation { c in
        if x < 0 { c.resume(throwing: E()) } else { c.resume(returning: x) }
    }
}

// True: sums elements of stream.
public func sumStream(_ s: AsyncStream<Int>) async -> Int {
    var t = 0
    for await v in s { t += v }
    return t
}

// True: spawns Task that calls c.bump(1); returns the task.
public func spawn(_ c: Counter) -> Task<Int, Never> {
    Task { await c.bump(1) }
}

public func spawnDetached(_ x: Int) -> Task<Int, Never> {
    Task.detached { x &* 9 }
}

// True: sleeps 1ms then returns x.
public func napper(_ x: Int) async throws -> Int {
    try await Task.sleep(nanoseconds: 1_000_000)
    return x
}

// True: returns 1 if cancelled else 0.
public func cancelled() -> Int { Task.isCancelled ? 1 : 0 }

// True: throws CancellationError if cancelled, else returns x.
public func checkCancel(_ x: Int) async throws -> Int {
    try Task.checkCancellation()
    return x
}

// True: isolated parameter: c.value + 1, no hop.
public func isoRead(_ c: isolated Counter) -> Int { c.value + 1 }

// True: #isolation passed through.
public func passIso(_ x: Int, isolation: isolated (any Actor)? = #isolation) async -> Int { x + 3 }

@globalActor public actor MyGA { public static let shared = MyGA() }
@MyGA public func gaFunc(_ x: Int) -> Int { x - 4 }
public func callGA(_ x: Int) async -> Int { await gaFunc(x) }

public final class SerialExec: SerialExecutor {
    public func enqueue(_ job: consuming ExecutorJob) { job.runSynchronously(on: asUnownedSerialExecutor()) }
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor { UnownedSerialExecutor(ordinary: self) }
}
public actor CustomExecActor {
    let ex = SerialExec()
    public nonisolated var unownedExecutor: UnownedSerialExecutor { ex.asUnownedSerialExecutor() }
    public var n = 5
    public func get() -> Int { n }
}
