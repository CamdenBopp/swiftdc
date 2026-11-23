@frozen public struct Split {
    public let a: Int16
    public let b: Float16
    public let c: Int16
    public init(_ a: Int16, _ b: Float16, _ c: Int16) {
        self.a = a
        self.b = b
        self.c = c
    }
}

@inline(never)
public func after(_ value: Split, _ following: Int) -> Int {
    following &+ Int(value.a) &+ Int(value.c)
}

@inline(never)
public func forward(_ following: Int) -> Int {
    after(Split(3, Float16(1), 5), following)
}
