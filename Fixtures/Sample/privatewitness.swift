// Conformances of private types to another image's protocol (`Hashable`).
// A private type's parent is an anonymous context, so its name cannot be
// qualified from metadata; `interface` prints it as `PrivateWitness.Token`.
// Stripped, every witness's address must come from the conformance alone.
//
// True behaviour: `Token`'s witnesses are its own `TW` functions. `Badge`
// has two private conformances under one name (`Badge` here, and a local
// `Badge` in `badgeHash`), so a witness found by name alone could belong to
// either, and is declined. `Outer.Token` (internal, so its parent is
// `Outer`) keeps a qualified name, which rules it out as `Token`'s match.
private struct Token: Hashable {
    let raw: Int
}

private struct Badge: Hashable {
    let raw: Int
}

public enum Outer {
    struct Token: Hashable {
        let label: String
    }
}

public func tokenHash(_ raw: Int) -> AnyHashable {
    AnyHashable(Token(raw: raw))
}

public func outerTokenHash(_ label: String) -> AnyHashable {
    AnyHashable(Outer.Token(label: label))
}

public func badgeHash(_ raw: Int, local: Bool) -> AnyHashable {
    struct Badge: Hashable {
        let raw: Int
        let local = true
    }
    return local ? AnyHashable(Badge(raw: raw)) : AnyHashable(PrivateWitness.Badge(raw: raw))
}
