// Fixture for two classes that share a simple name in different scopes.
// swiftdc's vtable index is keyed by simple name, so `Beta.Node`'s dispatches
// must never resolve through `Alpha.Node`'s slot table.
//
// Built by `build.sh` into `libSameName.dylib` (-O).

public enum Alpha {
    public class Node {
        public var a: Int = 0
        public init() {}
        public func launchMissiles() -> Int { a + 1 }
        public var count: Int { a + 10 }
    }
}

public enum Beta {
    public class Node {
        public var b: Int = 0
        public init() {}
        public func harmless() -> Int { b + 2 }
        public var size: Int { b + 20 }
        @inline(never) public func work() -> Int { harmless() + size }
    }
}
