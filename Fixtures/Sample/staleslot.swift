// `n` lives in the async context. After the await, the await-return funclet
// reloads its own context from the callee's (`ldr x19, [x22]`) and passes
// `&n` as `x19 + 0x10`. bump writes the slot; the later load sees 18, not 7.
@inline(never) public func bump(_ x: inout Int) { x &+= 11 }
@inline(never) nonisolated(nonsending) public func g(_ a: Int) async -> Int {
    await Task.yield()
    return a &+ 5
}

nonisolated(nonsending) public func f1(_ a: Int) async -> Int {
    var n = 7
    let r = await g(a)
    bump(&n)
    return n &+ r
}
