// Value witnesses of an associated type's metadata. countAll is never
// specialized, so it iterates C through C's witness table: it makes and
// destroys a C.Iterator and destroys each C.Element, and both metadata come
// from swift_getAssociatedTypeWitness(…, associated type descriptor for
// Swift.Sequence.Iterator / .Element). Their value witnesses are named for
// that associated type: `A.Element` with symbols, `arg1.Element` stripped
// (C's metadata follows the formal c).

@_semantics("optimize.sil.specialize.generic.never") @inline(never)
func countAll<C: Collection>(_ c: C) -> Int {
    var n = 0
    for element in c { withExtendedLifetime(element) { n += 1 } }
    return n
}

public func useCount(_ values: [String]) -> Int { countAll(values) }
