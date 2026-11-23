// The key path intrinsics take a fixed register list: the key path's
// class carries Root and Value, so no metadata is passed.
//   swift_getAtKeyPath(x0 = &root, x1 = key path), result through x8;
//   swift_setAtWritableKeyPath / swift_setAtReferenceWritableKeyPath
//   (x0 = &root, x1 = key path, x2 = &newValue).
// Each function keeps a later parameter live in the next register (z in
// x2 or x3), so a call that took live registers read `(…, arg1, arg2)`.
public struct Q { public var a: Int; public var b: Int }
public final class R { public var n: Int = 0 }
public func get3(_ q: Q, _ k: KeyPath<Q, Int>, _ z: Int) -> Int { q[keyPath: k] &+ z }
public func set4(_ q: inout Q, _ k: WritableKeyPath<Q, Int>, _ v: Int, _ z: Int) -> Int { q[keyPath: k] = v; return z }
public func setr4(_ r: R, _ k: ReferenceWritableKeyPath<R, Int>, _ v: Int, _ z: Int, _ w: Int) -> Int { r[keyPath: k] = v; return z &+ w }
