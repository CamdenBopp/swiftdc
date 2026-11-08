// String literals whose text reads like a note once split at two spaces
// (-O). Notes in an annotation are separated by two spaces, and a call's
// rendered arguments are a note, so a renderer that split the annotation
// and took the first piece starting `return ` printed a piece of the
// literal as the function's return. A bound call's note was cut at the
// literal's first double space.
//
// True behaviour: each `emit…` function calls `emit` once with its literal
// and returns nothing; none of them throws. `measured` returns
// measure("ok  done"). `readLabelled` calls `wide` once and returns
// w.a &+ w.e of its result.

public var sink = ""

@inline(never) public func emit(_ text: String) { sink = text }

// A small literal (in registers) with `  return ` inside it.
public func emitReturnText() { emit("a  return 1") }

// A literal in __cstring, indented the way embedded scripts are.
public func emitScript() { emit("function f() {\n    return 1;\n}\n") }

// A literal that is a whole throw note.
public func emitThrowText() { emit("then throw ?") }

// A literal that holds an exit note between double spaces.
public func emitExitText() { emit("x  swift-exit=normal  y") }

@inline(never) public func measure(_ text: String) -> Int { text.utf8.count }

// A tail call returning `measure`'s result, its literal with a double
// space: the return note was cut at it.
public func measured() -> Int { measure("ok  done") }

public struct Wide {
    public var a, b, c, d, e: Int
}

@inline(never) public func wide(_ label: String) -> Wide {
    Wide(a: label.utf8.count, b: 2, c: 3, d: 4, e: 5)
}

// The result comes back through x8 and is read word by word, so the call is
// bound once; its literal has a double space.
public func readLabelled() -> Int {
    let w = wide("Name  Value")
    return w.a &+ w.e
}

// Literals that read as the statement notes the pseudo view also scanned
// for, and as the markers on a call: a field write, an ivar write, a tuple
// of ivar writes, `self = …`, a yield, an executor hop, `await=` and
// `dispatch=self`. True behaviour: each calls `emit` once with its literal.
public func emitFieldWriteText() { emit("a  self.x = 1") }
public func emitIvarWriteText() { emit("a  self->x -= 1") }
public func emitTupleWriteText() { emit("a  (self->a, b) = (1, 2)") }
public func emitSelfInitText() { emit("a  self = b") }
public func emitYieldText() { emit("a  yield &self.x") }
public func emitHopText() { emit("a  await hop_to_executor(MainActor)") }
public func emitAwaitText() { emit("a  await=r9") }
public func emitDispatchText() { emit("a  dispatch=self") }

// A real field write whose value spells a literal with a double space:
// its note was cut there. True behaviour: remeasure() stores
// measure("ok  done") to self.count.
public struct Tally {
    public var count = 0
    public mutating func remeasure() { count = measure("ok  done") }
}

@inline(never) public func handler(_ name: String) -> @convention(c) () -> Void {
    name.isEmpty ? { sink = "e" } : { sink = "f" }
}

// `bl handler; br x0`: a tail call through the pointer `handler` returned.
// The jump note spells the target with the literal and was cut at its
// double space. True behaviour: calls handler("a  b"), then jumps to the
// pointer it returned.
public func runHandler() { handler("a  b")() }

// `cmp x0, x8; b.eq` against a literal's address: the baked condition
// holds the literal. True behaviour: emit("y") iff p is that address.
public func isLabel(_ p: UnsafeRawPointer) {
    if p == UnsafeRawPointer(("a  b" as StaticString).utf8Start) { emit("y") }
}
