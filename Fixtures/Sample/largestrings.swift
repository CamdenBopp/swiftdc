// Swift literals of 16 bytes or more at -O: passed as (count and flags,
// (address - 32) | 1<<63), the object word pointing 32 bytes before the
// bytes. The first literal is 17 bytes, so the linker places the second 32
// bytes after it: naming the object word's address named the first.
@inline(never) public func show(_ s: String) { print(s) }

public func labels() {
    show("Seventeen bytes!!")
    show("A literal laid out 32 bytes later")
}

public func matches(_ s: String) -> Bool { s == "A literal laid out 32 bytes later" }
