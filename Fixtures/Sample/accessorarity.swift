// A system type's metadata accessor takes the request and the type's key
// generic arguments, nothing more (-O): `optionalType` calls Swift.Optional's
// accessor, `mov x0, #0; mov x1, x3; bl _$sSqMa`, with b and c still in x1
// and x2 before it. Optional<Wrapped> has one key argument, so the call is
// `(request, T)`; a later register is a stale caller argument.
@inline(never) public func optionalType<T>(_ a: Int, _ b: Int, _ c: Int, _ t: T.Type) -> Any.Type {
    return a > b + c ? Optional<T>.self : T.self
}
// Dictionary<Key: Hashable, Value> has three: Key, Value, and Key's
// Hashable witness table.
@inline(never) public func dictionaryType<K: Hashable, V>(_ a: Int, _ b: Int, _ k: K.Type, _ v: V.Type) -> Any.Type {
    return a > b ? [K: V].self : K.self
}
