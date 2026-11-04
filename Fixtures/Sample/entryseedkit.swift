// A module whose types share their simple names with entryseed.swift's. A
// five-word struct travels through x8 as a result (`sret`), so these exercise
// the consumers that read a result's layout.

@frozen public struct Rec {
    public var first: Int, second: Int, third: Int, fourth: Int, fifth: Int
    @inlinable public init(first: Int, second: Int, third: Int, fourth: Int, fifth: Int) {
        self.first = first; self.second = second; self.third = third
        self.fourth = fourth; self.fifth = fifth
    }
}
