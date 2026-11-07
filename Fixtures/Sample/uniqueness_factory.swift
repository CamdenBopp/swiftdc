// Authored probe for result identity through a runtime uniqueness query.
// The private raw pointer records ownership for cleanup outside the assembly
// wrapper; it does not create another strong reference to the object.
public final class FactoryBox {
    public let payload: Int
    public init() { payload = 47 }
}
nonisolated(unsafe) private var lastPointer: UnsafeMutableRawPointer?
nonisolated(unsafe) private var creations: Int = 0
nonisolated(unsafe) private var marks: Int = 0
nonisolated(unsafe) private var creationsAtMark: Int = 0

@_cdecl("query_factory_create")
@_optimize(none) @inline(never)
public func createFactoryObject() -> UnsafeMutableRawPointer {
    creations += 1
    let pointer = Unmanaged.passRetained(FactoryBox()).toOpaque()
    lastPointer = pointer
    return pointer
}

@_cdecl("query_factory_mark")
@_optimize(none) @inline(never)
public func markFactoryEffect() {
    marks += 1
    creationsAtMark = creations
}

@_cdecl("query_factory_reset")
@_optimize(none) @inline(never)
public func resetFactoryCounters() {
    precondition(lastPointer == nil)
    creations = 0
    marks = 0
    creationsAtMark = 0
}

@_cdecl("query_factory_creation_count")
@_optimize(none) @inline(never)
public func factoryCreationCount() -> Int { creations }

@_cdecl("query_factory_mark_count")
@_optimize(none) @inline(never)
public func factoryMarkCount() -> Int { marks }

@_cdecl("query_factory_creations_at_mark")
@_optimize(none) @inline(never)
public func factoryCreationsAtMark() -> Int { creationsAtMark }

@_cdecl("query_factory_destroy_last")
@_optimize(none) @inline(never)
public func destroyLastFactoryObject() {
    if let pointer = lastPointer {
        lastPointer = nil
        Unmanaged<FactoryBox>.fromOpaque(pointer).release()
    }
}

@_cdecl("query_factory_layer1")
@_optimize(none) @inline(never)
public func factoryLayer1(_ value: Int) -> Int { value &+ 1 }

@_cdecl("query_factory_layer2")
@_optimize(none) @inline(never)
public func factoryLayer2(_ value: Int) -> Int { value &+ 2 }

@_cdecl("query_factory_layer3")
@_optimize(none) @inline(never)
public func factoryLayer3(_ value: Int) -> Int { value &+ 3 }

@_cdecl("query_factory_layer4")
@_optimize(none) @inline(never)
public func factoryLayer4(_ value: Int) -> Int { value &+ 4 }

@_cdecl("query_factory_layer5")
@_optimize(none) @inline(never)
public func factoryLayer5(_ value: Int) -> Int { value &+ 5 }

@_cdecl("query_factory_layer6")
@_optimize(none) @inline(never)
public func factoryLayer6(_ value: Int) -> Int { value &+ 6 }

@_cdecl("query_factory_layer7")
@_optimize(none) @inline(never)
public func factoryLayer7(_ value: Int) -> Int { value &+ 7 }
