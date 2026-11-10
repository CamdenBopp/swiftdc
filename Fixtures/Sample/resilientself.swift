// Built with -enable-library-evolution at -Onone, -O and -Osize. A public
// enum of a resilient module is passed by address: its members read their
// tag through x20 (`ldrb w8, [x20]`), and so do the witnesses of any
// no-payload enum, whose self is `@in_guaranteed`.
// - `Mode.label` picks a literal by the tag: `csel`s at -O and -Osize, a
//   branch per case at -Onone.
// - `Mode.isAlpha` compares it, `Mode.rank(_:)` adds it to an argument by
//   case: `base` is still x0, self in x20.
// - `Fixed` is frozen: it travels in x0, and x20 is not self.
// - `Payload.isNone` reads x20 too, but its first byte is a payload's, no
//   tag, so a case is not named from it.
// - `Kind` and `Asm` give resilient_self.s its names: an instance witness
//   that reads self through x20, and bodies a compiler would not emit that
//   read x20 where no self is.
public enum Mode: String {
    case alpha, beta, gamma
    public var label: String {
        switch self {
        case .alpha: return "first"
        case .beta: return "second"
        case .gamma: return "third"
        }
    }
    public var isAlpha: Bool { self == .alpha }
    public func rank(_ base: Int) -> Int {
        switch self {
        case .alpha: return base
        case .beta: return base &+ 1
        case .gamma: return base &+ 2
        }
    }
}

@frozen public enum Fixed: Int {
    case one, two
    public var label: String { self == .one ? "one" : "two" }
}

public enum Payload {
    case number(Int)
    case word(String)
    case none
    public var isNone: Bool {
        if case .none = self { return true }
        return false
    }
}

public protocol Kind {
    static func make() -> Int
    init(seed: Int)
    func peek() -> Int
}

public enum Asm {
    case a, b
}
