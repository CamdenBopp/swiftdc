// A Swift `@objc` property's getter thunk (-O): it loads the ivar through
// its computed offset (`ldr x0, [x19, x20]`, which nothing tracks) and
// returns it through `objc_retainAutoreleaseReturnValue`. That call
// returns its argument, here unknown, so the return is unknown too; read
// as a call with no recorded argument it rendered
// `return /* unresolved call @ … */ ?`.
//
// True behaviour: -[Labelled label] returns the label ivar.
import Foundation

public final class Labelled: NSObject {
    @objc public var label: NSString = "x"
}
