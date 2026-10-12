// Fixture for an async context slot whose address escapes. A `var` live
// across an await lives in a slot of the async context; passing it `inout`
// hands the slot's address (`add x0, x22, #off`) to the callee, which writes
// it. One store into the slot in the chain then no longer proves its value.
//
// Built by `build.sh` into `libAsyncInout.dylib` (-O).

@inline(never) public func syncBump(_ x: inout Int) { x &+= 11 }

public func inoutSync(_ a: Int) async -> Int {
    var n = a &* 3
    await Task.yield()
    syncBump(&n)
    return n
}

@inline(never) public func bump(_ x: inout Int) async { x &+= 7; await Task.yield() }

public func inoutAcross(_ a: Int) async -> Int {
    var n = a &* 3
    await bump(&n)
    return n
}
