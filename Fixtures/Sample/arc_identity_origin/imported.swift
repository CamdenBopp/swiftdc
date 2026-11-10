import ArcOriginForeignC

@_cdecl("arc_origin_import_probe")
@inline(never)
public func arcOriginImportProbe(_ first: Int64, _ second: Int64) -> Int64 {
    arc_origin_misleading(first, second)
}
