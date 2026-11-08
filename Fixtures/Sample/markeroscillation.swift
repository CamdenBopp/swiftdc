// A loop the tracer converges on only if escape markers stay once they
// reach a block (-O). `[a, b, c].compactMap { $0 }` lowers to a
// three-element stack array and a compaction loop that re-materializes the
// array's base address inside the loop. Without per-block sticky escape
// markers the fixpoint never settles (`values.fixpoint-cap`), the function
// claims nothing, and every call in it renders `()`. True behaviour:
// returns the non-nil arguments in order.
public func compacted(_ a: String?, _ b: String?, _ c: String?) -> [String] {
    [a, b, c].compactMap { $0 }
}
