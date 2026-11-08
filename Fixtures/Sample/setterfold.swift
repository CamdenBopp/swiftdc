// A vtable dispatch to self's own setter folds into an assignment, its
// value the setter's parameter as its type travels (-O): a String's two
// words, `label = ""` is (0, 0xe000000000000000) in x0 and x1, and a
// Double in d0, not x0. Read as x0 alone, `label = ""` was `self.label = 0`.
open class Named {
    open var label: String = "x"
    open var scale: Double = 1
    open var count: Int = 0
    public init() {}
    @inline(never) public func reset() { label = "" }
    @inline(never) public func half() { scale = 0.5 }
    @inline(never) public func seven() { count = 7 }
}
