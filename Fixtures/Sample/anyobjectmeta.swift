// `AnyObject.Type` is one register: AnyObject has no witness tables, so its
// existential metatype is the class's metadata pointer alone (-O):
//   ident: `ret` (x0 in, x0 out);  pick: `tst w0; csel x0, x1, x2, ne`;
//   pass:  takes its Int in x1, after the metatype in x0.
public final class K {}
@inline(never) public func pass(_ t: AnyObject.Type, _ k: Int) -> Int { k &+ 1 }
@inline(never) public func ident(_ t: AnyObject.Type) -> AnyObject.Type { t }
@inline(never) public func pick(_ b: Bool, _ t: AnyObject.Type, _ u: AnyObject.Type) -> AnyObject.Type { b ? t : u }
public func callPass() -> Int { pass(K.self, 5) }
