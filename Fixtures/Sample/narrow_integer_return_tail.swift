import Darwin

// Zero is added only to the oracle's own Int32 storage. The C result is signed;
// the Swift result reinterprets its low 32 bits as UInt32. Optimized code ends
// in a tail B, so a return renderer must not bypass the result-width proof.
@inline(never) public func unsignedAtomic(_ value: UnsafeMutablePointer<Int32>) -> UInt32 {
    UInt32(bitPattern: OSAtomicAdd32(0, value))
}
