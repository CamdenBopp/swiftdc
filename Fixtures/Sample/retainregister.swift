// objc_retain_xN: on the iOS targets the compiler retains a value that is
// not in x0 through a register-specific stub (`bl objc_retain_x20`), which
// returns the object in x0. Built for the arm64 simulator; macOS targets
// emit plain objc_retain here.
import Foundation

nonisolated(unsafe) var registry: [NSObject] = []
@inline(never) public func code() -> Int { 41 }
@inline(never) public func enroll(_ o: __owned NSObject) { registry.append(o) }

public final class Node: NSObject {
    public func join(_ k: Int) -> Int {
        let a = code()
        enroll(self)
        return a &+ k
    }
}
