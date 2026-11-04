// `prop` and `title` set an overridable property through the vtable: at -O
// `ldr x1, [x8, #n]; br x1`, a tail dispatch whose target is in x1, and at
// -Onone a `blr`. Each setter takes one argument, whatever the run decoded:
// `void @"$s…1xSivs"(i64 %0, ptr swiftself %1)`.
open class Base {
    open var x: Int = 0
    open var s: String = ""
    public final var prop: Int {
        get { x &+ 1 }
        set { x = newValue &- 103 }
    }
    public final var plain: Int {
        get { x }
        set { x = newValue }
    }
    public final var title: String {
        get { s }
        set { s = newValue }
    }
}

open class Derived: Base {
    open override var x: Int { didSet { s = "" } }
}
