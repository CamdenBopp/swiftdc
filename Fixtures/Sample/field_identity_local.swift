import FieldIdentityExternal

public struct Vec {
    public var wrongFirst: Double
    public var wrongSecond: Double
}

public struct Calculator {
    var offset: Double

    public init(offset: Double) { self.offset = offset }

    public func sum(_ value: FieldIdentityExternal.Vec) -> Double {
        value.actualFirst + value.actualSecond + offset
    }

    public func localSum(_ value: Vec) -> Double {
        value.wrongFirst + value.wrongSecond + offset
    }
}

public struct EmbeddedExternal {
    public var leading: Int
    public var value: FieldIdentityExternal.Vec
    public var trailing: Int

    public init(leading: Int, value: FieldIdentityExternal.Vec, trailing: Int) {
        self.leading = leading
        self.value = value
        self.trailing = trailing
    }
}
