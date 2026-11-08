// Callee-allocated coroutine accessors (`yielding borrow` / `yielding
// mutate`, the CoroutineAccessors feature), built -O and stripped
// (`strip -x`), so every internal name must come from metadata.
//
// The lowering under test: such an accessor's method descriptor carries a
// coroutine kind with the 0x40 bit set, which `MethodDescriptorFlags::
// isCalleeAllocatedCoroutine()` reads as `CoroImpl`, a relative pointer to a
// coroutine function pointer record `{ i32 relative Function, i32, i64 }` in
// data (`…Twc`). A witness table slot for such a requirement
// (`ProtocolRequirementFlags` 0x20 on a coroutine kind) holds the witness's
// record the same way.
//
// True behaviour: `Box.value`'s yielding accessors and `Item`'s witnesses
// are functions named from metadata at the code each record leads to; the
// records themselves are named as nothing.

class Box {
    var stored = 1
    var value: Int {
        yielding borrow { yield stored }
        yielding mutate { yield &stored }
    }
}

protocol Slot {
    var v: Int { yielding borrow set }
}

struct Item: Slot {
    var raw: Int
    var v: Int {
        yielding borrow { yield raw }
        yielding mutate { yield &raw }
    }
}

@inline(never) func bump(_ s: inout some Slot) { s.v &+= 1 }

@inline(never) func make(_ k: Int) -> Box {
    let b = Box()
    b.stored = k
    return b
}

public func entry(_ k: Int) -> Int {
    var item = Item(raw: k)
    bump(&item)
    let box = make(k)
    box.value &+= 2
    return box.value &+ item.v
}
