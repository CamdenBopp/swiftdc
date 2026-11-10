// Compiler ABI reference for caller-owned mutating value self.
// One-word value self is a valid caller-owned inout Cell. These explicit
// mutating declarations independently choose pointer Swift-self in x20.
public struct Cell {
    public var word: Int
    public init(_ word: Int) { self.word=word }
    @_silgen_name("$s9FrameSelf4CellV11cachedAliasSiyF")
    public mutating func cachedAlias() -> Int
    @_silgen_name("$s9FrameSelf4CellV12privateCacheSiyF")
    public mutating func privateCache() -> Int
    @inline(never) public mutating func abiReference(_ newWord: Int) -> Int {
        let old=word
        word=newWord
        return old
    }
}
// Independent concrete Swift caller/ABI reference. The ASM cachedAlias and
// privateCache methods are invoked only by their fixed-coordinate C oracles.
@inline(never) public func callABIReference(_ cell: UnsafeMutablePointer<Cell>) -> Int {
    cell.pointee.abiReference(99)
}

extension Cell {
    @_silgen_name("$s9FrameSelf4CellV9lostReachSiyF")
    public mutating func lostReach() -> Int
}

public final class PointerBox {
    public var pointer: UnsafeMutablePointer<Int>
    public init() { pointer=UnsafeMutablePointer<Int>(bitPattern: 1)! }
}
// Global Swift function ABI: one class-reference argument inx0, Int resultx0.
@_silgen_name("$s9FrameSelf18argumentFieldAliasySiAA10PointerBoxCF")
public func argumentFieldAlias(_ box: PointerBox) -> Int

// Ordinary safe-lifetime Swift reference: the address lives only within the
// withUnsafeMutablePointer closure, and the original field is restored there.
// Inspect LLVM for class argx0, field offset16, pointer store/reload semantics.
@inline(never) public func argumentFieldReference(_ box: PointerBox) -> Int {
    var local=7
    let prior=box.pointer
    return withUnsafeMutablePointer(to: &local) { address in
        box.pointer=address
        let reloaded=box.pointer
        reloaded.pointee=99
        let observed=address.pointee
        box.pointer=prior
        return observed
    }
}
@_cdecl("complete_mutable_argument_reference_oracle")
public func argumentFieldReferenceOracle() -> Int {
    argumentFieldReference(PointerBox())
}
@_cdecl("complete_mutable_argument_field_oracle")
public func argumentFieldOracle() -> Int {
    let box=PointerBox()
    let base=UInt(bitPattern: Unmanaged.passUnretained(box).toOpaque())
    let field=withUnsafeMutablePointer(to: &box.pointer) {
        UInt(bitPattern: UnsafeMutableRawPointer($0))
    }
    guard field==base+16 else { return -2 }
    let prior=box.pointer
    let observed=argumentFieldAlias(box)
    // Read only the saved address bits after the ASM frame ends, never the
    // pointee. Restore the original field before the class is released.
    let stored=UInt(bitPattern: box.pointer)
    box.pointer=prior
    guard stored != UInt(bitPattern: prior), observed==99 else { return -1 }
    return 99
}

public struct EntryPointer {
    public var address: UnsafeMutablePointer<Int>
    public init(_ address: UnsafeMutablePointer<Int>) { self.address=address }
}
// Global Swift ABI: the one-word struct travels by value inx0; unrelated
// class reference isx1; scalar Int result isx0. Inspect generated LLVM.
@_silgen_name("entry_pointer_probe")
public func entryPointerProbe(_ entry: EntryPointer, _ unrelated: PointerBox) -> Int
@inline(never) public func entryPointerABIReference(_ entry: EntryPointer, _ unrelated: PointerBox) -> Int {
    entry.address.pointee=99
    return 7
}
@_cdecl("complete_entry_pointer_positive_oracle")
public func entryPointerPositiveOracle() -> Int {
    let box=PointerBox()
    let base=UInt(bitPattern: Unmanaged.passUnretained(box).toOpaque())
    let field=withUnsafeMutablePointer(to: &box.pointer) {
        UInt(bitPattern: UnsafeMutableRawPointer($0))
    }
    guard field==base+16 else { return -2 }
    let prior=box.pointer
    var words=[17,3,19]
    let value=words.withUnsafeMutableBufferPointer { storage in
        entryPointerProbe(EntryPointer(storage.baseAddress!.advanced(by: 1)),box)
    }
    guard value==7, words==[17,99,19], box.pointer==prior else { return -1 }
    return 799
}
@_cdecl("complete_entry_pointer_reference_oracle")
public func entryPointerReferenceOracle() -> Int {
    let box=PointerBox()
    var word=3
    let value=withUnsafeMutablePointer(to: &word) { address in
        entryPointerABIReference(EntryPointer(address),box)
    }
    return value==7 && word==99 ? 799 : -1
}

@_silgen_name("entry_pointer_copy_probe")
public func entryPointerCopyProbe(_ entry: EntryPointer, _ unrelated: PointerBox) -> Int
@_cdecl("complete_entry_pointer_copy_oracle")
public func entryPointerCopyOracle() -> Int {
    let box=PointerBox()
    let base=UInt(bitPattern: Unmanaged.passUnretained(box).toOpaque())
    let field=withUnsafeMutablePointer(to: &box.pointer) {
        UInt(bitPattern: UnsafeMutableRawPointer($0))
    }
    guard field==base+16 else { return -2 }
    let prior=box.pointer
    var words=[17,3,19]
    let value=words.withUnsafeMutableBufferPointer { storage in
        entryPointerCopyProbe(EntryPointer(storage.baseAddress!.advanced(by: 1)),box)
    }
    guard value==7, words==[17,99,19], box.pointer==prior else { return -1 }
    return 799
}
