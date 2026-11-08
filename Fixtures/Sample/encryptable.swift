// Linked with `ld -encryptable`, so it carries LC_ENCRYPTION_INFO_64 with
// cryptid 0: plaintext, as an App Store binary is before Apple encrypts it.
// Tests flip cryptid to 1 and scramble the declared range, which is what an
// installed App Store binary looks like on disk. The true behaviour: with
// cryptid 0 every command reads it; with cryptid 1 none may, because its
// code and metadata are ciphertext.
public struct Point {
    public var x: Int
    public var y: Int
}

public func area(_ p: Point) -> Int { p.x * p.y }
