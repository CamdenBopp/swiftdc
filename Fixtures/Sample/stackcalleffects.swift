// The pointer is used only while withUnsafeMutablePointer keeps its storage
// alive. A separate non-inlined call observes the exported address.
nonisolated(unsafe) private var exported: UnsafeMutablePointer<Int>?

@inline(never)
private func changeExported() {
    exported?.pointee = 11
}

@inline(never)
public func cacheEscape(_ seed: Int) -> Int {
    var value = seed
    return withUnsafeMutablePointer(to: &value) { pointer in
        exported = pointer
        pointer.pointee = 7
        changeExported()
        return pointer.pointee
    }
}

@_cdecl("stack_compiled_global")
public func nativeGlobal(_ seed: Int) -> Int { cacheEscape(seed) }
