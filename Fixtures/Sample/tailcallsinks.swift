// The Swift -O shape of tailcallsinks.c's s9: a loop whose else arm and whose
// normal exit both leave through a tail call (`b fb`, `b fc`). True
// behaviour: nothing runs after fc(a); fb(a) runs only from the else arm.
@inline(never) public func p(_ a: Int) -> Bool { a & 3 != 0 }
@inline(never) public func fa() { print("a") }
@inline(never) public func fb(_ x: Int) { print("b", x) }
@inline(never) public func fc(_ x: Int) { print("c", x) }

public func s9(_ start: Int) {
    var a = start
    while p(a) {
        if p(a &+ 1) { fa() } else { fb(a); return }
        a &+= 1
    }
    fc(a)
}
