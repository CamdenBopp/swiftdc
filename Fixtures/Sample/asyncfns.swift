// Fixture exercising swiftdc's handling of Swift async functions. The compiler
// splits an async function at every suspension point into an entry funclet
// plus one resume funclet per `await`, reached through the async function
// pointer record (`Tu` symbol) and through resume addresses stored into the
// async context before the tail call into the callee or `swift_task_switch`.
// In a stripped build those funclets have no symbol at all; only
// LC_FUNCTION_STARTS and the stores that target them remain.
//
// Built by `build.sh` into `libAsyncFns.dylib` (-Onone -g),
// `libAsyncFns.opt.dylib` (-O), and `libAsyncFns.opt.stripped.dylib`.
//
// Keep the shapes stable: `AsyncFuncletTests.swift` asserts exact funclet
// counts and rendered output.

// Marked @inline(never) so the -O build keeps every call as a real suspension
// instead of inlining the callee's body into the caller.

// MARK: - Leaves (no suspension: one funclet each)

@inline(never)
public func fetchValue(_ x: Int) async -> Int { x &* 3 }

@inline(never)
public func fetchOther(_ x: Int) async -> Int { x &+ 7 }

// MARK: - One suspension: entry + one resume funclet

@inline(never)
public func oneAwait(_ x: Int) async -> Int {
    let v = await fetchValue(x)
    return v &+ 1
}

// MARK: - Two suspensions: entry + two resume funclets

@inline(never)
public func twoAwaits(_ x: Int) async -> Int {
    let a = await fetchValue(x)
    let b = await fetchOther(a)
    return a &+ b
}

// MARK: - Throwing async: the error path adds a different lowering

public enum FetchError: Error { case bad }

@inline(never)
public func fetchOrThrow(_ x: Int) async throws -> Int {
    if x < 0 { throw FetchError.bad }
    return x
}

@inline(never)
public func awaitThrowing(_ x: Int) async throws -> Int {
    let v = try await fetchOrThrow(x)
    return v &* 2
}

// MARK: - Actor hop plus await: both resume kinds in one function

// Isolated to the main actor, so returning from the nonisolated callee needs a
// hop back (a `swift_task_switch` continuation funclet) after the await-return
// funclet. Exercises both kinds and their shared numbering.
@MainActor
@inline(never)
public func onMainAwait(_ x: Int) async -> Int {
    let v = await fetchValue(x)
    return v &+ 1
}

// MARK: - Negative controls: synchronous neighbours must not be grouped

public func syncNeighbour(_ x: Int) -> Int { x &* 3 }

public func syncCaller(_ x: Int) -> Int { syncNeighbour(x) &+ 1 }
