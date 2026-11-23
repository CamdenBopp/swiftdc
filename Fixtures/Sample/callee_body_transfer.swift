// Authored compiler/native ABI reference; the ASM oracle fixes actual buffer coordinates.
public struct Packet {
    public var a, b, c, d, e: Int64
    public init() { a = 1; b = 2; c = 3; d = 4; e = 5 }
    public init(_ a: Int64, _ b: Int64, _ c: Int64, _ d: Int64, _ e: Int64) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e
    }
}
@_silgen_name("negative_may_make_packet")
@inline(never) public func makePacket() -> Packet { Packet() }

// A pre-call field load remains an old value when an aliased result write
// changes that field. The native oracles check all field offsets and values.
public final class FieldBox {
    public var a: Int64=1
    public var b: Int64=2
    public var c: Int64=3
    public var d: Int64=4
    public var e: Int64=5
    public init() {}
    @inline(never) public func abiReference() -> Packet { Packet(a,b,c,d,e) }
}
nonisolated(unsafe) private var observedOldField: Int64 = -1
@_cdecl("complete_body_observe_old_field")
@inline(never) public func observeOldField(_ value: Int64) -> Int64 {
    observedOldField=value
    return value
}
@_silgen_name("complete_body_field_copy_invoke")
private func invokeFieldCopy(_ object: UnsafeMutableRawPointer, _ result: UnsafeMutableRawPointer) -> Int64
private func bits(_ value: inout Int64) -> UInt {
    withUnsafeMutablePointer(to: &value) { UInt(bitPattern: UnsafeMutableRawPointer($0)) }
}
@_cdecl("complete_body_stale_field_oracle")
public func staleFieldOracle() -> Int64 {
    let object=FieldBox()
    let raw=Unmanaged.passUnretained(object).toOpaque()
    let base=UInt(bitPattern: raw)
    guard bits(&object.a)==base+16, bits(&object.b)==base+24,
          bits(&object.c)==base+32, bits(&object.d)==base+40,
          bits(&object.e)==base+48 else { return -2 }
    observedOldField = -1
    let old=withUnsafeMutablePointer(to: &object.a) { first in
        invokeFieldCopy(raw, UnsafeMutableRawPointer(first))
    }
    guard old==2, observedOldField==2,
          object.a==1, object.b==99, object.c==3,
          object.d==4, object.e==5 else { return -1 }
    return 299
}

@_silgen_name("complete_body_field_copy_readonly_invoke")
private func invokeFieldCopyReadOnly(_ object: UnsafeMutableRawPointer, _ result: UnsafeMutableRawPointer) -> Int64
@_cdecl("complete_body_readonly_field_oracle")
public func readOnlyFieldOracle() -> Int64 {
    let object = FieldBox()
    let raw = Unmanaged.passUnretained(object).toOpaque()
    observedOldField = -1
    let old = withUnsafeMutablePointer(to: &object.a) {
        invokeFieldCopyReadOnly(raw, UnsafeMutableRawPointer($0))
    }
    return old == 2 && observedOldField == 2 && object.b == 2 ? 202 : -1
}

// Optional independent compiler ABI reference for the parent native lane.
// Compile as part of module PlanAlias; no symbol collision with authored ASM.
// Inspect its generated async entry/ResumeParent tail and context layout.
@inline(never) public func bodyTransferAsyncABIReference(_ value: Int) async -> Int {
    value
}
