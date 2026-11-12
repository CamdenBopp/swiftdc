// A closure takes what it captured as arguments after its formals: the
// forwarder for `{ y in y &+ k }` loads k from its context and passes it
// in x1 (`ldr x1, [x20, #0x10]; b closure #1`). The closure's printed
// name lists `(Swift.Int)`, its formal alone, and the call rendered
// `closure #1 (arg0)`, one argument short.
//
// True behaviour: adder(k) returns a closure that adds k to its argument;
// the forwarder calls closure #1 with y and k.
@inline(never) public func adder(_ k: Int) -> (Int) -> Int { { y in y &+ k } }
@inline(never) public func apply(_ f: (Int) -> Int) -> Int { f(10) }
