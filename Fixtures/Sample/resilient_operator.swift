// Two integer fields have a known memory layout, but a public non-frozen
// value built with library evolution has a separately lowered parameter ABI.
// The assembly caller will be generated only after inspecting the emitted IR.
public struct V {
    public let a: Int
    public let b: Int
    public init(_ a: Int, _ b: Int) { self.a = a; self.b = b }

    @inline(never)
    public static func + (_ lhs: V, _ rhs: Int) -> Int { lhs.a &+ rhs }
}

@_cdecl("resilient_operator_make")
public func makeOperand() -> UnsafeMutableRawPointer {
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<V>.size,
        alignment: MemoryLayout<V>.alignment)
    pointer.initializeMemory(as: V.self, repeating: V(40, 2), count: 1)
    return pointer
}

@_cdecl("resilient_operator_destroy")
public func destroyOperand(_ pointer: UnsafeMutableRawPointer) {
    pointer.assumingMemoryBound(to: V.self).deinitialize(count: 1)
    pointer.deallocate()
}
