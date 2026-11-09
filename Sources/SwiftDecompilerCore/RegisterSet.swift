/// A set of register numbers below 64 in one word.
///
/// A register summary is kept for every function of an image, and each held
/// its argument reads as `Set<Int>`: a heap object per non-empty set, 77,765
/// of them (8.4 MB) through a GoodLinks `xrefs`. The members are x0–x7 and
/// v0–v7 numbers, so a bit each holds them. Iteration is in ascending order,
/// so nothing that walks one depends on hash order.
struct RegisterSet: SetAlgebra, Sequence, Hashable, Sendable, ExpressibleByArrayLiteral {
    private var bits: UInt64 = 0

    init() {}

    init(arrayLiteral elements: Int...) {
        for element in elements { insert(element) }
    }

    /// A member is a register number: 64 or more is a programmer error.
    private static func bit(_ number: Int) -> UInt64 {
        precondition((0 ..< 64).contains(number), "register number \(number) out of range")
        return 1 << UInt64(number)
    }

    func contains(_ number: Int) -> Bool {
        (0 ..< 64).contains(number) && bits & (1 << UInt64(number)) != 0
    }

    var isEmpty: Bool { bits == 0 }

    func union(_ other: RegisterSet) -> RegisterSet {
        var result = self
        result.bits |= other.bits
        return result
    }

    func intersection(_ other: RegisterSet) -> RegisterSet {
        var result = self
        result.bits &= other.bits
        return result
    }

    func symmetricDifference(_ other: RegisterSet) -> RegisterSet {
        var result = self
        result.bits ^= other.bits
        return result
    }

    @discardableResult
    mutating func insert(_ number: Int) -> (inserted: Bool, memberAfterInsert: Int) {
        let present = contains(number)
        bits |= Self.bit(number)
        return (!present, number)
    }

    @discardableResult
    mutating func remove(_ number: Int) -> Int? {
        guard contains(number) else { return nil }
        bits &= ~Self.bit(number)
        return number
    }

    @discardableResult
    mutating func update(with number: Int) -> Int? {
        let present = contains(number)
        bits |= Self.bit(number)
        return present ? number : nil
    }

    mutating func formUnion(_ other: RegisterSet) { bits |= other.bits }
    mutating func formIntersection(_ other: RegisterSet) { bits &= other.bits }
    mutating func formSymmetricDifference(_ other: RegisterSet) { bits ^= other.bits }

    struct Iterator: IteratorProtocol {
        fileprivate var remaining: UInt64
        mutating func next() -> Int? {
            guard remaining != 0 else { return nil }
            let number = remaining.trailingZeroBitCount
            remaining &= remaining - 1
            return number
        }
    }

    func makeIterator() -> Iterator { Iterator(remaining: bits) }

    var underestimatedCount: Int { bits.nonzeroBitCount }
}
