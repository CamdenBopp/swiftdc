@frozen
public struct Tiny {
    public var value: Int
    public init(_ value: Int) { self.value = value }

    // Declaration only: Swift supplies the actual ABI for this one-word
    // nonmutating value self. The assembly implementation must follow it.
    @_silgen_name("$s8SelfRole4TinyV4readSiyF")
    public func read() -> Int

    @_silgen_name("$s8SelfRole4TinyV12mutatingReadSiyF")
    public mutating func mutatingRead() -> Int

    @_silgen_name("$s8SelfRole4TinyV14forwardingReadSiyF")
    public mutating func forwardingRead() -> Int

    @_silgen_name("$s8SelfRole4TinyV13unusedContextSiyF")
    public mutating func unusedContext() -> Int
}

@_cdecl("selfrole_native")
public func nativeTinyRead() -> Int { Tiny(7).read() }

@_cdecl("selfrole_context")
public func nativeContextRead() -> Int { var value = Tiny(9); return value.mutatingRead() }

@_cdecl("selfrole_forward")
public func nativeForwardingRead() -> Int { var value = Tiny(11); return value.forwardingRead() }

@_cdecl("selfrole_unused")
public func nativeUnusedContext() -> Int { var value = Tiny(17); return value.unusedContext() }
