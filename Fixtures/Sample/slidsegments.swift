// An executable whose segments map to the file at different slides, the
// layout a user reported from an iOS app. `slidsegments_zerofill.s` puts an
// 0x870000-byte zero-fill section at the end of __DATA, so __DATA's vmsize
// is far larger than its filesize. build.sh then moves three sections into a
// __DATA_DIRTY segment after it and `__swift5_fieldmd` into a __SWIFT_FIELDS
// segment after that (`ld -rename_section`). Their file bytes follow
// __DATA's directly, but their addresses follow the zero fill: each one's VM
// offset from __TEXT is its file offset plus 0x870000. __DATA_DIRTY holds
// fixup chains; __SWIFT_FIELDS holds none, only relative pointers.
//
// Every relative pointer that crosses into or out of a slid segment is a VM
// displacement, so `pointer's file offset + delta` is the wrong file offset:
//   - the ObjC method lists in __TEXT name selector references in
//     __DATA_DIRTY,__objc_selrefs (positive, into the slid segment);
//   - __SWIFT_FIELDS,__swift5_fieldmd's records name mangled type and field
//     names in __TEXT (negative, out of it): `Pair.first` is named "first";
//   - `Bridged`'s superclass is a mangled name in __TEXT with an indirect
//     symbolic reference (`\x02` + rel32) to an `NSObject` slot in
//     __DATA_DIRTY,__got;
//   - the chained fixups' starts for __DATA_DIRTY give its VM offset.
// dyld loads it and it prints "d3 6.0 2 first".
import Foundation

public protocol Shape { func area() -> Double }

public struct Rect: Shape {
    public var w: Double
    public var h: Double
    public func area() -> Double { w * h }
}

public struct Pair {
    public var first: Int
    public var second: String
}

open class Base {
    public var name: String = "base"
    public init() {}
    open func greet() -> String { name }
}

public final class Derived: Base {
    public var count = 3
    public override func greet() -> String { "d\(count)" }
}

@objc public class Bridged: NSObject {
    @objc public var label = "l"
    @objc public func ping(_ n: Int) -> Int { n + 1 }
}

let pair = Pair(first: 1, second: "two")
let field = Mirror(reflecting: pair).children.first?.label ?? "?"
print(Derived().greet(), Rect(w: 2, h: 3).area(), Bridged().ping(1), field)
