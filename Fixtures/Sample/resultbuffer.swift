// A five-word struct is returned through x8. resultbuffer.s defines two
// functions returning it that fill the buffer with 7s and then call a
// runtime function with x8 unchanged. True behaviour: swift_getAtKeyPath
// (the stdlib's generic _getAtKeyPath<Root, Value>, whose Value comes back
// through x8) overwrites the buffer, so `staleAfterKeyPath`'s result is
// whatever the key path read; swift_retain ignores x8, so
// `keptAfterRetain` returns Big(a: 7, b: 7, c: 7, d: 7, e: 7).
public struct Big { public var a, b, c, d, e: Int }
@inline(never) public func make(_ x: Int) -> Big { Big(a: x, b: x, c: x, d: x, e: x) }
