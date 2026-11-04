// Collection representation does not depend on its element being a closure.
// Each of these collections is one integer-bank word, so `k` is x1, even
// though the demangled generic argument contains an arrow (the `>` of `->`
// is no generic delimiter).
//
// Every body differs on purpose. With the same body, -O merges the functions
// into one thunk and the symbols alias (`takeArray`, `takeDictionary` and
// `passDictionary` were all one address, which rendered `sub_464`), and a
// bare forwarder is a tail branch with no call to read arguments from.
// True behaviour: passArray(h, k) == h.count + k + 1;
// passContiguous == h.count - k + 2; passDictionary == h.count * k + 3;
// passNested == (h.count ^ k) + 4; each returnX hands back `other`, retained.
public typealias Handler = (Int) -> Int

@inline(never) public func takeArray(_ handlers: [Handler], _ k: Int) -> Int {
    handlers.count &+ k
}
@inline(never) public func takeContiguous(_ handlers: ContiguousArray<Handler>, _ k: Int) -> Int {
    handlers.count &- k
}
@inline(never) public func takeDictionary(_ handlers: [String: Handler], _ k: Int) -> Int {
    handlers.count &* k
}
@inline(never) public func takeNested(_ handlers: [String: [Handler]], _ k: Int) -> Int {
    handlers.count ^ k
}
public func passArray(_ handlers: [Handler], _ k: Int) -> Int { takeArray(handlers, k) &+ 1 }
public func passContiguous(_ handlers: ContiguousArray<Handler>, _ k: Int) -> Int { takeContiguous(handlers, k) &+ 2 }
public func passDictionary(_ handlers: [String: Handler], _ k: Int) -> Int { takeDictionary(handlers, k) &+ 3 }
public func passNested(_ handlers: [String: [Handler]], _ k: Int) -> Int { takeNested(handlers, k) &+ 4 }
public func returnArray(_ handlers: [Handler], _ other: [Handler]) -> [Handler] { other }
public func returnDictionary(_ k: Int, _ handlers: [String: Handler], _ other: [String: Handler]) -> [String: Handler] { other }

// A buffer pointer is still two words, never a single-register result.
public func returnBuffer(_ handlers: UnsafeBufferPointer<Handler>) -> UnsafeBufferPointer<Handler> { handlers }
