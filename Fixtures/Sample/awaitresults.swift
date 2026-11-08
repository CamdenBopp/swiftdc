// Awaits whose result does not come back in x0 alone. A direct async result
// is passed to the resume funclet in x0 (or v0); a generic or too-large
// result is written into a buffer the caller passed in, a String arrives in
// x0 and x1, and the runtime's future and async-let waits write their result
// into a buffer and resume with x0 holding nothing of it. True behaviour:
// each `use…` passes the awaited value (or a field of it) to `sink`, and
// only `useInt` may name x0 at its resume as the result.
public struct Big5 { public var a, b, c, d, e: Int }

@inline(never) public func sink(_ x: Int) { print("sink", x) }
@inline(never) public func sinkString(_ s: String) { print("sink", s) }

@inline(never) public func intResult(_ x: Int) async -> Int { await Task.yield(); return x &+ 1 }
// Never specialized, so `useGeneric` calls the generic body with T = Int.
@_semantics("optimize.sil.specialize.generic.never")
@inline(never) public func genericResult<T>(_ x: T) async -> T { await Task.yield(); return x }
@inline(never) public func bigResult(_ x: Int) async -> Big5 {
    await Task.yield()
    return Big5(a: x, b: x &+ 1, c: 3, d: 4, e: 5)
}
@inline(never) public func stringResult(_ x: Int) async -> String { await Task.yield(); return String(x) }
@inline(never) public func optionalResult(_ x: Int) async -> Int? { await Task.yield(); return x < 0 ? nil : x }

// Control: an Int result is in x0 at the resume.
public func useInt(_ x: Int) async { sink(await intResult(x) &+ 2) }
// `T` is an opaque generic: the callee writes it through the buffer in x0.
public func useGeneric(_ x: Int) async { sink(await genericResult(x) &+ 3) }
// Five words: written into the caller's buffer.
public func useBig(_ x: Int) async { sink(await bigResult(x).b &+ 4) }
// Two words, x0 and x1.
public func useString(_ x: Int) async { sinkString(await stringResult(x)) }
// Payload in x0, nil tag in x1.
public func useOptional(_ x: Int) async { sink(await optionalResult(x) ?? 5) }
// The runtime writes a task's result into a buffer.
public func useTaskValue(_ t: Task<Int, Never>) async { sink(await t.value &+ 6) }
// The async-let's result lives in the child task's buffer.
public func useAsyncLet(_ x: Int) async {
    async let v = intResult(x)
    sink(await v &+ 7)
}
// The async-let child closure returns `Swift.Int` through an indirect
// buffer, and its name's last arrow is the enclosing function's result.
public func useAsyncLetReturning(_ x: Int) async -> Int {
    async let v = intResult(x)
    return await v &+ 8
}
