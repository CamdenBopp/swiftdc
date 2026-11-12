// A protocol witness that ends by tail-calling its conforming member
// (`ldr x0, [x20]; b V.f`): the witness returns the member's result in x0,
// unchanged. The tail-return rule took only an ordinary `Module.Type.member`
// caller name, which a witness never is, so the call rendered as a
// statement with no `return`.
//
// True behaviour: the witness of Counted.count() returns V.count(), an Int.
// (zero()'s witness folds to its constant at -O; it is kept as a control.)
public protocol Counted {
    func count() -> Int
    static func zero() -> Int
}

public struct V: Counted {
    public var s: Int
    public init(s: Int) { self.s = s }
    @inline(never) public func count() -> Int { s &+ 3 }
    @inline(never) public static func zero() -> Int { 5 }
}
