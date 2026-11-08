// The class whose field select_store.s's methods read: `flag` at 0x10.
public final class Box {
    public var flag = 0
    public init() {}
}

@inline(never) public func touch(_ box: Box) { box.flag &+= 1 }
