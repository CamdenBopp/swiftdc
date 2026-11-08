// Fixture for ivars whose offset is computed at load time. `Stamped` stores a
// Foundation `Date` (resilient, size unknown at compile time), so every field
// offset of the class is computed when the class is realized, and the offset
// variables its ObjC ivar list points at (`$s...Wvd`) are zero-fill in
// `__common`. `Plain` is the control: its offsets are constants in __TEXT.
//
// Built by `build.sh` into `libRuntimeIvars.dylib` (-O).

import Foundation

public class Stamped {
    public var when: Date = Date()
    public var count: Int = 0
    public var label: String = ""
    public init() {}
    public func bump() { count += 1 }
}

public class Plain {
    public var a: Int = 0
    public var b: Int = 0
    public init() {}
}
