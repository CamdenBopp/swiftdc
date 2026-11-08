// A class whose simple name another module's class also has, and whose layout
// is fixed, so the client reads it at constant offsets.

public final class Twin { public var first = 1; public var second = 2; public init() {} }

// A value type with the simple name of a class in the module that imports this.
public struct Pair { public var left = 1; public var right = 2; public init() {} }
