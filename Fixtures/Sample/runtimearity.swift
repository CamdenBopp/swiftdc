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
//
// The rest are Swift runtime entry points of fixed arity, each called with
// more or fewer registers live than it takes (swift/include/swift/Runtime):
//
// - `resumeFailing` resumes an unsafe continuation with an error:
//   `swift_continuation_throwingResumeWithError(continuation, error)`, two
//   (Concurrency.h:1116).
// - `onMain` checks it is on the main actor:
//   `swift_task_getMainExecutor(void)`, none (Concurrency.h:1165).
// - `erase` boxes a generic value as an existential, so it instantiates the
//   conformance: `swift_getWitnessTable(conformance, type,
//   instantiationArgs)`, three (Metadata.h:369), and completes the box's
//   metadata: `swift_checkMetadataState(request, type)`, two
//   (Metadata.h:350).
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

public struct RuntimeArityBox<T>: CustomStringConvertible {
    var value: T
    public var description: String { "box" }
}

public struct RuntimeArityFailure: Error {}

public func resumeFailing(_ a: Int, _ b: Int) async throws -> Int {
    try await withUnsafeThrowingContinuation { (c: UnsafeContinuation<Int, Error>) in
        if a > b { c.resume(throwing: RuntimeArityFailure()) } else { c.resume(returning: a) }
    }
}

public func onMain(_ a: Int, _ b: Int) -> Int {
    MainActor.assumeIsolated { a + b }
}

@inline(never) public func erase<T>(_ v: T, _ a: Int, _ b: Int) -> CustomStringConvertible {
    RuntimeArityBox(value: v)
}
