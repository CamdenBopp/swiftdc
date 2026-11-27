// Calls through the words past a value-witness table's eight common
// functions (-O and -Onone). Only an enum's table has functions there:
// getEnumTag at +0x58, destructiveProjectEnumData at +0x60 and
// destructiveInjectEnumTag at +0x68 (swift/include/swift/ABI/Metadata.h,
// EnumValueWitnessTable). Every other table ends at +0x58.
import EnumSlotKit

// The compiler's own calls. Signal is resilient, so its tag is read and
// written through its value witnesses, on the metadata its accessor
// returns: `bl type metadata accessor for EnumSlotKit.Signal; ldur x8,
// [x0, #-8]; ldr x8, [x8, #0x58]; blr x8`.
//
// True behaviour: 11 for idle, n + 23 for level(n), the UTF-8 length + 37
// for named, 41 for a case a later EnumSlotKit adds.
@inline(never)
public func classify(_ signal: Signal) -> Int {
    switch signal {
    case .idle: return 11
    case .level(let n): return n &+ 23
    case .named(let text): return text.utf8.count &+ 37
    @unknown default: return 41
    }
}

// True behaviour: Signal.level(n * 3), built by storing the payload and
// calling destructiveInjectEnumTag (+0x68) with level's tag.
@inline(never)
public func level(_ n: Int) -> Signal { .level(n &* 3) }

typealias TagReader = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UInt32

// `[[type - 8] + 0x58](value, type)`: the word at +0x58 of the table a
// type's metadata points back to, called as getEnumTag is, with the
// metadata last. For an enum that word is getEnumTag. For any other type
// it is whatever follows the table, and the call is to an unknown function.
@inline(__always)
func callWordPastCommonTable(_ value: UnsafeRawPointer, _ type: Any.Type) -> UInt32 {
    let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
    let table = metadata.load(fromByteOffset: -8, as: UnsafeRawPointer.self)
    let entry = table.load(fromByteOffset: 0x58, as: TagReader.self)
    return entry(value, metadata)
}

// True behaviour: Signal's tag for the value at `value`, plus 401. The
// table is an enum's, so the word called is its getEnumTag.
@inline(never)
public func enumSlot(_ value: UnsafeRawPointer) -> UInt32 {
    callWordPastCommonTable(value, Signal.self) &+ 401
}

// True behaviour: calls the word after Plain's table and adds 101. Plain
// is a struct: that word is no value witness, and nothing here is an enum
// operation on Plain.
@inline(never)
public func structSlot(_ value: UnsafeRawPointer) -> UInt32 {
    callWordPastCommonTable(value, Plain.self) &+ 101
}

// True behaviour: calls the word after the table Node's metadata points
// back to and adds 307. Node is a class.
@inline(never)
public func nodeSlot(_ value: UnsafeRawPointer) -> UInt32 {
    callWordPastCommonTable(value, Node.self) &+ 307
}

// True behaviour: the same call on a class-constrained parameter's
// metatype, plus 211. T is some class: its table has no enum witnesses.
@inline(never)
public func classSlot<T: AnyObject>(_ value: UnsafeRawPointer, _ type: T.Type) -> UInt32 {
    callWordPastCommonTable(value, type) &+ 211
}
