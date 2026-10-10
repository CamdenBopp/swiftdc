// Swift's error convention through callees that have no name to read.
//
// A caller arms swifterror by zeroing x21 before the call and tests x21 after.
// When the callee's symbol says ` throws`, swiftdc knows x21 is redefined. When
// the callee is unnamed (a stripped local, as in a shipping framework), it used
// to read the arming `mov x21, #0` as the tested value: `if (0 != 0)` and a
// constant return. The `-O`, `strip -x` build of this file reproduces both
// shapes measured in SwiftData.
import Foundation

public enum ProbeError: Error { case negative }

@inline(never)
private func hiddenThrower(_ x: Int) throws -> Int {
    if x < 0 { throw ProbeError.negative }
    return x &* 2
}

// A Swift do/catch around an unnamed throwing call.
public func tryHidden(_ x: Int) -> Int {
    do { return try hiddenThrower(x) } catch { return -1 }
}

// An @objc thunk (`validateAndReturnError:`) around an internal throwing
// method, whose symbol `strip -x` removes. The SwiftData shape.
@objc(SEValidator)
public class Validator: NSObject {
    @objc public var limit: Int = 0
    @inline(never) @objc func validate() throws {
        if limit < 0 { throw ProbeError.negative }
    }
}
