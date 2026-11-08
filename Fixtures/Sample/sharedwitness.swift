// Value witnesses IRGen fills with its shared helpers (-O, and a strip -x
// copy; the types are internal, so stripping leaves their witnesses
// unnamed). `Laden` holds a reference and 24 words of trivial data: its
// copy retains, so initializeWithCopy is its own, but it is bitwise
// takable, so its initializeWithTake is `__swift_memcpy200_8`, an unrolled
// copy longer than 16 instructions, in that one slot. True behaviour: the
// helper is no type's witness; `Laden`'s destroy and `Pair`'s are their own.
// `Boxed`, a single-case enum over one reference, takes IRGen's
// `__swift_destroy_strong`, `__swift_initWithCopy_strong` and
// `__swift_assignWith{Copy,Take}_strong`, one per slot, which are no
// type's witnesses; its enum witnesses are its own.
final class Ref { var n = 0 }
struct Pair { var a: Ref; var b: Ref }
struct Laden {
    var ref: Ref
    var a0 = 0, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0, a8 = 0, a9 = 0
    var b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0, b7 = 0, b8 = 0, b9 = 0
    var c0 = 0, c1 = 0, c2 = 0, c3 = 0
}
enum Boxed { case one(Ref) }
@inline(never) public func boxes() -> [Any] { [Pair(a: Ref(), b: Ref()), Laden(ref: Ref()), Boxed.one(Ref())] }
