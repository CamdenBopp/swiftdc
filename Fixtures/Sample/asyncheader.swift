// A caller fills in each new callee async context's header, Parent at
// +0 and ResumeParent at +8, before it calls (swift/lib/IRGen/GenCall.cpp).
// At -O the two words go in one `stp x22, resume, [x0]` straight after
// `swift_task_alloc`; at -Onone the block is moved into x22 first and
// each word stored alone. True behaviour: no source statement stores
// anything; `twice` is `await work(k) &+ (await work(k &+ 1))`.
@inline(never) func work(_ k: Int) async -> Int { k &* 3 }
public func twice(_ k: Int) async -> Int { await work(k) &+ (await work(k &+ 1)) }
public func pass(_ k: Int) async -> Int { await work(k) }
