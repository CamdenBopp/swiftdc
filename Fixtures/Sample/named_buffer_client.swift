// Identical frozen layouts in the provider and consumer exercise the lowered
// Swift sret ABI without supplying the decompiler a declaration for malloc.
@frozen public struct Five {
    public var a, b, c, d, e: Int64
    public init(_ value: Int64) {
        a = value; b = value; c = value; d = value; e = value
    }
}
#if BUFFER_SYSTEM
@_silgen_name("$s12BufferSystem7forwardyAA4FiveVs5Int64VF")
public func forward(_ value: Int64) -> Five
@_silgen_name("$s12BufferSystem8indirectyAA4FiveVs5Int64VF")
public func indirect(_ value: Int64) -> Five
@_cdecl("named_buffer_system_probe")
@inline(never) public func bufferProbe(_ value: Int64) -> Int64 { forward(value).a }
@_cdecl("named_buffer_system_indirect_probe")
@inline(never) public func indirectProbe(_ value: Int64) -> Int64 { indirect(value).a }
#else
@_silgen_name("$s12BufferClient7forwardyAA4FiveVs5Int64VF")
public func forward(_ value: Int64) -> Five
@_silgen_name("$s12BufferClient8indirectyAA4FiveVs5Int64VF")
public func indirect(_ value: Int64) -> Five
@_cdecl("named_buffer_foreign_probe")
@inline(never) public func bufferProbe(_ value: Int64) -> Int64 { forward(value).a }
@_cdecl("named_buffer_foreign_indirect_probe")
@inline(never) public func indirectProbe(_ value: Int64) -> Int64 { indirect(value).a }
#endif
