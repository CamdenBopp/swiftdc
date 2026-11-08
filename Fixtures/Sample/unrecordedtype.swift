// A type whose descriptor and field descriptor the image holds, but no
// `__swift5_types` record lists. IRGen records a type when it emits the
// type's metadata, and emits lazily under optimization; Xcode's LLDB has
// such types (`ASTGenVisitor.DeclAttributesResult`). build.sh removes
// `Inner`'s record from the built dylib (droptyperecord.py) to reduce that
// shape: `Inner` is reachable only from `Holder`'s field and its own field
// descriptor, and is a struct { a: Int, b: Int }.
struct Inner { var a: Int; var b: Int }
public struct Holder {
    var inner = Inner(a: 1, b: 2)
    public init() {}
    public var total: Int { inner.a &+ inner.b }
}
