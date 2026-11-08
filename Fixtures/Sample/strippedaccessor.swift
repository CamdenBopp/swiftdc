// A stripped binary's metadata names a vtable accessor by its kind alone:
// Counter's `value` getter is `StrippedAccessor.Counter.getter`, with no
// property. A self dispatch to it (`ldr x8, [x20]; ldr x8, [x8, #k];
// blr x8`) is `self.value`, and with the property unknown it must not
// read as a property named after the type (`self.Counter`).
class Counter {
    var value: Int = 0
    init() {}
    @inline(never) func bump() -> Int { value = value &+ 1; return value }
}
public func run() -> Int { Counter().bump() }
