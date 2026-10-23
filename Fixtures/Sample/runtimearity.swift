// Calls that take fewer arguments than the registers holding values at them.
// An `@objc` initializer of a Swift class stores its two arguments from x2
// and x3 and then needs the class's metadata for `super.init()`, while x2
// and x3 still hold the arguments:
//
// - `RuntimeArityOpenEvent` is not final, so it calls its own metadata
//   accessor (`…CMa`). The accessor's body is `adrp x0; add x0; bl
//   objc_opt_self; mov x1, #0; ret`: it reads no argument register.
// - `RuntimeArityFinalEvent` is final, so it calls `swift_getObjectType`,
//   which takes one argument, the object (swift/include/swift/Runtime/
//   Casting.h:231).
//
// True behaviour: the accessor takes nothing and swift_getObjectType takes
// self alone; neither receives profileName or trigger.
import Foundation

@objc public enum RuntimeArityTrigger: Int { case manual, automatic }

@objc class RuntimeArityOpenEvent: NSObject {
    let profile: Int
    let trigger: RuntimeArityTrigger
    @objc init(profileName: Int, trigger: RuntimeArityTrigger) {
        profile = profileName
        self.trigger = trigger
        super.init()
    }
}

@objc final class RuntimeArityFinalEvent: NSObject {
    let profile: Int
    let trigger: RuntimeArityTrigger
    @objc init(profileName: Int, trigger: RuntimeArityTrigger) {
        profile = profileName
        self.trigger = trigger
        super.init()
    }
}
