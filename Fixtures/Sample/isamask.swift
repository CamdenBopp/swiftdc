// A generic class that inherits from Objective-C reads its metadata through
// its masked isa (-O): `ldr x8, [x20]; ldr x9, [_swift_isaMask@GOT];
// ldr x9, [x9]; and x8, x9, x8`, then its generic argument A at the
// immediate-members offset and A's assignWithCopy through A's value-witness
// table: `self.value = v` is `assignWithCopy value witness for A(…)`.
import Foundation
public final class Box<T>: NSObject {
    var value: T
    public init(_ v: T) { value = v }
    @inline(never) public func set(_ v: T) { value = v }
}
