// Fixture for compiler code-generation idioms that need their own image, so
// their bytes never move the hard-coded fuzz offsets into libReconstruction.
// Built by `build.sh` into `libCodegen.opt.dylib` (-O) and a stripped copy.

// Division by a constant. At -O none of these is an sdiv: each lowers to a
// multiply-high by a magic reciprocal, in a different shape per divisor
// (the shapes are listed in MagicDivision.swift).
public func divideBySeven(_ a: Int) -> Int { a / 7 }
public func divideByThree(_ a: Int) -> Int { a / 3 }
public func divideByFifteen(_ a: Int) -> Int { a / 15 }
public func divideByMinusSeven(_ a: Int) -> Int { a / -7 }
public func remainderBySeven(_ a: Int) -> Int { a % 7 }
public func unsignedDivideBySeven(_ a: UInt) -> UInt { a / 7 }
public func unsignedDivideByThousand(_ a: UInt) -> UInt { a / 1000 }

// Identical code folding across vtables. At -O these classes' accessors are the
// same bytes, and LLVM's function merging gives them one body per accessor kind,
// which every class's method descriptors point at. Metadata then names one
// address once per class; a stripped binary must decline to pick one
// (MetadataNameOracleTests). With only two classes this compiler (Swift 6.3)
// keeps the bodies apart; the third makes the merge happen.
open class FoldLeft {
    open var count = 0
    public init() {}
}
open class FoldMiddle {
    open var amount = 0
    public init() {}
}
open class FoldRight {
    open var total = 0
    public init() {}
}

// Unsigned division on Int-typed operands: `udiv` where the Swift types are
// signed. A bare `/` would claim signed division, which disagrees at every
// negative input; the render must carry the unsigned operation.
public func unsignedQuotient(_ a: Int, _ b: Int) -> Int {
    Int(bitPattern: UInt(bitPattern: a) / UInt(bitPattern: b))
}
public func unsignedRemainderOf(_ a: Int, _ b: Int) -> Int {
    Int(bitPattern: UInt(bitPattern: a) % UInt(bitPattern: b))
}
