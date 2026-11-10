// Folds strip hides. -O, built as a dylib and as a `strip -x` copy.
//
// `Local.other` returns 778, and so does `closureUser({ 777 })` once the
// closure is propagated: `mov w0, #778; ret`. The linker folds them, and
// `strip -x` removes both symbols, which leaves `Local`'s vtable as the only
// name at that address. `viaClosure` calls the specialization, not `Local`.
class Local {
    func other() -> Int { 778 }
    func same() -> Int { 779 }
    func work(_ a: Int) -> Int { a &* 3 &+ other() }
    func dispatch() -> Int { other() &+ work(1) }
}

final class LocalLeaf: Local {
    override func other() -> Int { 780 }
    override func work(_ a: Int) -> Int { a &* 5 &+ same() }
}

protocol Shape { func area(_ scale: Int) -> Int; func sides() -> Int }

struct Square: Shape {
    var side: Int
    func area(_ scale: Int) -> Int { side &* side &* scale }
    func sides() -> Int { 781 }
}

struct Triangle: Shape {
    var base: Int
    func area(_ scale: Int) -> Int { base &* scale &* 2 }
    func sides() -> Int { 782 }
}

@inline(never) func closureUser(_ f: () -> Int) -> Int { f() &+ 1 }

public func viaClosure() -> Int { closureUser({ 777 }) }

public func viaWitness(_ pick: Bool) -> Int {
    let shape: any Shape = pick ? Square(side: 2) : Triangle(base: 3)
    return shape.area(2) &+ shape.sides() &+ closureUser({ 780 })
}

public func viaClass(_ pick: Bool) -> Int {
    let local = pick ? Local() : LocalLeaf()
    return local.dispatch()
}

// `Exported.w`'s setter is a bare `ret`, and so is the resume half of
// `modify`. Only the setter's symbol survives `strip -x`, so `Base.w.modify`
// handed back `Exported.w.setter` as its continuation.
public class Base {
    public var w = 1
    public init() {}
}

public final class Exported: Base {
    override public var w: Int {
        get { 2 }
        set {}
    }
}

@inline(never) public func bump(_ base: Base) { base.w += 1 }

// A call into a body that does work of its own keeps its name.
@inline(never) public func work(_ a: Int, _ b: Int) -> Int { a &* b &+ a }

public func callsWork(_ a: Int) -> Int { work(a, a &+ 1) &+ 1 }
