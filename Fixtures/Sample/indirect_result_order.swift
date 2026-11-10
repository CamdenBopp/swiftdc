// Five words return in the caller's x8 buffer. The assembly wrapper forwards
// that buffer to a producer, then calls an observable effect before returning.
// The producer has a C-spelled symbol but keeps the compiler's Swift sret ABI;
// a spelling alone must not decide whether a whole indirect result is scalar.
public struct Packet {
    public var a: Int64
    public var b: Int64
    public var c: Int64
    public var d: Int64
    public var e: Int64
    public init(_ value: Int64) {
        a = value; b = value &+ 1; c = value &+ 2; d = value &+ 3; e = value &+ 4
    }
}

nonisolated(unsafe) private var orderTrace: Int64 = 0

@_silgen_name("indirect_order_make_packet")
@inline(never) public func makePacket() -> Packet {
    orderTrace = orderTrace &* 10 &+ 1
    return Packet(orderTrace)
}

@inline(never) public func effect() {
    orderTrace = orderTrace &* 10 &+ 2
}

@_silgen_name("$s13IndirectOrder7orderedAA6PacketVyF")
public func ordered() -> Packet

// 12 proves producer then effect; every field proves the complete result.
@_cdecl("indirect_order_native")
public func nativeOrderOracle() -> Int64 {
    orderTrace = 0
    let value = ordered()
    guard value.a == 1, value.b == 2, value.c == 3, value.d == 4, value.e == 5 else { return -1 }
    return orderTrace
}

// A saved result pointer in an escaped frame remains a possible alias even
// after the tracer forgets that slot. Mutating its second word changes the
// returned value; it is no longer the producer's original Packet.
nonisolated(unsafe) private var aliasTrace: Int64 = 0

@_silgen_name("alias_result_make")
@inline(never) public func makeAliasPacket(_ local: UnsafeMutableRawPointer) -> Packet {
    local.storeBytes(of: UInt64(77), as: UInt64.self)
    aliasTrace = aliasTrace &* 10 &+ 1
    return Packet(aliasTrace)
}

@_silgen_name("alias_result_mutate")
@inline(never) public func mutateAliasPacket(_ field: UnsafeMutablePointer<Int64>, _ value: Int64) {
    field.pointee = value
    aliasTrace = aliasTrace &* 10 &+ 2
}

@_silgen_name("alias_plain_make")
@inline(never) public func makePlainAliasPacket() -> Packet {
    aliasTrace = aliasTrace &* 10 &+ 1
    return Packet(aliasTrace)
}

@_silgen_name("alias_result_touch")
@inline(never) public func touchAliasFrame(_ local: UnsafeMutableRawPointer) {
    let value = local.load(as: UInt64.self)
    local.storeBytes(of: value &+ 1, as: UInt64.self)
    aliasTrace = aliasTrace &* 10 &+ 2
}

@_silgen_name("$s13IndirectOrder12aliasOrderedAA6PacketVyF")
public func aliasOrdered() -> Packet
@_silgen_name("$s13IndirectOrder12aliasClearedAA6PacketVyF")
public func aliasCleared() -> Packet
@_silgen_name("$s13IndirectOrder11aliasJoinedyAA6PacketVs5Int64VF")
public func aliasJoined(_ flag: Int64) -> Packet
@_silgen_name("$s13IndirectOrder12aliasContextAA6PacketVyF")
public func aliasContext() -> Packet

extension Packet {
    // This callee really reads the incoming Swift context pointer. A caller
    // keeping its result there must retain the MAY escape, unlike otherWide.
    @inline(never) public mutating func mutateB() {
        b = 99
        aliasTrace = aliasTrace &* 10 &+ 2
    }
}

@_cdecl("indirect_alias_context_native")
public func nativeContextAliasOracle() -> Int64 {
    aliasTrace = 0
    let value = aliasContext()
    guard value.a == 1, value.b == 99, value.c == 3, value.d == 4, value.e == 5 else { return -1 }
    return aliasTrace &* 100 &+ value.b
}

@_cdecl("indirect_alias_native")
public func nativeAliasOracle() -> Int64 {
    aliasTrace = 0
    let value = aliasOrdered()
    guard value.a == 1, value.b == 99, value.c == 3, value.d == 4, value.e == 5 else { return -1 }
    return aliasTrace &* 100 &+ value.b
}

@_cdecl("indirect_alias_cleared_native")
public func nativeClearedAliasOracle() -> Int64 {
    aliasTrace = 0
    let value = aliasCleared()
    guard value.a == 1, value.b == 2, value.c == 3, value.d == 4, value.e == 5 else { return -1 }
    return aliasTrace &* 100 &+ value.b
}

@_cdecl("indirect_alias_joined_native")
public func nativeJoinedAliasOracle(_ flag: Int64) -> Int64 {
    aliasTrace = 0
    let value = aliasJoined(flag)
    guard value.a == 1, value.b == (flag == 0 ? 2 : 99), value.c == 3, value.d == 4, value.e == 5 else { return -1 }
    return aliasTrace &* 100 &+ value.b
}


// An outlined helper reloads the incoming context after x20 was overwritten.
// One path uses it locally; the other forwards it to a real context reader.
@_silgen_name("$s13IndirectOrder13aliasOutlinedAA6PacketVyF")
public func aliasOutlined() -> Packet
@_silgen_name("$s13IndirectOrder18aliasOutlinedRelayAA6PacketVyF")
public func aliasOutlinedRelay() -> Packet

@_cdecl("indirect_alias_outlined_native")
public func nativeOutlinedAliasOracle() -> Int64 {
    aliasTrace = 0
    let value = aliasOutlined()
    guard value.a == 1, value.b == 99, value.c == 3, value.d == 4, value.e == 5 else { return -1 }
    return aliasTrace &* 100 &+ value.b
}

@_cdecl("indirect_alias_outlined_relay_native")
public func nativeOutlinedRelayAliasOracle() -> Int64 {
    aliasTrace = 0
    let value = aliasOutlinedRelay()
    guard value.a == 1, value.b == 99, value.c == 3, value.d == 4, value.e == 5 else { return -1 }
    return aliasTrace &* 100 &+ value.b
}
