// Fixture for copy-on-write. `isKnownUniquelyReferenced` lowers to
// `Builtin.isUnique` and then to the runtime call
// `swift_isUniquelyReferenced_nonNull_native`, which returns a Bool: the
// object's strong refcount is exactly one. It does not return its argument.
//
// Built by `build.sh` into `libCow.dylib` (-O).

final class Storage {
    var values: [Int]
    init(_ values: [Int]) { self.values = values }
}

public struct CowBox {
    var storage: Storage
    public init() { storage = Storage([]) }

    public mutating func append(_ x: Int) {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(storage.values)
        }
        storage.values.append(x)
    }

    @inline(never)
    public mutating func isUnique() -> Bool { isKnownUniquelyReferenced(&storage) }
}
