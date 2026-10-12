import EnumIdentityExternal

public enum Shade {
    case amber, violet
}

public enum Packet {
    case empty
    case number(Int)
    case ident(Int)
}

public enum Box {
    public enum State { case amber, violet }
}

public func fromExternalNoPayload() -> EnumIdentityExternal.Shade { .red }
public func fromLocalNoPayload() -> Shade { .amber }
public func fromExternalPayload() -> EnumIdentityExternal.Packet { .done }
public func fromLocalPayload() -> Packet { .empty }
public func fromExternalNested() -> EnumIdentityExternal.Box.State { .red }
public func fromLocalNested() -> Box.State { .amber }
