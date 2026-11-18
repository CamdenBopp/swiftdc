import Darwin

// The C declarations consume w0, even when the Swift entry receives an Int64.
// Optimized tail calls need no instruction to discard the upper 32 bits.
@inline(never) public func narrowClose(_ x: Int64) -> Int32 {
    Darwin.close(Int32(truncatingIfNeeded: x))
}

@inline(never) public func narrowKill(_ x: Int64) -> Int32 {
    Darwin.kill(Int32(truncatingIfNeeded: x), 0)
}

@inline(never) public func narrowSleep(_ x: UInt64) -> UInt32 {
    Darwin.sleep(UInt32(truncatingIfNeeded: x))
}

// Only these two functions run in the oracle. Inputs are ASCII lowercase or
// EOF after truncation, so toupper's domain is respected at every call.
@inline(never) public func narrowUpper(_ x: Int64) -> Int32 {
    Darwin.toupper(Int32(truncatingIfNeeded: x))
}

@inline(never) public func narrowComputedUpper(_ x: Int64) -> Int32 {
    Darwin.toupper(Int32(truncatingIfNeeded: x &+ 1))
}

// Distinct instruction bodies keep the narrow control from sharing an entry
// with the wide kill wrapper. These functions are disassembled, never run.
@inline(never) public func typedKill(_ x: Int32) -> Int32 {
    Darwin.kill(x, 1)
}

@inline(never) public func constantClose() -> Int32 {
    Darwin.close(-1)
}

// The current SDK catalog does not record C result widths. Losing a result
// as an argument must keep its producing call and its order.
@inline(never) public func narrowProducer() -> Int32 {
    Darwin.kill(Darwin.getpid(), 0)
}

// A declared variadic still reads its fixed flags parameter as a C int.
// Never executed: arbitrary flags can require an additional mode argument.
// Darwin.open is a Swift overlay. Bind the actual C symbol instead; its
// pointer/int fixed prefix uses x0/w1 under both scalar conventions here.
@_silgen_name("open") private func importedOpen(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32
@inline(never) public func narrowOpen(_ path: UnsafePointer<CChar>, _ flags: Int64) -> Int32 {
    importedOpen(path, Int32(truncatingIfNeeded: flags))
}

// Comparisons produce complete 0/1 words (CSET or a phi of literal stores),
// so their upper bits do not inherit uncertainty from the compared inputs.
@inline(never) public func comparisonUpper(_ x: Int64) -> Int32 {
    Darwin.toupper(x == 1 ? 1 : 0)
}

@inline(never) public func producerComparisonUpper() -> Int32 {
    Darwin.toupper(Darwin.getpid() > 0 ? 1 : 0)
}

@inline(never) public func comparisonOffsetUpper(_ x: Int64) -> Int32 {
    Darwin.toupper((x == 1 ? 1 : 0) + 1)
}
