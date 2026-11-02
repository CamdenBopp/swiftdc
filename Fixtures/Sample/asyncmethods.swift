// Async class methods and an async protocol requirement, built -O and
// stripped (`strip -x`), so every internal name must come from metadata.
//
// The lowering under test: an async method's vtable entry and method
// descriptor do not point at code. `MethodDescriptorFlags::IsAsync` (0x40)
// makes the descriptor's implementation an `AsyncImpl` relative pointer to an
// async function pointer record, `{ int32 relative Function;
// uint32 ExpectedContextSize }`, in data; the entry funclet is where that
// record's first field leads. An override follows its base method's flag, and
// a witness table slot for a requirement with `ProtocolRequirementFlags::
// IsAsync` (0x20) holds the witness's async function pointer.
//
// True behaviour: `Animal.fetch()`'s entry funclet is a function named from
// metadata; the async function pointer beside it is data and is named as
// nothing. The synchronous `legs()` and its override keep the code address
// their descriptors name directly.

func work(_ n: Int) async -> Int {
    await Task.yield()
    return n &* 3
}

class Animal {
    var count = 1
    func legs() -> Int { count &+ 4 }
    func fetch() async -> Int {
        let a = await work(count)
        return a &+ 1
    }
    func rest(_ n: Int) async -> Int {
        await Task.yield()
        return n &+ count
    }
}

final class Dog: Animal {
    override func legs() -> Int { count &+ 3 }
    override func fetch() async -> Int {
        let a = await work(count &* 2)
        let b = await work(a)
        return a &+ b
    }
}

protocol Fetcher {
    func pull(_ n: Int) async -> Int
    func size() -> Int
}

struct Box: Fetcher {
    var base: Int
    func pull(_ n: Int) async -> Int {
        let a = await work(n &+ base)
        return a &- 1
    }
    func size() -> Int { base &* 7 }
}

@inline(never) func use(_ f: some Fetcher) async -> Int {
    await f.pull(2) &+ f.size()
}

@inline(never) func pick(_ k: Int) -> Animal { k > 0 ? Dog() : Animal() }

public func entry(_ k: Int) async -> Int {
    let a = pick(k)
    let fetched = await a.fetch()
    let rested = await a.rest(k)
    let fetchers: [any Fetcher] = [Box(base: k)]
    var total = a.legs() &+ fetched &+ rested
    for f in fetchers { total = total &+ (await f.pull(k)) }
    return total &+ (await use(Box(base: 1)))
}
