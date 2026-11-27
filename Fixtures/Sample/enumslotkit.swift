// A module compiled with library evolution, so a client reaches each
// type's metadata through its accessor and an enum's cases through its
// value witnesses. The accessor's symbol spells the nominal kind:
// `type metadata accessor for EnumSlotKit.Signal` is `$s11EnumSlotKit6SignalOMa`
// (an enum), Plain's ends `VMa` (a struct), Node's `CMa` (a class).
public enum Signal {
    case idle
    case level(Int)
    case named(String)
}

public struct Plain {
    public var first: Int
    public var second: Int
    public init(first: Int, second: Int) { self.first = first; self.second = second }
}

public final class Node {
    public var weight: Int
    public init(weight: Int) { self.weight = weight }
}
