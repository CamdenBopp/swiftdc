// A foreign malloc returns five Swift words through x8. A caller's old
// contents (1...5) are overwritten, even though the SDK malloc returns x0.
@frozen public struct Five {
    public var a, b, c, d, e: Int64
    public init(_ value: Int64) {
        a = value &+ 11; b = value &+ 12; c = value &+ 13
        d = value &+ 14; e = value &+ 15
    }
}
// The assembly export tails here, avoiding LLVM malloc builtin rewriting.
@_silgen_name("named_buffer_allocate")
@inline(never) public func allocateFive(_ value: Int64) -> Five { Five(value) }
