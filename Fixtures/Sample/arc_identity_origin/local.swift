import ArcOriginForeignC

@_cdecl("arc_origin_local_probe")
@inline(never)
public func arcOriginLocalProbe(_ first: Int64, _ second: Int64) -> Int64 {
    arc_origin_misleading(first, second)
}
