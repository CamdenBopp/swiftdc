// A String picked by a condition is two `csel`s, one per word, both
// reading the same flags (-O):
// - `either(_:)` is `flag ? "yes" : "no"`: `tst w0, #1` then `csel x0`
//   and `csel x1`, both `ne`;
// - `pick(_:)` is one of three literals: a chain of `cmp`/`csel` pairs,
//   each pair on its own compare, `n == 0 ? "zero" : n == 1 ? "one" :
//   "many"`.
// Each read `return ?`: a word that is a select was no literal.
@inline(never) public func either(_ flag: Bool) -> String { flag ? "yes" : "no" }

@inline(never) public func pick(_ n: Int) -> String {
    n == 0 ? "zero" : n == 1 ? "one" : "many"
}
