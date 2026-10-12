public enum Shade {
    case red, blue
}

public enum Packet {
    case done
    case number(Int)
    case ident(Int)
}

public enum Box {
    public enum State { case red, blue }
}
